import * as fs from 'node:fs';
import * as http from 'node:http';
import * as path from 'node:path';

import { app, BrowserWindow, dialog, ipcMain, screen } from 'electron';
// quki-core is ESM-only; under Node16 module resolution a CommonJS file
// importing *types* from an ESM package must say which condition
// ("import") to resolve them under (TS1542) - this has no runtime effect,
// it only tells tsc which of quki-core's package.json export conditions to
// read the .d.ts from.
import type { StorageBackend } from 'quki-core' with { 'resolution-mode': 'import' };

import { resolveMigratedStorageRoot } from './flutterMigration.js';
import { PreferencesStore } from './preferences.js';
import { isValidWritableDirectory } from './storageValidation.js';
import { RESOLVE_PATH_SYNC_CHANNEL, SETUP_CHANNELS, STORAGE_CHANNELS, type ResolvePathSyncResult } from './storageIpc.js';

// Applies a caller-chosen userData directory before anything reads
// app.getPath('userData') - must run at module load, before app.whenReady(),
// or Electron will have already resolved the real default. This is a
// test-only seam (see e2e/electron.e2e.ts): it is how a Playwright run gets
// a genuinely fresh app with no prior preferences.json, without touching
// the developer's real Electron profile.
const userDataOverride = process.env.QUKI_ELECTRON_USERDATA_DIR;
if (userDataOverride) {
  app.setPath('userData', userDataOverride);
}

// Same seam, for app.getPath('documents'): "Use app storage" now resolves
// under Documents (see resolveAppStorageDir below), and Flutter-migration
// detection (flutterMigration.ts) checks that same folder for pre-existing
// QuKis - neither must ever touch a real developer machine's real Documents
// folder during a Playwright run.
const documentsOverride = process.env.QUKI_ELECTRON_DOCUMENTS_DIR;
if (documentsOverride) {
  app.setPath('documents', documentsOverride);
}

// This package builds to CommonJS (see tsconfig.json / the report: Electron's
// ESM main-process loader crashes on `import ... from 'electron'` itself on
// the installed Electron version, independent of anything here - a plain
// CommonJS main process sidesteps that entirely). __dirname is CommonJS's
// own ambient global, unlike an ESM main process which would need the
// import.meta.url workaround.

// The renderer (project/src, the same web app OpfsBackend already serves)
// is unmodified by this wrapper. project/dist is its production build,
// already proven by `npm run build` at the project root.
// In a packaged build, extraResources copies project/dist → resources/webdist.
// In dev, __dirname is project/electron/dist/ so ../../dist is project/dist/.
const RENDERER_DIST_DIR = app.isPackaged
  ? path.join(process.resourcesPath, 'webdist')
  : path.join(__dirname, '..', '..', 'dist');

/**
 * Matches the Flutter app's own "app storage" convention exactly:
 * getApplicationDocumentsDirectory()/qukis (lib/main.dart), which on Windows
 * and Linux resolves to the real, user-visible Documents folder - not a
 * hidden app-data directory (confirmed by reading path_provider_windows's
 * and path_provider_linux's actual source, not assumed). A fresh install's
 * "Use app storage" choice must land in the same folder a migrating Flutter
 * app-storage user's QuKis already occupy - see STORAGE_CONTRACT.md's
 * migration section and flutterMigration.ts.
 */
function resolveAppStorageDir(): string {
  return path.join(app.getPath('documents'), 'qukis');
}

// quki-core is ESM-only (project/core/package.json has no CommonJS entry
// point), and a CommonJS module can't `require()` an ESM file - only
// `import()` it dynamically, which Node supports natively even from CJS.
// `backend` stays undefined until a storage root is known - either from a
// previously-chosen preference, the QUKI_ELECTRON_DIR dev/test override
// below, or a choice made on the setup screen - so no file operation can
// run before a location exists (BEHAVIOR_SPEC.md §3).
let backend: StorageBackend | undefined;
let currentRoot: string | null = null;

/**
 * Set only when app.whenReady() found a previously-chosen storagePath in
 * this app's own preferences.json that failed isValidWritableDirectory at
 * this launch - see the app.whenReady() handler below and
 * SETUP_CHANNELS.getState's handler. Cleared the moment any real storage
 * root is actually set, so a subsequent successful choice (or a later
 * launch where the folder is reachable again) stops reporting it.
 */
let unreachableStoragePath: string | null = null;

async function setBackendRoot(root: string): Promise<void> {
  const { NodeFsBackend } = await import('quki-core/node');
  const next = new NodeFsBackend(root);
  await next.mkdirp('');
  backend = next;
  currentRoot = root;
  unreachableStoragePath = null;
}

