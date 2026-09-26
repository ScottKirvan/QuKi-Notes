import * as fs from 'node:fs';
import * as path from 'node:path';

// isValidWritableDirectory used to be defined here; it moved to
// storageValidation.ts so main.ts's own startup-path validation can share it
// without importing Flutter-migration-specific code - see that file's doc
// comment.
import { isValidWritableDirectory } from './storageValidation.js';

/**
 * STORAGE_CONTRACT.md's migration section: "The existing folder opens
 * as-is. Onboarding points the new app at the same folder; nothing is
 * converted, renamed or rewritten... Existing users update in place."
 * BEHAVIOR_SPEC.md §1/§3 describe the Flutter app's own version of this: an
 * upgrade check that silently adopts app storage rather than showing setup
 * again when a location was never explicitly chosen but QuKis already exist.
 * These functions replicate that same spirit against the *new* app's
 * knowledge of where the Flutter app's own preferences and app-storage
 * folder actually live on disk.
 *
 * Every real path here was confirmed by reading the actual Flutter plugin
 * source in the local pub cache (shared_preferences_windows,
 * shared_preferences_linux, path_provider_windows, path_provider_linux,
 * xdg_directories) rather than assumed - see the task notes for the exact
 * file/line trace. windows/runner/Runner.rc sets CompanyName "com.quki" and
 * ProductName "quki_notes"; linux/CMakeLists.txt sets APPLICATION_ID
 * "com.quki.quki_notes".
 */

export interface FlutterMigrationChoice {
  basePath: string;
}

/**
 * Real per-platform path to the Flutter app's shared_preferences.json.
 * QUKI_ELECTRON_FLUTTER_PREFS_PATH is a test-only override - the same seam
 * pattern as QUKI_ELECTRON_USERDATA_DIR in main.ts - so a Playwright run can
 * point this at a throwaway temp file instead of a real developer machine's
 * real Flutter install. Set to an empty string to simulate no Flutter
 * install at all.
 */
export function resolveFlutterPreferencesPath(platform: NodeJS.Platform, env: NodeJS.ProcessEnv): string | null {
  const override = env.QUKI_ELECTRON_FLUTTER_PREFS_PATH;
  if (override !== undefined) {
    return override === '' ? null : override;
  }
  if (platform === 'win32') {
    // shared_preferences_windows.dart: getApplicationSupportPath() is
    // path_provider_windows's RoamingAppData (%APPDATA%) plus
    // "<CompanyName>\<ProductName>" read from the built exe's VERSIONINFO
    // resource; the preferences file is "<that dir>\shared_preferences.json".
    const appData = env.APPDATA;
    if (!appData) return null;
    return path.join(appData, 'com.quki', 'quki_notes', 'shared_preferences.json');
  }
  if (platform === 'linux') {
    // shared_preferences_linux.dart: getApplicationSupportPath() is
    // path_provider_linux's $XDG_DATA_HOME (default ~/.local/share) plus the
    // GApplication id ("com.quki.quki_notes", from linux/CMakeLists.txt);
    // the preferences file is "<that dir>/shared_preferences.json".
    const dataHome = env.XDG_DATA_HOME || (env.HOME ? path.join(env.HOME, '.local', 'share') : null);
    if (!dataHome) return null;
    return path.join(dataHome, 'com.quki.quki_notes', 'shared_preferences.json');
  }
  return null;
}

/**
 * Reads and parses the Flutter app's shared_preferences.json and extracts
 * an explicitly-chosen storage location, if any. shared_preferences'
 * classic wrapper prepends "flutter." to every key before it reaches
 * platform storage (confirmed by reading shared_preferences_legacy.dart), so
 * the on-disk keys are "flutter.storage.base_path" and
 * "flutter.storage.location_chosen" (see
 * lib/core/storage/storage_location_service.dart for the unprefixed names).
 * A missing file, unreadable file, corrupt JSON, or unset/false flag are all
 * treated the same as "nothing to adopt" - never thrown.
 */
export function readFlutterMigrationChoice(prefsPath: string): FlutterMigrationChoice | null {
  let raw: string;
  try {
    raw = fs.readFileSync(prefsPath, 'utf8');
  } catch {
    return null;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (parsed === null || typeof parsed !== 'object') return null;
  const record = parsed as Record<string, unknown>;
  const chosen = record['flutter.storage.location_chosen'];
  const basePath = record['flutter.storage.base_path'];
  if (chosen === true && typeof basePath === 'string' && basePath.length > 0) {
    return { basePath };
  }
  return null;
}

/**
 * STORAGE_CONTRACT.md rule 9: the folder is flat, so this checks direct
 * children only - never recurses.
 */
export function folderHasMarkdownFile(dir: string): boolean {
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return false;
  }
  return entries.some((entry) => entry.isFile() && entry.name.toLowerCase().endsWith('.md'));
}

/**
 * The one entry point main.ts calls. Two routes to a silent adoption, in
 * order, mirroring the Flutter app's own adoptAppStorageIfUpgrading()
 * (lib/core/storage/storage_location_service.dart):
 *
 *  1. The Flutter app explicitly recorded a chosen location - adopt it,
 *     whatever it is (app storage or a filesystem folder the user picked),
 *     provided it still validates (see isValidWritableDirectory).
 *  2. No recorded choice (no Flutter install found, the flag was never set,
 *     or the recorded path failed validation), but the Flutter app-storage
 *     default folder (appStorageDir - <Documents>/qukis, the same folder
 *     resolveAppStorageDir() in main.ts now resolves to) already has at
 *     least one .md file in it and validates too - adopt that folder, the
 *     same fallback the Flutter app itself applies.
 *
 * A candidate that fails validation is treated exactly as if that route
 * hadn't matched at all: it falls through to the next route rather than
 * being adopted or silently replaced with a freshly-created empty folder.
 * Returns null when nothing valid is found, meaning the real first-launch
 * setup screen should show.
 */
export function resolveMigratedStorageRoot(options: {
  platform: NodeJS.Platform;
  env: NodeJS.ProcessEnv;
  appStorageDir: string;
}): string | null {
  const prefsPath = resolveFlutterPreferencesPath(options.platform, options.env);
  if (prefsPath) {
    const choice = readFlutterMigrationChoice(prefsPath);
    if (choice && isValidWritableDirectory(choice.basePath)) return choice.basePath;
  }
  if (folderHasMarkdownFile(options.appStorageDir) && isValidWritableDirectory(options.appStorageDir)) {
    return options.appStorageDir;
  }
  return null;
}
