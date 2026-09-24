import { describe, expect, it, vi } from "vitest";

import { AndroidSettingsStore, type AndroidSettingsDeps } from "./androidSettingsStore.js";

const SETTINGS_PATH = "/data/data/com.quki.quki_notes/files/quki_settings.json";

function fakeDeps(files: Record<string, string> = {}): AndroidSettingsDeps & { files: Record<string, string> } {
  return {
    files,
    exists: vi.fn(async (path: string) => path in files),
    readText: vi.fn(async (path: string) => {
      if (!(path in files)) throw new Error(`ENOENT: ${path}`);
      return files[path]!;
    }),
    writeTextAtomic: vi.fn(async (path: string, content: string) => {
      files[path] = content;
    }),
  };
}

describe("AndroidSettingsStore", () => {
  describe("read", () => {
    it("returns not-chosen when the settings file does not exist", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual({ storagePath: null, storageChosen: false });
      expect(deps.readText).not.toHaveBeenCalled();
    });

    it("returns not-chosen when the file exists but is not valid JSON", async () => {
      const deps = fakeDeps({ [SETTINGS_PATH]: "{not json" });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual({ storagePath: null, storageChosen: false });
    });

    it("returns not-chosen when exists() says true but readText rejects (a read race)", async () => {
      const deps = fakeDeps();
      deps.exists = vi.fn(async () => true);
      deps.readText = vi.fn(async () => {
        throw new Error("unexpected native I/O failure");
      });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual({ storagePath: null, storageChosen: false });
    });

    it("returns the recorded path and chosen flag from a valid settings file", async () => {
      const deps = fakeDeps({
        [SETTINGS_PATH]: JSON.stringify({ storagePath: "/storage/emulated/0/Documents/QuKi_Notes", storageChosen: true }),
      });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual({ storagePath: "/storage/emulated/0/Documents/QuKi_Notes", storageChosen: true });
    });

    it("defaults missing/malformed fields rather than trusting the file's shape", async () => {
      const deps = fakeDeps({ [SETTINGS_PATH]: JSON.stringify({ storagePath: 42, storageChosen: "yes" }) });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual({ storagePath: null, storageChosen: false });
    });
  });

  describe("write / setStorageLocation", () => {
    it("writes the settings JSON via writeTextAtomic at the fixed settings path", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      await store.write({ storagePath: "/chosen/folder", storageChosen: true });

      expect(deps.writeTextAtomic).toHaveBeenCalledWith(SETTINGS_PATH, JSON.stringify({ storagePath: "/chosen/folder", storageChosen: true }, null, 2));
    });

    it("setStorageLocation writes and returns the resulting settings", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      const result = await store.setStorageLocation("/chosen/folder");

      expect(result).toEqual({ storagePath: "/chosen/folder", storageChosen: true });
      const written = JSON.parse(deps.files[SETTINGS_PATH]!) as unknown;
      expect(written).toEqual({ storagePath: "/chosen/folder", storageChosen: true });
    });

    it("a write followed by a read round-trips", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      await store.setStorageLocation("/chosen/folder");

      expect(await store.read()).toEqual({ storagePath: "/chosen/folder", storageChosen: true });
    });
  });
});