function requireBackend(): StorageBackend {
  if (!backend) {
    throw new Error('QuKi storage backend used before a storage location was chosen');
  }
  return backend;
}

function registerStorageIpc(): void {
  ipcMain.handle(STORAGE_CHANNELS.readText, (_event, relPath: string) => requireBackend().readText(relPath));
  ipcMain.handle(STORAGE_CHANNELS.writeTextAtomic, (_event, relPath: string, content: string) =>
    requireBackend().writeTextAtomic(relPath, content),
  );
  ipcMain.handle(STORAGE_CHANNELS.readBinary, (_event, relPath: string) => requireBackend().readBinary(relPath));
  ipcMain.handle(STORAGE_CHANNELS.writeBinaryAtomic, (_event, relPath: string, content: Uint8Array) =>
    requireBackend().writeBinaryAtomic(relPath, content),
  );
  ipcMain.handle(STORAGE_CHANNELS.remove, (_event, relPath: string) => requireBackend().remove(relPath));
  ipcMain.handle(STORAGE_CHANNELS.rename, (_event, fromRelPath: string, toRelPath: string) =>
    requireBackend().rename(fromRelPath, toRelPath),
  );
  ipcMain.handle(STORAGE_CHANNELS.exists, (_event, relPath: string) => requireBackend().exists(relPath));
  ipcMain.handle(STORAGE_CHANNELS.stat, (_event, relPath: string) => requireBackend().stat(relPath));
  ipcMain.handle(STORAGE_CHANNELS.listDir, (_event, relDir: string) => requireBackend().listDir(relDir));
  ipcMain.handle(STORAGE_CHANNELS.mkdirp, (_event, relDir: string) => requireBackend().mkdirp(relDir));

  // See storageIpc.ts: resolvePath is the one StorageBackend method that is
  // synchronous by contract, so it can't go through ipcMain.handle (always
  // async). sendSync blocks the renderer until this returns, which is
  // acceptable here because it is called once per image paste/write, not on
  // a hot path.
  ipcMain.on(RESOLVE_PATH_SYNC_CHANNEL, (event, relPath: string) => {
    try {
      const value = requireBackend().resolvePath(relPath);
      event.returnValue = { ok: true, value } satisfies ResolvePathSyncResult;
    } catch (error) {
      event.returnValue = {
        ok: false,
        message: error instanceof Error ? error.message : String(error),
      } satisfies ResolvePathSyncResult;
    }
  });
}

function registerSetupIpc(prefsStore: PreferencesStore): void {
  ipcMain.handle(SETUP_CHANNELS.getState, () => ({
    chosen: backend !== undefined,
    path: currentRoot,
    isAppStorage: currentRoot !== null && currentRoot === resolveAppStorageDir(),
    unreachablePath: unreachableStoragePath,
  }));

  // [Proposed — unconfirmed] The renderer's recovery screen (see
  // src/main.ts's init()) offers a cancel option there rather than forcing
  // an immediate re-choice, since the previously-chosen folder may come
  // back on its own (a drive gets plugged back in, a network share gets
  // remounted) without the user wanting to pick a different one right now.
  // But the app cannot usefully run with no storage backend at all -
  // every read/write would fail - so declining is wired to quitting
  // cleanly instead of falling through into a broken editor. The user can
  // just relaunch once the location is reachable again.
  ipcMain.handle(SETUP_CHANNELS.quit, () => {
    app.quit();
  });

  ipcMain.handle(SETUP_CHANNELS.chooseAppStorage, async () => {
    const dir = resolveAppStorageDir();
    await setBackendRoot(dir);
    prefsStore.setStorageLocation(dir);
    return dir;
  });

  ipcMain.handle(SETUP_CHANNELS.chooseFilesystem, async () => {
    // Test-only seam (see e2e/electron.e2e.ts): Playwright cannot drive an
    // OS-native directory picker, so a test run sets this env var to stand
    // in for the user's choice instead of opening the real dialog. Empty
    // string stands in for the user cancelling the picker.
    const forcedPath = process.env.QUKI_TEST_FORCE_DIALOG_PATH;
    let selected: string | null;
    if (forcedPath !== undefined) {
      selected = forcedPath === '' ? null : forcedPath;
    } else {
      const win = BrowserWindow.getFocusedWindow();
      const result = win
        ? await dialog.showOpenDialog(win, { properties: ['openDirectory'] })
        : await dialog.showOpenDialog({ properties: ['openDirectory'] });
      selected = result.canceled || result.filePaths.length === 0 ? null : result.filePaths[0]!;
    }
    if (selected === null) return null;
    await setBackendRoot(selected);
    prefsStore.setStorageLocation(selected);
    return selected;
  });
}

