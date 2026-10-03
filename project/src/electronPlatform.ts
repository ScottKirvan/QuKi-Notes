/**
 * Renderer-side type for the platform bridge exposed by
 * project/electron/src/preload.ts (`contextBridge.exposeInMainWorld`).
 * Preload's sandboxed context still gets a real `process.platform` from
 * Electron (see preload.ts for the confirmation this doesn't need an IPC
 * round trip), so this is a plain value, not an API with methods like
 * electronAPI/electronSetupAPI.
 *
 * Used to gate Send (BEHAVIOR_SPEC.md §4 / STORAGE_CONTRACT.md's "share is
 * one action" section): only Linux has a built destination (clipboard)
 * today, so the button must stay disabled everywhere else rather than
 * silently falling back to clipboard on a platform that spec calls for
 * native share on instead.
 */
export {};

declare global {
  interface Window {
    /** Present only inside the Electron wrapper; absent in the plain web build. */
    electronPlatform?: NodeJS.Platform;
  }
}
