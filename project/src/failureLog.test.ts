import * as fsp from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";

import { NodeFsBackend } from "quki-core/node";
import { QuKiStore, createKeyValueFailureLog, type FailureEntry, type FailureLogStore } from "quki-core";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { getFailureLogView, initFailureLog, installGlobalFailureHandlers, whereOf } from "./failureLog.js";
import { AutoSaveController } from "./persistence.js";

const SENTINEL_TEXT = "SENTINEL-BODY-TEXT-9c1d";
const SENTINEL_FILE = "sentinel-private-name";

function memoryStore(): FailureLogStore & { entries: () => Promise<FailureEntry[]> } {
  const data = new Map<string, string>();
  const log = createKeyValueFailureLog(
    { getItem: (k) => data.get(k) ?? null, setItem: (k, v) => void data.set(k, v), removeItem: (k) => void data.delete(k) },
    "k",
  );
  return Object.assign(log, { entries: () => log.read() });
}

function start(): ReturnType<typeof memoryStore> {
  const store = memoryStore();
  initFailureLog({ version: "9.9.9", platform: "web", backend: "opfs", store });
  return store;
}

describe("whereOf", () => {
  it("keeps only the bundle's own file name", () => {
    expect(whereOf("https://x.test/assets/index-abc.js", 1, 2345)).toBe("index-abc.js:1:2345");
    expect(whereOf("C:\\Users\\me\\app\\a.js", 1, 2)).toBe("a.js:1:2");
    expect(whereOf(undefined, 1, 2)).toBeUndefined();
  });
});

describe("installGlobalFailureHandlers", () => {
  function fakeWindow() {
    const handlers = new Map<string, (e: unknown) => void>();
    return { handlers, addEventListener: (type: string, fn: (e: unknown) => void) => void handlers.set(type, fn) };
  }

  it("records an uncaught exception and an unhandled rejection", async () => {
    const store = start();
    const win = fakeWindow();
    installGlobalFailureHandlers(win as unknown as Window);
    win.handlers.get("error")!({ error: new TypeError("x is not a function"), message: "x", filename: "https://h/assets/a.js", lineno: 3, colno: 4 });
    win.handlers.get("unhandledrejection")!({ reason: Object.assign(new Error("denied"), { name: "NotAllowedError" }) });
    const entries = await store.entries();
    expect(entries.map((e) => [e.kind, e.name])).toEqual([
      ["uncaught", "TypeError"],
      ["unhandled-rejection", "NotAllowedError"],
    ]);
    expect(entries[0]!.where).toBe("a.js:3:4");
  });

  it("ignores the browser's harmless ResizeObserver notice", async () => {
    const store = start();
    const win = fakeWindow();
    installGlobalFailureHandlers(win as unknown as Window);
    win.handlers.get("error")!({ message: "ResizeObserver loop completed with undelivered notifications." });
    expect(await store.entries()).toEqual([]);
  });
});

describe("the log view", () => {
  it("reads as text and clears", async () => {
    const store = start();
    await store.append({ t: "2026-11-26T10:00:00.000Z", kind: "save", op: "save", version: "1", platform: "web", backend: "opfs", process: "renderer" });
    const view = getFailureLogView()!;
    expect(await view.readText()).toContain("[save] save");
    await view.clear();
    expect(await view.readText()).toBe("No failures recorded.");
  });
});

describe("saving records failures without QuKi text or filenames", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await fsp.mkdtemp(path.join(tmpdir(), "quki-failurelog-test-"));
  });
  afterEach(async () => {
    await fsp.rm(dir, { recursive: true, force: true });
  });

  it("records nothing for a normal save", async () => {
    const store = start();
    const quki = new QuKiStore(new NodeFsBackend(dir));
    const controller = new AutoSaveController(quki, () => `hello ${SENTINEL_TEXT}`, () => {}, { id: null, body: "", modifiedAt: null });
    expect((await controller.flush()).status).toBe("saved");
    expect(await store.entries()).toEqual([]);
  });

  it("records a failed save with the error's name and code, never the text or a filename", async () => {
    const store = start();
    const quki = new QuKiStore(new NodeFsBackend(dir));
    const created = await quki.save({ id: null, body: "first" });
    if (created.status !== "saved") throw new Error("unreachable");
    quki.save = async () => {
      throw Object.assign(new Error(`ENOSPC: no space left on device, open '${dir}/${created.id}.md' while writing ${SENTINEL_TEXT} to ${SENTINEL_FILE}.md`), {
        code: "ENOSPC",
      });
    };
    const controller = new AutoSaveController(quki, () => `body ${SENTINEL_TEXT}`, () => {}, { id: created.id, body: "first", modifiedAt: created.modifiedAt });
    expect((await controller.flush()).status).toBe("error");
    const entries = await store.entries();
    expect(entries).toHaveLength(1);
    expect(entries[0]).toMatchObject({ kind: "save", op: "save", code: "ENOSPC", version: "9.9.9", platform: "web", backend: "opfs" });
    const text = JSON.stringify(entries);
    for (const forbidden of [SENTINEL_TEXT, SENTINEL_FILE, created.id, dir]) expect(text).not.toContain(forbidden);
  });

  it("records the save-conflict path and the forced overwrite that follows", async () => {
    const store = start();
    const quki = new QuKiStore(new NodeFsBackend(dir));
    const created = await quki.save({ id: null, body: "original" });
    if (created.status !== "saved") throw new Error("unreachable");
    await new Promise((r) => setTimeout(r, 10));
    await quki.save({ id: created.id, body: "changed elsewhere", expectedModifiedAt: created.modifiedAt });
    const controller = new AutoSaveController(quki, () => `edit ${SENTINEL_TEXT}`, () => {}, { id: created.id, body: "original", modifiedAt: created.modifiedAt });
    expect((await controller.flush()).status).toBe("conflict");
    const entries = await store.entries();
    expect(entries.map((e) => [e.kind, e.conflict])).toEqual([["conflict", "modified"]]);
    expect(JSON.stringify(entries)).not.toContain(SENTINEL_TEXT);
  });

  it("records a failed overwrite as forced", async () => {
    const store = start();
    const quki = new QuKiStore(new NodeFsBackend(dir));
    const created = await quki.save({ id: null, body: "original" });
    if (created.status !== "saved") throw new Error("unreachable");
    quki.save = async () => {
      throw Object.assign(new Error("EACCES: permission denied"), { code: "EACCES" });
    };
    const controller = new AutoSaveController(quki, () => "edit", () => {}, { id: created.id, body: "original", modifiedAt: created.modifiedAt });
    await controller.overwrite();
    const [entry] = await store.entries();
    expect(entry).toMatchObject({ kind: "save", op: "overwrite", forced: true, code: "EACCES" });
  });
});
