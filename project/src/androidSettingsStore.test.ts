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

const DEFAULTS = { storagePath: null, storageChosen: false, plainTextMode: false };

describe("AndroidSettingsStore", () => {
  describe("read", () => {
    it("returns not-chosen when the settings file does not exist", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual(DEFAULTS);
      expect(deps.readText).not.toHaveBeenCalled();
    });

    it("returns not-chosen when the file exists but is not valid JSON", async () => {
      const deps = fakeDeps({ [SETTINGS_PATH]: "{not json" });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual(DEFAULTS);
    });

    it("returns not-chosen when exists() says true but readText rejects (a read race)", async () => {
      const deps = fakeDeps();
      deps.exists = vi.fn(async () => true);
      deps.readText = vi.fn(async () => {
        throw new Error("unexpected native I/O failure");
      });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual(DEFAULTS);
    });

    it("returns the recorded path and chosen flag from a valid settings file", async () => {
      const deps = fakeDeps({
        [SETTINGS_PATH]: JSON.stringify({ storagePath: "/storage/emulated/0/Documents/QuKi_Notes", storageChosen: true }),
      });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual({ ...DEFAULTS, storagePath: "/storage/emulated/0/Documents/QuKi_Notes", storageChosen: true });
    });

    it("defaults missing/malformed fields rather than trusting the file's shape", async () => {
      const deps = fakeDeps({ [SETTINGS_PATH]: JSON.stringify({ storagePath: 42, storageChosen: "yes", plainTextMode: "yes" }) });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual(DEFAULTS);
    });

    // BEHAVIOR_SPEC.md §4: the mode toggle's plain-text/rendered choice
    // "persists across launches" - same file, same shape as storagePath above.
    it("returns a recorded plainTextMode from a valid settings file", async () => {
      const deps = fakeDeps({ [SETTINGS_PATH]: JSON.stringify({ plainTextMode: true }) });
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      expect(await store.read()).toEqual({ ...DEFAULTS, plainTextMode: true });
    });
  });

  describe("write / setStorageLocation", () => {
    it("writes the settings JSON via writeTextAtomic at the fixed settings path", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      await store.write({ storagePath: "/chosen/folder", storageChosen: true, plainTextMode: false });

      expect(deps.writeTextAtomic).toHaveBeenCalledWith(
        SETTINGS_PATH,
        JSON.stringify({ storagePath: "/chosen/folder", storageChosen: true, plainTextMode: false }, null, 2),
      );
    });

    it("setStorageLocation writes and returns the resulting settings", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      const result = await store.setStorageLocation("/chosen/folder");

      expect(result).toEqual({ ...DEFAULTS, storagePath: "/chosen/folder", storageChosen: true });
      const written = JSON.parse(deps.files[SETTINGS_PATH]!) as unknown;
      expect(written).toEqual({ ...DEFAULTS, storagePath: "/chosen/folder", storageChosen: true });
    });

    it("a write followed by a read round-trips", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      await store.setStorageLocation("/chosen/folder");

      expect(await store.read()).toEqual({ ...DEFAULTS, storagePath: "/chosen/folder", storageChosen: true });
    });

    it("setStorageLocation preserves a previously-set plainTextMode rather than wiping it", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);
      await store.setPlainTextMode(true);

      await store.setStorageLocation("/chosen/folder");

      expect(await store.read()).toEqual({ storagePath: "/chosen/folder", storageChosen: true, plainTextMode: true });
    });
  });

  describe("setPlainTextMode", () => {
    it("writes and returns the resulting settings", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);

      const result = await store.setPlainTextMode(true);

      expect(result).toEqual({ ...DEFAULTS, plainTextMode: true });
      expect(await store.read()).toEqual({ ...DEFAULTS, plainTextMode: true });
    });

    it("preserves a previously-chosen storage location rather than wiping it", async () => {
      const deps = fakeDeps();
      const store = new AndroidSettingsStore(deps, SETTINGS_PATH);
      await store.setStorageLocation("/chosen/folder");

      await store.setPlainTextMode(true);

      expect(await store.read()).toEqual({ storagePath: "/chosen/folder", storageChosen: true, plainTextMode: true });
    });
  });
});
