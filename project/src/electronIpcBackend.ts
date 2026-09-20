import type { FileStat, StorageBackend } from "quki-core";

/**
 * The renderer-side half of the Electron wrapper (see
 * project/electron/src/main.ts and preload.ts for the main-process half).
 * Every method but resolvePath is proxied over the ElectronStorageApi the
 * caller hands in (window.electronAPI in main.ts - see below), which the
 * preload script exposes via contextBridge; this file never touches Node
 * or Electron APIs directly, only that bridge surface. The api is passed
 * in rather than read from `window` internally so this class has no DOM
 * dependency and can be unit-tested in plain Node (see
 * electronIpcBackend.test.ts) - this project's tests run without a DOM,
 * matching its existing convention of covering DOM-touching wiring with
 * the Playwright e2e suite instead.
 *
 * resolvePath is synchronous on StorageBackend (core/src/storageBackend.ts
 * - QuKiStore.writeImage relies on getting the value back immediately, not
 * a Promise), so it alone is bridged over a synchronous IPC call
 * (ipcRenderer.sendSync, wrapped by the preload script) rather than the
 * async invoke() every other method uses.
 */
type AsyncStorageApi = {
  [K in keyof Omit<StorageBackend, "resolvePath">]: StorageBackend[K] extends (...args: infer A) => infer R
    ? (...args: A) => Promise<Awaited<R>>
    : never;
};

export type ElectronStorageApi = AsyncStorageApi & {
  resolvePath(relPath: string): string;
};

declare global {
  interface Window {
    /** Present only when running inside the Electron wrapper (see preload.ts); absent in the plain web build. */
    electronAPI?: ElectronStorageApi;
  }
}

export class ElectronIpcBackend implements StorageBackend {
  constructor(private readonly api: ElectronStorageApi) {}

  readText(relPath: string): Promise<string> {
    return this.api.readText(relPath);
  }

  writeTextAtomic(relPath: string, content: string): Promise<void> {
    return this.api.writeTextAtomic(relPath, content);
  }

  readBinary(relPath: string): Promise<Uint8Array> {
    return this.api.readBinary(relPath);
  }

  writeBinaryAtomic(relPath: string, content: Uint8Array): Promise<void> {
    return this.api.writeBinaryAtomic(relPath, content);
  }

  remove(relPath: string): Promise<void> {
    return this.api.remove(relPath);
  }

  rename(fromRelPath: string, toRelPath: string): Promise<void> {
    return this.api.rename(fromRelPath, toRelPath);
  }

  exists(relPath: string): Promise<boolean> {
    return this.api.exists(relPath);
  }

  stat(relPath: string): Promise<FileStat> {
    return this.api.stat(relPath);
  }

  listDir(relDir: string): Promise<string[]> {
    return this.api.listDir(relDir);
  }

  mkdirp(relDir: string): Promise<void> {
    return this.api.mkdirp(relDir);
  }

  resolvePath(relPath: string): string {
    return this.api.resolvePath(relPath);
  }
}
