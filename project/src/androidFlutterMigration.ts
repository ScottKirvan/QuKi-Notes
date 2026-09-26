/**
 * STORAGE_CONTRACT.md's migration section: "The existing folder opens as-is.
 * Onboarding points the new app at the same folder; nothing is converted,
 * renamed or rewritten... Existing users update in place." This is the
 * Android counterpart of project/electron/src/flutterMigration.ts - same
 * intent (BEHAVIOR_SPEC.md's adoptAppStorageIfUpgrading, mirrored from
 * lib/core/storage/storage_location_service.dart), different mechanism:
 * Electron reads a JSON file directly; Android has no filesystem access from
 * inside the WebView, so every real read here crosses the Capacitor bridge
 * into StoragePlugin.kt's getFlutterMigrationInfo/isValidWritableDirectory
 * (real Context.getSharedPreferences/File calls - see that file's doc
 * comments for the exact APIs and the pub-cache source that confirmed them).
 *
 * Kept deps-injected and platform/Capacitor-free, the same way
 * androidStorageAccess.ts's createStorageAccessGate is, so the decision
 * logic is unit-testable without any native plugin or DOM involved.
 */

export interface FlutterMigrationChoice {
  basePath: string;
}

export interface AndroidFlutterMigrationDeps {
  /** StoragePlugin.kt's getFlutterMigrationInfo - real SharedPreferences + real app-documents-path lookup. */
  getFlutterMigrationInfo(): Promise<{ locationChosen: boolean; basePath: string | null; appDocumentsPath: string }>;
  /** StoragePlugin.kt's isValidWritableDirectory - a real write-probe, not a permissions-bit check. */
  isValidWritableDirectory(path: string): Promise<boolean>;
  /** The existing generic Storage plugin's listDir, reused as-is (see CapacitorStoragePlugin.listDir). */
  listDir(path: string): Promise<string[]>;
}

/**
 * Joins an already-known-absolute Android directory with a single path
 * segment. Deliberately minimal (no `..`/`.` handling, unlike
 * capacitorBackend.ts's posixResolve) - the one caller below only ever joins
 * a plugin-reported absolute directory with the literal segment "qukis".
 */
function posixJoin(dir: string, segment: string): string {
  return dir.endsWith("/") ? `${dir}${segment}` : `${dir}/${segment}`;
}

/**
 * STORAGE_CONTRACT.md rule 9: the folder is flat, so this checks direct
 * children only - never recurses. A rejected/failed listDir call (e.g. the
 * path doesn't exist) is treated the same as "no markdown file here", never
 * thrown - matching flutterMigration.ts's folderHasMarkdownFile.
 */
export async function folderHasMarkdownFile(deps: AndroidFlutterMigrationDeps, dir: string): Promise<boolean> {
  let entries: string[];
  try {
    entries = await deps.listDir(dir);
  } catch {
    return false;
  }
  return entries.some((entry) => entry.toLowerCase().endsWith(".md"));
}

/**
 * Reads the Flutter app's real shared_preferences and extracts an
 * explicitly-chosen storage location, if any - the Android equivalent of
 * flutterMigration.ts's readFlutterMigrationChoice, minus the file-parsing
 * (StoragePlugin.kt's getFlutterMigrationInfo already did that, through the
 * real SharedPreferences API rather than hand-parsed XML).
 */
export async function readFlutterMigrationChoice(deps: AndroidFlutterMigrationDeps): Promise<FlutterMigrationChoice | null> {
  const info = await deps.getFlutterMigrationInfo();
  if (info.locationChosen && info.basePath) return { basePath: info.basePath };
  return null;
}

/**
 * The one entry point main.ts calls, mirroring
 * flutterMigration.ts's resolveMigratedStorageRoot exactly in shape and
 * precedence:
 *
 *  1. The Flutter app explicitly recorded a chosen location - adopt it,
 *     whatever it is (its own app-storage default, or a filesystem folder
 *     the user picked via "Filesystem storage"), provided it still
 *     validates (isValidWritableDirectory).
 *  2. No recorded choice, but the Flutter app-storage default folder
 *     (<appDocumentsPath>/qukis, matching lib/main.dart's own
 *     `p.join(appDir.path, 'qukis')`) already has at least one .md file in
 *     it and validates too - adopt that folder, the same fallback the
 *     Flutter app itself applies (adoptAppStorageIfUpgrading).
 *
 * A candidate that fails validation is treated exactly as if that route
 * hadn't matched at all - it falls through to the next route rather than
 * being adopted or silently replaced with a freshly-created empty folder.
 * Returns null when nothing valid is found, meaning the normal Android
 * onboarding/permission flow should run as it does today.
 */
export async function resolveMigratedStorageRoot(deps: AndroidFlutterMigrationDeps): Promise<string | null> {
  const info = await deps.getFlutterMigrationInfo();

  if (info.locationChosen && info.basePath && (await deps.isValidWritableDirectory(info.basePath))) {
    return info.basePath;
  }

  const appStorageDir = posixJoin(info.appDocumentsPath, "qukis");
  if ((await folderHasMarkdownFile(deps, appStorageDir)) && (await deps.isValidWritableDirectory(appStorageDir))) {
    return appStorageDir;
  }

  return null;
}
