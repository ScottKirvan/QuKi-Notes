/**
 * A native Capacitor build briefly registered a service worker before this
 * app stopped doing so on native platforms (see main.ts's own
 * `!Capacitor.isNativePlatform()` gate around registerSW) - registering
 * nothing new does not unregister an old one. A device that ran one of
 * those earlier builds keeps that stale registration controlling the page
 * and serving whatever it precached indefinitely, regardless of what a
 * later APK update actually contains.
 *
 * Kept pure and deps-injected, the same pattern as
 * androidStorageAccess.ts/androidFlutterMigration.ts, so it is
 * unit-testable without a real ServiceWorkerContainer or Cache Storage.
 * main.ts calls this unconditionally on every native launch - cheap and a
 * no-op when nothing is registered, so there is no need to track whether it
 * has already run.
 */

export interface StaleServiceWorkerRegistration {
  unregister(): Promise<boolean>;
}

export interface StaleServiceWorkerCleanupDeps {
  getRegistrations(): Promise<readonly StaleServiceWorkerRegistration[]>;
  cacheKeys(): Promise<readonly string[]>;
  deleteCache(key: string): Promise<boolean>;
}

export async function cleanupStaleServiceWorker(deps: StaleServiceWorkerCleanupDeps): Promise<void> {
  const registrations = await deps.getRegistrations();
  await Promise.all(registrations.map((registration) => registration.unregister()));

  const keys = await deps.cacheKeys();
  await Promise.all(keys.map((key) => deps.deleteCache(key)));
}
