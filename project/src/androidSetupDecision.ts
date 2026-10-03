/**
 * The precedence this task's brief specifies for resolving Android's storage
 * location at launch, kept pure and deps-injected - same pattern as
 * androidStorageAccess.ts's createStorageAccessGate and
 * androidFlutterMigration.ts's resolveMigratedStorageRoot - so it is
 * unit-testable without Capacitor, native I/O, or the DOM. androidSetupApi.ts
 * wires this to the real settings file (androidSettingsStore.ts) and the
 * real migration detection (androidFlutterMigration.ts).
 *
 * Order, matching Electron's own app.whenReady() precedence
 * (electron/src/main.ts) as closely as the two platforms' mechanisms allow:
 *
 *  1. The new Android settings file already recorded a chosen path - use it
 *     if it still validates, otherwise this is the "unreachable" recovery
 *     case (a returning user, not a fresh install).
 *  2. No settings-file choice yet, but the existing Flutter-migration
 *     detection finds a path - adopt it silently and persist it into the
 *     settings file, so this is a one-time detection rather than
 *     re-detecting on every launch (STORAGE_CONTRACT.md's migration
 *     section).
 *  3. Neither - a genuine fresh install with nothing to adopt. The caller
 *     shows the first-launch two-choice screen.
 */

export type AndroidSetupOutcome =
  | { kind: "use-path"; path: string }
  | { kind: "recovery"; unreachablePath: string }
  | { kind: "first-launch" };

export interface AndroidSetupDecisionDeps {
  readSettings(): Promise<{ storagePath: string | null; storageChosen: boolean }>;
  writeSettings(settings: { storagePath: string; storageChosen: boolean }): Promise<void>;
  isValidWritableDirectory(path: string): Promise<boolean>;
  resolveMigratedStorageRoot(): Promise<string | null>;
}

export async function decideAndroidStorageSetup(deps: AndroidSetupDecisionDeps): Promise<AndroidSetupOutcome> {
  const settings = await deps.readSettings();
  if (settings.storageChosen && settings.storagePath !== null) {
    if (await deps.isValidWritableDirectory(settings.storagePath)) {
      return { kind: "use-path", path: settings.storagePath };
    }
    return { kind: "recovery", unreachablePath: settings.storagePath };
  }

  const migratedPath = await deps.resolveMigratedStorageRoot();
  if (migratedPath !== null) {
    await deps.writeSettings({ storagePath: migratedPath, storageChosen: true });
    return { kind: "use-path", path: migratedPath };
  }

  return { kind: "first-launch" };
}
