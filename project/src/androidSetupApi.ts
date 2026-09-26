/**
 * Android's implementation of electronSetupApi.ts's ElectronSetupApi
 * contract - the same getState/chooseFilesystem/chooseAppStorage/quit shape
 * Electron's setup IPC bridge already satisfies, so screens/setupView.ts and
 * screens/settingsView.ts plug into this with no changes of their own (see
 * main.ts for the wiring that constructs this only on Android).
 *
 * Kept Capacitor-free like androidStorageAccess.ts/androidFlutterMigration.ts
 * - every real native call (permission gate, path resolution, app exit)
 * arrives through AndroidSetupApiDeps, so this stays unit-testable without a
 * device.
 *
 * The initial storage-location decision (androidSetupDecision.ts) runs once,
 * during construction - mirroring Electron's own app.whenReady(), which
 * resolves the storage root before the renderer ever calls
 * quki:setup:getState. getState() afterward just reports the outcome
 * already decided here, rather than re-running the precedence on every call.
 */

import type { ElectronSetupApi, StorageLocationState } from "./electronSetupApi.js";
import { decideAndroidStorageSetup, type AndroidSetupDecisionDeps } from "./androidSetupDecision.js";
import type { AndroidSettingsStore } from "./androidSettingsStore.js";

export interface AndroidSetupApiDeps {
  /** `context.filesDir.absolutePath`, resolved once before construction (CapacitorStorage.getPrivateStoragePath). */
  privateStoragePath: string;
  settingsStore: AndroidSettingsStore;
  /**
   * Runs the all-files-access permission gate (androidStorageAccess.ts via
   * main.ts's ensureAndroidStorageAccess) if needed, then resolves the
   * external Documents path. Only ever called from chooseFilesystem - i.e.
   * only when the user explicitly picks "Filesystem storage", never
   * unconditionally at launch.
   */
  requestFilesystemAccess(): Promise<string>;
  isValidWritableDirectory(path: string): Promise<boolean>;
  resolveMigratedStorageRoot(): Promise<string | null>;
  /**
   * Notifies main.ts that a path was resolved (first launch or Settings ->
   * Change location), so it can update the live CapacitorFsBackend's root
   * (CapacitorFsBackend.setRoot) and re-run mkdirp. A no-op before the
   * backend exists yet - main.ts's own createCapacitorBackend call already
   * mkdirp's the initial root once it's constructed.
   *
   * Awaited by chooseFilesystem/chooseAppStorage below: the caller (e.g.
   * main.ts's changeStorageLocation) reloads from the new root immediately
   * after either resolves, so the new directory must already exist by then
   * - firing this without awaiting it would let that reload race the mkdirp
   * it depends on.
   */
  onLocationResolved(path: string): Promise<void>;
  exitApp(): Promise<void>;
}

const APP_STORAGE_DIR_NAME = "QuKi_Notes";

/**
 * The app's private data directory (e.g. /data/data/com.quki.quki_notes) -
 * `privateStoragePath` (context.filesDir.absolutePath, per StoragePlugin.kt's
 * getPrivateStoragePath) is always that directory's own "files" child, the
 * same assumption androidFlutterMigration.ts's getFlutterMigrationInfo
 * already relies on (`context.filesDir.parentFile`) to locate the sibling
 * "app_flutter" directory.
 */
function privateDataRoot(privateStoragePath: string): string {
  const lastSlash = privateStoragePath.lastIndexOf("/");
  return lastSlash === -1 ? privateStoragePath : privateStoragePath.slice(0, lastSlash);
}

/**
 * Everything under the app's private data directory is deleted when the app
 * is uninstalled and inaccessible to other apps or the user's own file
 * manager (developer.android.com/training/data-storage/app-specific: "When
 * the user uninstalls your app, the files saved in app-specific storage are
 * removed" / "The system prevents other apps from accessing these
 * locations"). That covers both this app's own "Use app storage" choice
 * (<privateStoragePath>/QuKi_Notes) and a migrated Flutter app-storage
 * user's folder (a sibling "app_flutter/qukis" directory under the same
 * private root - see androidFlutterMigration.ts), so this checks path
 * *membership* in the private root rather than equality with one specific
 * known subfolder - the resolved path's actual guarantees don't depend on
 * which route produced it.
 */
function isUnderPrivateStorage(path: string, privateStoragePath: string): boolean {
  const root = privateDataRoot(privateStoragePath);
  return path === root || path.startsWith(`${root}/`);
}

export async function createAndroidSetupApi(deps: AndroidSetupApiDeps): Promise<ElectronSetupApi> {
  let currentPath: string | null = null;
  let unreachablePath: string | null = null;

  const decisionDeps: AndroidSetupDecisionDeps = {
    readSettings: () => deps.settingsStore.read(),
    writeSettings: (settings) => deps.settingsStore.write(settings),
    isValidWritableDirectory: deps.isValidWritableDirectory,
    resolveMigratedStorageRoot: deps.resolveMigratedStorageRoot,
  };

  const outcome = await decideAndroidStorageSetup(decisionDeps);
  if (outcome.kind === "use-path") {
    currentPath = outcome.path;
  } else if (outcome.kind === "recovery") {
    unreachablePath = outcome.unreachablePath;
  }

  const appStoragePath = `${deps.privateStoragePath}/${APP_STORAGE_DIR_NAME}`;

  return {
    async getState(): Promise<StorageLocationState> {
      return {
        chosen: currentPath !== null,
        path: currentPath,
        isAppStorage: currentPath !== null && isUnderPrivateStorage(currentPath, deps.privateStoragePath),
        unreachablePath,
      };
    },

    async chooseFilesystem(): Promise<string | null> {
      const path = await deps.requestFilesystemAccess();
      await deps.settingsStore.setStorageLocation(path);
      currentPath = path;
      unreachablePath = null;
      await deps.onLocationResolved(path);
      return path;
    },

    async chooseAppStorage(): Promise<string> {
      await deps.settingsStore.setStorageLocation(appStoragePath);
      currentPath = appStoragePath;
      unreachablePath = null;
      await deps.onLocationResolved(appStoragePath);
      return appStoragePath;
    },

    async quit(): Promise<void> {
      await deps.exitApp();
    },
  };
}