const CONTENT_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.map': 'application/json; charset=utf-8',
};

/**
 * The renderer's production build uses root-absolute asset URLs
 * (/assets/...), which a bare `file://` load can't resolve correctly.
 * Serving project/dist over a local loopback HTTP server - the same
 * approach e2e/persistence.e2e.ts already uses to drive the web build with
 * Playwright - sidesteps that without changing how the renderer is built.
 */
function serveRendererDist(): Promise<{ server: http.Server; url: string }> {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(RENDERER_DIST_DIR)) {
      reject(new Error(`Renderer build not found at ${RENDERER_DIST_DIR} - run "npm run build" in project/ first`));
      return;
    }
    const server = http.createServer((req, res) => {
      const reqPath = (req.url ?? '/').split('?')[0]!;
      const filePath = path.join(RENDERER_DIST_DIR, reqPath === '/' ? 'index.html' : reqPath);
      if (!filePath.startsWith(RENDERER_DIST_DIR)) {
        res.writeHead(403).end();
        return;
      }
      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(404).end();
          return;
        }
        const ext = path.extname(filePath);
        res.writeHead(200, { 'content-type': CONTENT_TYPES[ext] ?? 'application/octet-stream' });
        res.end(data);
      });
    });
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (address === null || typeof address === 'string') {
        reject(new Error('failed to bind renderer static server'));
        return;
      }
      resolve({ server, url: `http://127.0.0.1:${address.port}` });
    });
  });
}

let rendererServer: http.Server | null = null;

const DEFAULT_WINDOW_WIDTH = 1100;
const DEFAULT_WINDOW_HEIGHT = 800;

// BEHAVIOR_SPEC.md §10: "saved on move, resize and close - on the
// completed-gesture events, not continuously, so a drag doesn't hammer the
// preference store." 500ms of silence after the last continuous move/resize
// event is the fallback signal for "gesture completed" (see
// attachWindowBoundsPersistence below for why a fallback is needed at all).
const WINDOW_BOUNDS_SAVE_DEBOUNCE_MS = 500;

interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

function rectsIntersect(a: Rect, b: Rect): boolean {
  return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
}

/**
 * [Proposed — unconfirmed] Not spec'd: BEHAVIOR_SPEC.md §10 says to restore
 * saved bounds but doesn't say what to do when the saved rectangle no longer
 * overlaps any connected display (e.g. bounds saved from a docked
 * multi-monitor setup, later launched with only the laptop's own screen
 * connected) - Electron does not clamp this itself, and restoring bounds
 * with no on-screen overlap at all would place the window somewhere the
 * user cannot see or reach it. Treating that case the same as "bounds
 * missing" (falls through to the OS-placed default) seems the safer
 * default; flagged as a proposal since Scott hasn't confirmed it.
 */
function isOnAnyDisplay(bounds: Rect): boolean {
  return screen.getAllDisplays().some((display) => rectsIntersect(bounds, display.workArea));
}

function resolveInitialWindowBounds(prefsStore: PreferencesStore): Partial<Rect> {
  const prefs = prefsStore.read();
  const { windowX, windowY, windowWidth, windowHeight } = prefs;
  if (windowX === null || windowY === null || windowWidth === null || windowHeight === null) {
    return {};
  }
  const bounds: Rect = { x: windowX, y: windowY, width: windowWidth, height: windowHeight };
  return isOnAnyDisplay(bounds) ? bounds : {};
}

/**
 * Saves window bounds on move/resize/close per BEHAVIOR_SPEC.md §10, without
 * writing to the preference store on every frame of a drag.
 *
 * Electron does provide a true "gesture completed" signal - 'moved' and
 * 'resized' fire once, after the user finishes dragging/resizing - but this
 * project's installed Electron (33.4.11, see electron.d.ts) documents both
 * as `@platform darwin,win32` only. Neither is available on Linux, which
 * BEHAVIOR_SPEC.md §10 explicitly covers alongside Windows. So both
 * mechanisms are wired here: 'moved'/'resized' save immediately on win32
 * (pre-empting the debounce, no extra delay), and the debounced
 * 'move'/'resize' handlers are what actually cover Linux, where 'moved'/
 * 'resized' never fire at all.
 */
