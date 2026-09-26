import { describe, expect, it, vi } from "vitest";

import { CapacitorFsBackend, type CapacitorStoragePlugin } from "./capacitorBackend.js";

const ROOT = "/storage/emulated/0/Documents/QuKi_Notes";

function fakePlugin(): CapacitorStoragePlugin {
  return {
    readText: vi.fn().mockResolvedValue({ content: "body text" }),
    writeTextAtomic: vi.fn().mockResolvedValue(undefined),
    readBinary: vi.fn().mockResolvedValue({ data: btoa("\x01\x02\x03") }),
    writeBinaryAtomic: vi.fn().mockResolvedValue(undefined),
    remove: vi.fn().mockResolvedValue(undefined),
    rename: vi.fn().mockResolvedValue(undefined),
    exists: vi.fn().mockResolvedValue({ exists: true }),
    stat: vi.fn().mockResolvedValue({ size: 1, mtimeMs: 2, birthtimeMs: 0 }),
    listDir: vi.fn().mockResolvedValue({ entries: ["a.md"] }),
    mkdirp: vi.fn().mockResolvedValue(undefined),
    isExternalStorageManager: vi.fn().mockResolvedValue({ granted: true }),
    getExternalDocumentsPath: vi.fn().mockResolvedValue({ path: ROOT }),
    requestAllFilesAccess: vi.fn().mockResolvedValue(undefined),
    getFlutterMigrationInfo: vi.fn().mockResolvedValue({ locationChosen: false, basePath: null, appDocumentsPath: "/data/data/com.quki.quki_notes/app_flutter" }),
    isValidWritableDirectory: vi.fn().mockResolvedValue({ valid: true }),
    getPrivateStoragePath: vi.fn().mockResolvedValue({ path: "/data/data/com.quki.quki_notes/files" }),
  };
}

describe("CapacitorFsBackend", () => {
  it("proxies every StorageBackend method to the corresponding injected plugin call, with paths resolved under the root", async () => {
    const plugin = fakePlugin();
    const backend = new CapacitorFsBackend(plugin, ROOT);

    await expect(backend.readText("a.md")).resolves.toBe("body text");
    expect(plugin.readText).toHaveBeenCalledWith({ path: `${ROOT}/a.md` });

    await backend.writeTextAtomic("a.md", "new body");
    expect(plugin.writeTextAtomic).toHaveBeenCalledWith({ path: `${ROOT}/a.md`, content: "new body" });

    await expect(backend.readBinary("media/x.png")).resolves.toEqual(new Uint8Array([1, 2, 3]));
    expect(plugin.readBinary).toHaveBeenCalledWith({ path: `${ROOT}/media/x.png` });

    await backend.writeBinaryAtomic("media/x.png", new Uint8Array([9, 9]));
    expect(plugin.writeBinaryAtomic).toHaveBeenCalledWith({ path: `${ROOT}/media/x.png`, data: btoa("\x09\x09") });

    await backend.remove("a.md");
    expect(plugin.remove).toHaveBeenCalledWith({ path: `${ROOT}/a.md` });

    await backend.rename("a.md", ".trash/a.md");
    expect(plugin.rename).toHaveBeenCalledWith({ from: `${ROOT}/a.md`, to: `${ROOT}/.trash/a.md` });

    await expect(backend.exists("a.md")).resolves.toBe(true);
    expect(plugin.exists).toHaveBeenCalledWith({ path: `${ROOT}/a.md` });

    await expect(backend.stat("a.md")).resolves.toEqual({ size: 1, mtimeMs: 2, birthtimeMs: 0 });
    expect(plugin.stat).toHaveBeenCalledWith({ path: `${ROOT}/a.md` });

    await expect(backend.listDir("")).resolves.toEqual(["a.md"]);
    expect(plugin.listDir).toHaveBeenCalledWith({ path: ROOT });

    await backend.mkdirp("media");
    expect(plugin.mkdirp).toHaveBeenCalledWith({ path: `${ROOT}/media` });
  });

  it("calls resolvePath synchronously (no await needed), matching StorageBackend's contract", () => {
    const backend = new CapacitorFsBackend(fakePlugin(), ROOT);

    expect(backend.resolvePath("media/foo.png")).toBe(`${ROOT}/media/foo.png`);
    expect(backend.resolvePath("")).toBe(ROOT);
  });

  it("normalizes . and internal .. segments that stay inside the root", () => {
    const backend = new CapacitorFsBackend(fakePlugin(), ROOT);

    expect(backend.resolvePath("./a.md")).toBe(`${ROOT}/a.md`);
    expect(backend.resolvePath("media/../a.md")).toBe(`${ROOT}/a.md`);
  });

  it("throws rather than resolving a path that escapes the QuKi folder", () => {
    const backend = new CapacitorFsBackend(fakePlugin(), ROOT);

    expect(() => backend.resolvePath("..")).toThrow(/escapes QuKi folder/);
    expect(() => backend.resolvePath("../elsewhere.md")).toThrow(/escapes QuKi folder/);
    expect(() => backend.resolvePath("../../etc/passwd")).toThrow(/escapes QuKi folder/);
  });

  describe("setRoot", () => {
    it("changes which root later calls resolve against", async () => {
      const plugin = fakePlugin();
      const backend = new CapacitorFsBackend(plugin, ROOT);
      const NEW_ROOT = "/data/data/com.quki.quki_notes/files/QuKi_Notes";

      backend.setRoot(NEW_ROOT);

      expect(backend.resolvePath("a.md")).toBe(`${NEW_ROOT}/a.md`);
      await backend.readText("a.md");
      expect(plugin.readText).toHaveBeenCalledWith({ path: `${NEW_ROOT}/a.md` });
    });

    it("normalizes a trailing slash on the new root, same as the constructor does", () => {
      const backend = new CapacitorFsBackend(fakePlugin(), ROOT);

      backend.setRoot("/some/other/root/");

      expect(backend.resolvePath("a.md")).toBe("/some/other/root/a.md");
      expect(backend.resolvePath("")).toBe("/some/other/root");
    });

    it("enforces containment against the new root, not the old one", () => {
      const backend = new CapacitorFsBackend(fakePlugin(), ROOT);
      backend.setRoot("/new/root");

      expect(() => backend.resolvePath("../elsewhere.md")).toThrow(/escapes QuKi folder/);
      // A path that would have escaped the *old* root no longer needs to be
      // considered - only the new root's containment matters going forward.
      expect(backend.resolvePath("a.md")).toBe("/new/root/a.md");
    });
  });
});
