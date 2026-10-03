/**
 * Renderer-side type for the Settings -> Export IPC bridge (see
 * project/electron/src/main.ts and preload.ts for the main-process half).
 * Kept independent of that package's own types rather than imported from
 * it - matching electronIpcBackend.ts's and electronSetupApi.ts's existing
 * convention of not importing across the renderer/electron package
 * boundary.
 */
export interface ElectronExportApi {
  /** Opens the native "Save As" dialog and writes `bytes` there. Resolves to the chosen absolute path, or null if the dialog was cancelled. */
  saveExport(bytes: Uint8Array, defaultFileName: string): Promise<string | null>;
}

declare global {
  interface Window {
    /**
     * Present only when running inside the Electron wrapper (see
     * preload.ts); absent in the plain web build, exactly like
     * window.electronAPI (electronIpcBackend.ts) and window.electronSetupAPI
     * (electronSetupApi.ts).
     */
    electronExportAPI?: ElectronExportApi;
  }
}
