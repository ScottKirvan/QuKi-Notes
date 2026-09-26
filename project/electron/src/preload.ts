/**
 * Runs in the sandboxed preload context - BrowserWindow is created with
 * sandbox: true (main.ts). Electron's sandboxed preload loader intercepts
 * require() and only allows a small allowlist of built-ins (electron,
 * events, timers, ...); it cannot require() this package's own compiled
 * sibling files (confirmed by actually running it - a require('./storageIpc.js')
 * here fails with "module not found" even though the file exists on disk
 * and an unsandboxed script could load it fine). So this file is
 * deliberately self-contained: no local runtime imports, only `electron`
 * (which the sandbox does allow) and type-only imports from storageIpc.ts
 * (erased at compile time, so they never reach require() at all). The
 * channel name literals below are the runtime cost of that constraint -
 * they must stay in sync with storageIpc.ts's STORAGE_CHANNELS /
 * RESOLVE_PATH_SYNC_CHANNEL, which main.ts (not sandboxed) still imports
 * directly as its single source of truth.
 */
import { contextBridge, ipcRenderer } from 'electron';

import type { ElectronStorageApi, ResolvePathSyncResult, StorageLocationState } from './storageIpc.js';

const RESOLVE_PATH_SYNC_CHANNEL = 'quki:resolvePathSync';

const api: ElectronStorageApi = {
  readText: (relPath: string) => ipcRenderer.invoke('quki:readText', relPath),
  writeTextAtomic: (relPath: string, content: string) => ipcRenderer.invoke('quki:writeTextAtomic', relPath, content),
  readBinary: (relPath: string) => ipcRenderer.invoke('quki:readBinary', relPath),
  writeBinaryAtomic: (relPath: string, content: Uint8Array) => ipcRenderer.invoke('quki:writeBinaryAtomic', relPath, content),
  remove: (relPath: string) => ipcRenderer.invoke('quki:remove', relPath),
  rename: (fromRelPath: string, toRelPath: string) => ipcRenderer.invoke('quki:rename', fromRelPath, toRelPath),
  exists: (relPath: string) => ipcRenderer.invoke('quki:exists', relPath),
  stat: (relPath: string) => ipcRenderer.invoke('quki:stat', relPath),
  listDir: (relDir: string) => ipcRenderer.invoke('quki:listDir', relDir),
  mkdirp: (relDir: string) => ipcRenderer.invoke('quki:mkdirp', relDir),
  resolvePath: (relPath: string) => {
    const result = ipcRenderer.sendSync(RESOLVE_PATH_SYNC_CHANNEL, relPath) as ResolvePathSyncResult;
    if (!result.ok) throw new Error(result.message);
    return result.value;
  },
};

contextBridge.exposeInMainWorld('electronAPI', api);

/**
 * Send (STORAGE_CONTRACT.md: "share is one action with no picker... copy
 * to clipboard on Linux") needs to know which OS it's running on to decide
 * whether a destination exists at all - only Linux's clipboard destination
 * is built. `process.platform` is available here even under sandbox: true
 * (Electron's sandboxed preload/renderer process object still carries
 * platform/versions/type, unlike Node built-ins, which are what the
 * sandbox actually blocks) - confirmed by this preload script's own
 * existing pattern above, which already relies on a working `process`-free
 * bridge for everything else without needing a round trip through
 * ipcRenderer for a value this static.
 *
 * QUKI_TEST_FORCE_PLATFORM is a test-only seam (see e2e/send.e2e.ts),
 * matching this project's existing QUKI_ELECTRON_DIR / QUKI_TEST_FORCE_DIALOG_PATH
 * pattern: Playwright always drives this app on whatever OS the CI/dev
 * machine actually is, so the Linux-only Send path needs a way to be
 * exercised for real without an actual Linux box. process.env is readable
 * here for the same reason process.platform is - it isn't a Node built-in.
 */
contextBridge.exposeInMainWorld('electronPlatform', process.env.QUKI_TEST_FORCE_PLATFORM ?? process.platform);

/**
 * The setup/preferences bridge (BEHAVIOR_SPEC.md §3), exposed separately
 * from `electronAPI` above rather than folded into it - it is not part of
 * the StorageBackend surface and callers (src/main.ts, setupView.ts) treat
 * "is this running in Electron" and "has a storage location been chosen
 * yet" as two different questions.
 */
export interface ElectronSetupApi {
  getState(): Promise<StorageLocationState>;
  /** Resolves to the chosen absolute path, or null if the native picker was cancelled. */
  chooseFilesystem(): Promise<string | null>;
  chooseAppStorage(): Promise<string>;
  /**
   * Quits the app. Used only by the recovery setup screen (see
   * src/main.ts's init() and storageIpc.ts's StorageLocationState) when the
   * user declines to choose a new location for a previously-configured
   * folder that isn't currently reachable - see main.ts's
   * SETUP_CHANNELS.quit handler for why declining quits rather than
   * proceeding with no storage backend.
   */
  quit(): Promise<void>;
}

const setupApi: ElectronSetupApi = {
  getState: () => ipcRenderer.invoke('quki:setup:getState'),
  chooseFilesystem: () => ipcRenderer.invoke('quki:setup:chooseFilesystem'),
  chooseAppStorage: () => ipcRenderer.invoke('quki:setup:chooseAppStorage'),
  quit: () => ipcRenderer.invoke('quki:setup:quit'),
};

contextBridge.exposeInMainWorld('electronSetupAPI', setupApi);
