/**
 * Renderer-side type for the setup/preferences IPC bridge (see
 * project/electron/src/main.ts and preload.ts for the main-process half).
 * Kept independent of that package's own types rather than imported from
 * it - matching electronIpcBackend.ts's existing convention of not
 * importing across the renderer/electron package boundary.
 */
export interface StorageLocationState {
  chosen: boolean;
  path: string | null;
  /** Whether `path` is the app's own private-storage default, not a user-picked folder. Meaningless when `path` is null. */
  isAppStorage: boolean;
  /**
   * Set when this app's own preferences.json already recorded a chosen
   * storagePath but it failed re-validation at this launch (see
   * project/electron/src/main.ts's app.whenReady() handler) - a returning
   * user whose folder isn't reachable right now, not a genuine first
   * launch. null in every other case.
   */
  unreachablePath: string | null;
}

export interface ElectronSetupApi {
  getState(): Promise<StorageLocationState>;
  /** Resolves to the chosen absolute path, or null if the native picker was cancelled. */
  chooseFilesystem(): Promise<string | null>;
  chooseAppStorage(): Promise<string>;
  /** Quits the app - see the recovery flow in main.ts's init(). */
  quit(): Promise<void>;
}

declare global {
  interface Window {
    /**
     * Present only when running inside the Electron wrapper (see
     * preload.ts); absent in the plain web build, exactly like
     * window.electronAPI (electronIpcBackend.ts).
     */
    electronSetupAPI?: ElectronSetupApi;
  }
}
