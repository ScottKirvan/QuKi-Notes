import { describe, expect, it, vi } from "vitest";

import { ElectronIpcBackend, type ElectronStorageApi } from "./electronIpcBackend.js";

function fakeElectronApi(): ElectronStorageApi {
  return {
    readText: vi.fn().mockResolvedValue("body text"),
    writeTextAtomic: vi.fn().mockResolvedValue(undefined),
    readBinary: vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3])),
    writeBinaryAtomic: vi.fn().mockResolvedValue(undefined),
    remove: vi.fn().mockResolvedValue(undefined),
    rename: vi.fn().mockResolvedValue(undefined),
    exists: vi.fn().mockResolvedValue(true),
    stat: vi.fn().mockResolvedValue({ size: 1, mtimeMs: 2, birthtimeMs: 3 }),
    listDir: vi.fn().mockResolvedValue(["a.md"]),
    mkdirp: vi.fn().mockResolvedValue(undefined),
    resolvePath: vi.fn().mockReturnValue("/abs/media/foo.png"),
  };
}

describe("ElectronIpcBackend", () => {
  it("proxies every StorageBackend method to the corresponding injected api call, unchanged", async () => {
    const api = fakeElectronApi();
    const backend = new ElectronIpcBackend(api);

    await expect(backend.readText("a.md")).resolves.toBe("body text");
    expect(api.readText).toHaveBeenCalledWith("a.md");

    await backend.writeTextAtomic("a.md", "new body");
    expect(api.writeTextAtomic).toHaveBeenCalledWith("a.md", "new body");

    await expect(backend.readBinary("media/x.png")).resolves.toEqual(new Uint8Array([1, 2, 3]));
    expect(api.readBinary).toHaveBeenCalledWith("media/x.png");

    const bytes = new Uint8Array([9, 9]);
    await backend.writeBinaryAtomic("media/x.png", bytes);
    expect(api.writeBinaryAtomic).toHaveBeenCalledWith("media/x.png", bytes);

    await backend.remove("a.md");
    expect(api.remove).toHaveBeenCalledWith("a.md");

    await backend.rename("a.md", ".trash/a.md");
    expect(api.rename).toHaveBeenCalledWith("a.md", ".trash/a.md");

    await expect(backend.exists("a.md")).resolves.toBe(true);
    expect(api.exists).toHaveBeenCalledWith("a.md");

    await expect(backend.stat("a.md")).resolves.toEqual({ size: 1, mtimeMs: 2, birthtimeMs: 3 });
    expect(api.stat).toHaveBeenCalledWith("a.md");

    await expect(backend.listDir("")).resolves.toEqual(["a.md"]);
    expect(api.listDir).toHaveBeenCalledWith("");

    await backend.mkdirp("media");
    expect(api.mkdirp).toHaveBeenCalledWith("media");
  });

  it("calls resolvePath synchronously (no await needed), matching StorageBackend's contract", () => {
    const api = fakeElectronApi();
    const backend = new ElectronIpcBackend(api);

    const result = backend.resolvePath("media/foo.png");

    expect(result).toBe("/abs/media/foo.png");
    expect(api.resolvePath).toHaveBeenCalledWith("media/foo.png");
  });
});
