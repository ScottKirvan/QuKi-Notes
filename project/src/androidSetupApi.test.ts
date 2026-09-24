import { describe, expect, it, vi } from "vitest";

import { createAndroidSetupApi, type AndroidSetupApiDeps } from "./androidSetupApi.js";
import { AndroidSettingsStore, type AndroidSettingsDeps } from "./androidSettingsStore.js";

const PRIVATE_STORAGE_PATH = "/data/data/com.quki.quki_notes/files";
const SETTINGS_PATH = `${PRIVATE_STORAGE_PATH}/quki_settings.json`;

function fakeSettingsStore(initialFiles: Record<string, string> = {}): { store: AndroidSettingsStore; files: Record<string, string> } {
  const files = initialFiles;
  const deps: AndroidSettingsDeps = {
    exists: vi.fn(async (path: string) => path in files),
    readText: vi.fn(async (path: string) => files[path]!),
    writeTextAtomic: vi.fn(async (path: string, content: string) => {
      files[path] = content;
    }),
  };
  return { store: new AndroidSettingsStore(deps, SETTINGS_PATH), files };
}

function baseDeps(overrides: Partial<AndroidSetupApiDeps> = {}): AndroidSetupApiDeps {
  const { store } = fakeSettingsStore();
  return {
    privateStoragePath: PRIVATE_STORAGE_PATH,
    settingsStore: store,
    requestFilesystemAccess: vi.fn(async () => "/storage/emulated/0/Documents/QuKi_Notes"),
    isValidWritableDirectory: vi.fn(async () => true),
    resolveMigratedStorageRoot: vi.fn(async (): Promise<string | null> => null),
    onLocationResolved: vi.fn(),
    exitApp: vi.fn(async () => undefined),
    ...overrides,
  } as AndroidSetupApiDeps;
}

describe("createAndroidSetupApi", () => {
  it("reports not-chosen with no unreachable path on a genuine fresh install", async () => {
    const deps = baseDeps();

    const api = await createAndroidSetupApi(deps);

    expect(await api.getState()).toEqual({ chosen: false, path: null, unreachablePath: null });
  });

  it("reports the already-chosen path from a valid settings file without touching migration or the permission gate", async () => {
    const { store, files } = fakeSettingsStore();
    await store.setStorageLocation("/storage/emulated/0/Documents/QuKi_Notes");
    const deps = baseDeps({ settingsStore: new AndroidSettingsStore({ exists: async (p) => p in files, readText: async (p) => files[p]!, writeTextAtomic: async () => undefined }, SETTINGS_PATH) });

    const api = await createAndroidSetupApi(deps);

    expect(await api.getState()).toEqual({ chosen: true, path: "/storage/emulated/0/Documents/QuKi_Notes", unreachablePath: null });
    expect(deps.requestFilesystemAccess).not.toHaveBeenCalled();
    expect(deps.resolveMigratedStorageRoot).not.toHaveBeenCalled();
  });

  it("reports the unreachable path as a recovery case when the settings-file path no longer validates", async () => {
    const { store, files } = fakeSettingsStore();
    await store.setStorageLocation("/moved-or-deleted-folder");
    const deps = baseDeps({
      settingsStore: new AndroidSettingsStore({ exists: async (p) => p in files, readText: async (p) => files[p]!, writeTextAtomic: async () => undefined }, SETTINGS_PATH),
      isValidWritableDirectory: vi.fn(async () => false),
    });

    const api = await createAndroidSetupApi(deps);

    expect(await api.getState()).toEqual({ chosen: false, path: null, unreachablePath: "/moved-or-deleted-folder" });
  });

  it("silently adopts a migrated path and persists it", async () => {
    const deps = baseDeps({ resolveMigratedStorageRoot: vi.fn(async () => "/data/data/com.quki.quki_notes/app_flutter/qukis") });

    const api = await createAndroidSetupApi(deps);

    expect(await api.getState()).toEqual({ chosen: true, path: "/data/data/com.quki.quki_notes/app_flutter/qukis", unreachablePath: null });
    expect(await deps.settingsStore.read()).toEqual({ storagePath: "/data/data/com.quki.quki_notes/app_flutter/qukis", storageChosen: true });
  });

  describe("chooseFilesystem", () => {
    it("requests filesystem access, persists the resulting path, updates state, and notifies the caller", async () => {
      const deps = baseDeps();
      const api = await createAndroidSetupApi(deps);

      const path = await api.chooseFilesystem();

      expect(path).toBe("/storage/emulated/0/Documents/QuKi_Notes");
      expect(deps.requestFilesystemAccess).toHaveBeenCalledTimes(1);
      expect(await api.getState()).toEqual({ chosen: true, path: "/storage/emulated/0/Documents/QuKi_Notes", unreachablePath: null });
      expect(await deps.settingsStore.read()).toEqual({ storagePath: "/storage/emulated/0/Documents/QuKi_Notes", storageChosen: true });
      expect(deps.onLocationResolved).toHaveBeenCalledWith("/storage/emulated/0/Documents/QuKi_Notes");
    });

    it("clears a previously-reported unreachable path once a new choice is made", async () => {
      const { store, files } = fakeSettingsStore();
      await store.setStorageLocation("/moved-or-deleted-folder");
      const deps = baseDeps({
        settingsStore: new AndroidSettingsStore({ exists: async (p) => p in files, readText: async (p) => files[p]!, writeTextAtomic: async (p, c) => { files[p] = c; } }, SETTINGS_PATH),
        isValidWritableDirectory: vi.fn(async () => false),
      });
      const api = await createAndroidSetupApi(deps);
      expect((await api.getState()).unreachablePath).toBe("/moved-or-deleted-folder");

      await api.chooseFilesystem();

      expect((await api.getState()).unreachablePath).toBeNull();
    });
  });

  describe("chooseAppStorage", () => {
    it("resolves to <privateStoragePath>/QuKi_Notes, persists it, updates state, and notifies the caller", async () => {
      const deps = baseDeps();
      const api = await createAndroidSetupApi(deps);

      const path = await api.chooseAppStorage();

      expect(path).toBe(`${PRIVATE_STORAGE_PATH}/QuKi_Notes`);
      expect(await api.getState()).toEqual({ chosen: true, path: `${PRIVATE_STORAGE_PATH}/QuKi_Notes`, unreachablePath: null });
      expect(await deps.settingsStore.read()).toEqual({ storagePath: `${PRIVATE_STORAGE_PATH}/QuKi_Notes`, storageChosen: true });
      expect(deps.onLocationResolved).toHaveBeenCalledWith(`${PRIVATE_STORAGE_PATH}/QuKi_Notes`);
    });
  });

  describe("quit", () => {
    it("calls exitApp", async () => {
      const deps = baseDeps();
      const api = await createAndroidSetupApi(deps);

      await api.quit();

      expect(deps.exitApp).toHaveBeenCalledTimes(1);
    });
  });
});
