export type ServiceWorkerAction = "register" | "unregisterStale" | "none";

export interface ServiceWorkerPlatform {
  isCapacitorNative: boolean;
  isElectron: boolean;
}

// Electron clears stale registrations from its main process before the page
// loads (electron/src/serviceWorkerStorage.ts), so its renderer does nothing.
export function serviceWorkerAction(platform: ServiceWorkerPlatform): ServiceWorkerAction {
  if (platform.isCapacitorNative) return "unregisterStale";
  if (platform.isElectron) return "none";
  return "register";
}
