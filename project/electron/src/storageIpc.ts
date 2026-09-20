/**
 * Shared shape for the IPC surface bridging the renderer's ElectronIpcBackend
 * (project/src/electronIpcBackend.ts) to the main process's real
 * NodeFsBackend. Both main.ts (which implements this over ipcMain) and the
 * renderer's backend (which implements StorageBackend by calling this over
 * window.electronAPI) are typed off the same quki-core StorageBackend
 * interface, so a change to that interface surfaces as a type error on both
 * ends rather than a silent drift.
 *
 * Every StorageBackend method is already async except resolvePath, which
 * QuKiStore's callers (see core/src/media.ts) rely on getting back
 * synchronously. ipcMain.handle/ipcRenderer.invoke are always async, so
 * resolvePath is bridged separately over ipcRenderer.sendSync instead of
 * this async map - see main.ts and preload.ts.
 */
// See main.ts for why this needs an explicit resolution-mode attribute.
import type { StorageBackend } from 'quki-core' with { 'resolution-mode': 'import' };

export type AsyncStorageApi = {
  [K in keyof Omit<StorageBackend, 'resolvePath'>]: StorageBackend[K] extends (...args: infer A) => infer R
    ? (...args: A) => Promise<Awaited<R>>
    : never;
};

export type ElectronStorageApi = AsyncStorageApi & {
  resolvePath(relPath: string): string;
};

export const STORAGE_CHANNELS: { [K in keyof AsyncStorageApi]: string } = {
  readText: 'quki:readText',
  writeTextAtomic: 'quki:writeTextAtomic',
  readBinary: 'quki:readBinary',
  writeBinaryAtomic: 'quki:writeBinaryAtomic',
  remove: 'quki:remove',
  rename: 'quki:rename',
  exists: 'quki:exists',
  stat: 'quki:stat',
  listDir: 'quki:listDir',
  mkdirp: 'quki:mkdirp',
};

export const RESOLVE_PATH_SYNC_CHANNEL = 'quki:resolvePathSync';

export type ResolvePathSyncResult = { ok: true; value: string } | { ok: false; message: string };

/**
 * The setup/preferences IPC surface (BEHAVIOR_SPEC.md §3): whether a
 * storage location has ever been chosen, and the two ways of choosing one.
 * Channel names are duplicated as string literals in preload.ts rather than
 * importing SETUP_CHANNELS at runtime - see preload.ts's top comment for why
 * (the sandboxed preload context can't require() this package's own
 * compiled sibling files).
 */
export const SETUP_CHANNELS = {
  getState: 'quki:setup:getState',
  chooseFilesystem: 'quki:setup:chooseFilesystem',
  chooseAppStorage: 'quki:setup:chooseAppStorage',
  quit: 'quki:setup:quit',
} as const;

export interface StorageLocationState {
  chosen: boolean;
  path: string | null;
  /**
   * Set when this app's own preferences.json already recorded a chosen
   * storagePath but it failed re-validation at this launch (folder moved,
   * deleted, or its drive/network share not currently reachable) - see
   * main.ts's app.whenReady() handler. null in every other case, including
   * genuine first launch. The renderer uses this to tell the two "no
   * backend yet" situations apart: a brand-new user (nothing recorded) vs.
   * a returning user whose folder just isn't reachable *right now*.
   */
  unreachablePath: string | null;
}