function attachWindowBoundsPersistence(win: BrowserWindow, prefsStore: PreferencesStore): void {
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;

  const saveNow = (): void => {
    if (debounceTimer) {
      clearTimeout(debounceTimer);
      debounceTimer = null;
    }
    if (win.isDestroyed() || win.isMinimized()) return;
    prefsStore.setWindowBounds(win.getBounds());
  };

  const scheduleSave = (): void => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(saveNow, WINDOW_BOUNDS_SAVE_DEBOUNCE_MS);
  };

  win.on('move', scheduleSave);
  win.on('resize', scheduleSave);
  win.on('moved', saveNow);
  win.on('resized', saveNow);
  win.on('close', saveNow);
}

async function createWindow(prefsStore: PreferencesStore): Promise<BrowserWindow> {
  const win = new BrowserWindow({
    width: DEFAULT_WINDOW_WIDTH,
    height: DEFAULT_WINDOW_HEIGHT,
    ...resolveInitialWindowBounds(prefsStore),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  attachWindowBoundsPersistence(win, prefsStore);

  // Vite dev-server workflow (see project/scripts/electron-dev.mjs): when
  // set, load the live dev server instead of the static production build.
  const devServerUrl = process.env.ELECTRON_RENDERER_URL;
  if (devServerUrl) {
    await win.loadURL(devServerUrl);
  } else {
    const { server, url } = await serveRendererDist();
    rendererServer = server;
    await win.loadURL(url);
  }

  return win;
}

app.whenReady().then(async () => {
  const prefsStore = new PreferencesStore(app.getPath('userData'));

  // QUKI_ELECTRON_DIR is a dev/test override predating the setup screen
  // (chunk 1's Playwright proof still points this at a throwaway temp dir -
  // see e2e/electron.e2e.ts). When set, it bypasses preferences.json
  // entirely, both read and write: it must behave exactly as it did before
  // this chunk (straight to the editor, no setup screen), and a real
  // preferences file must never end up pointing at a temp directory an e2e
  // run is about to delete.
  const forcedRoot = process.env.QUKI_ELECTRON_DIR;
  if (forcedRoot) {
    await setBackendRoot(forcedRoot);
  } else {
    const prefs = prefsStore.read();
    if (prefs.storageChosen && prefs.storagePath) {
      // Re-validate on every normal launch, not just once at the moment the
      // choice was made - the folder a user already chose can stop being
      // reachable at any later launch (drive unplugged, folder moved or
      // deleted, network share not yet mounted). Without this,
      // setBackendRoot -> NodeFsBackend.mkdirp('') would silently create a
      // fresh empty directory at the stale path and open it as though it
      // were the user's whole library - every single launch,
      // indistinguishable from "you have no QuKis".
      if (isValidWritableDirectory(prefs.storagePath)) {
        await setBackendRoot(prefs.storagePath);
      } else {
        // Leave backend unset and remember why: the renderer's setup gate
        // (src/main.ts's init()) uses quki:setup:getState's unreachablePath
        // to show a distinct recovery screen instead of either (a) silently
        // adopting an empty folder or (b) the plain first-launch setup
        // copy, which would wrongly read to an established user as "your
        // whole library is gone". The stored preference itself is left
        // untouched - the folder is very likely still there, just not
        // reachable from this launch.
        unreachableStoragePath = prefs.storagePath;
      }
    } else {
      // No choice recorded in this app's own preferences yet - before
      // falling through to the setup screen, check whether this is really
      // an existing Flutter-app user upgrading in place (BEHAVIOR_SPEC.md
      // §1, STORAGE_CONTRACT.md's migration section): adopt their folder
      // silently rather than making them choose again.
      const migratedRoot = resolveMigratedStorageRoot({
        platform: process.platform,
        env: process.env,
        appStorageDir: resolveAppStorageDir(),
      });
      if (migratedRoot) {
        await setBackendRoot(migratedRoot);
        prefsStore.setStorageLocation(migratedRoot);
      }
      // Otherwise backend stays unset - genuine first launch. The renderer
      // asks quki:setup:getState, finds nothing chosen, and shows the setup
      // screen; choosing a card calls chooseAppStorage/chooseFilesystem
      // below, which is what actually sets the backend root.
    }
  }

  registerStorageIpc();
  registerSetupIpc(prefsStore);
  await createWindow(prefsStore);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) void createWindow(prefsStore);
  });
});

app.on('window-all-closed', () => {
  rendererServer?.close();
  if (process.platform !== 'darwin') app.quit();
});
