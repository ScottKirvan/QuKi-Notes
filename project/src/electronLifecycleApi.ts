/**
 * Renderer-side type for the quit-time flush handshake IPC bridge (see
 * project/electron/src/main.ts's attachQuitFlush and preload.ts for the
 * main-process half). Kept independent of that package's own types rather
 * than imported from it - matching electronIpcBackend.ts's and
 * electronSetupApi.ts's existing convention of not importing across the
 * renderer/electron package boundary.
 */
export interface ElectronLifecycleApi {
  /**
   * Registers callback to run when the main process is about to close the
   * window and needs the renderer's pending auto-save flushed first. The
   * main process defers the actual window close until callback's promise
   * settles (or a fallback timeout elapses) - see main.ts's attachQuitFlush.
   */
  onFlushBeforeQuit(callback: () => Promise<void>): void;
}

declare global {
  interface Window {
    /**
     * Present only when running inside the Electron wrapper (see
     * preload.ts); absent in the plain web build, exactly like
     * window.electronAPI (electronIpcBackend.ts).
     */
    electronLifecycleAPI?: ElectronLifecycleApi;
  }
}
