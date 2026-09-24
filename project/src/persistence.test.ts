import * as fsp from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";

import { NodeFsBackend } from "quki-core/node";
import { QuKiStore, type SaveParams, type SaveResult } from "quki-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { AutoSaveController, blankInitialQuKi } from "./persistence.js";

async function makeTempDir(): Promise<string> {
  return fsp.mkdtemp(path.join(tmpdir(), "quki-persistence-test-"));
}

describe("blankInitialQuKi", () => {
  it("is always blank, regardless of what QuKis already exist on disk", async () => {
    const dir = await makeTempDir();
    try {
      const store = new QuKiStore(new NodeFsBackend(dir));
      const first = await store.save({ id: null, body: "older" });
      if (first.status !== "saved") throw new Error("unreachable");
      await new Promise((resolve) => setTimeout(resolve, 10));
      const second = await store.save({ id: null, body: "newer" });
      if (second.status !== "saved") throw new Error("unreachable");

      // BEHAVIOR_SPEC.md §4: "A blank canvas on launch" - existing QuKis on
      // disk (however recently modified) are never reopened automatically.
      expect(blankInitialQuKi()).toEqual({ id: null, body: "", modifiedAt: null });
    } finally {
      await fsp.rm(dir, { recursive: true, force: true });
    }
  });

  it("starts blank when no QuKis exist", () => {
    expect(blankInitialQuKi()).toEqual({ id: null, body: "", modifiedAt: null });
  });
});

/**
 * A hand-rolled store double, used only for the pure timing tests below.
 * Combining vi.useFakeTimers() with NodeFsBackend's real filesystem I/O is
 * unreliable - fake timers fast-forward setTimeout/setInterval, but real
 * fs.promises calls complete via the actual libuv event loop, so advancing
 * fake time does not reliably wait for them. Timing behavior (debounce
 * length, interval period) is verified here against a synchronous fake;
 * everything that depends on real save outcomes (conflicts, empty-skip,
 * unchanged-skip) is verified further down against a real NodeFsBackend,
 * using flush() so no timer/IO race is involved.
 */
function makeFakeStore() {
  const calls: SaveParams[] = [];
  let nextModifiedAt = 1;
  const save = vi.fn(async (params: SaveParams): Promise<SaveResult> => {
    calls.push(params);
    if (params.body === "") return { status: "skipped-empty", id: params.id };
    const id = params.id ?? "fake-id";
    return {
      status: "saved",
      id,
      filename: `${id}.md`,
      createdAt: "2026-01-01T00:00:00.000Z",
      modifiedAt: `2026-01-01T00:00:00.${String(nextModifiedAt++).padStart(3, "0")}Z`,
    };
  });
  return { save, calls } as unknown as QuKiStore & { save: typeof save; calls: SaveParams[] };
}

/**
 * A store double whose save() hangs until the test resolves it explicitly,
 * used only to pin down overwrite()'s "wait for the in-flight save, then
 * write" ordering precisely (which normal call happened first, and with
 * what params). Everything else about overwrite() - real conflicts, real
 * on-disk content - is verified further down against a real NodeFsBackend.
 */
function makeControllableStore() {
  const calls: SaveParams[] = [];
  const resolvers: Array<(result: SaveResult) => void> = [];
  const save = vi.fn((params: SaveParams): Promise<SaveResult> => {
    calls.push(params);
    return new Promise<SaveResult>((resolve) => {
      resolvers.push(resolve);
    });
  });
  return { save, calls, resolvers } as unknown as QuKiStore & {
    save: typeof save;
    calls: SaveParams[];
    resolvers: typeof resolvers;
  };
}

/** Drains the microtask queue, regardless of how many hops a chain needs. */
function flushMicrotasks(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("AutoSaveController timing", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("debounces 2s after the last change by default, not before", async () => {
    const store = makeFakeStore();
    let body = "";
    const controller = new AutoSaveController(store, () => body, () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });

    body = "hello";
    controller.notifyChange();

    await vi.advanceTimersByTimeAsync(1999);
    expect(store.save).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(2);
    expect(store.save).toHaveBeenCalledTimes(1);
    expect(store.save).toHaveBeenCalledWith({ id: null, body: "hello", expectedModifiedAt: undefined });

    controller.dispose();
  });

  it("resets the debounce timer on every change - only the final edit is saved", async () => {
    const store = makeFakeStore();
    let body = "";
    const controller = new AutoSaveController(store, () => body, () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });

    body = "h";
    controller.notifyChange();
    await vi.advanceTimersByTimeAsync(1000);
    body = "he";
    controller.notifyChange();
    await vi.advanceTimersByTimeAsync(1000);
    body = "hel";
    controller.notifyChange();

    await vi.advanceTimersByTimeAsync(1000);
    expect(store.save).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1000);
    expect(store.save).toHaveBeenCalledTimes(1);
    expect(store.save).toHaveBeenCalledWith({ id: null, body: "hel", expectedModifiedAt: undefined });

    controller.dispose();
  });

  it("saves unconditionally every 30s once started, independent of the debounce", async () => {
    const store = makeFakeStore();
    const body = "periodic";
    const controller = new AutoSaveController(store, () => body, () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });
    controller.start();

    await vi.advanceTimersByTimeAsync(30_000);
    expect(store.save).toHaveBeenCalledTimes(1);

    controller.dispose();
  });

  it("passes the last-known id and modifiedAt as expectedModifiedAt on subsequent saves", async () => {
    const store = makeFakeStore();
    let body = "v1";
    const controller = new AutoSaveController(store, () => body, () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });

    controller.notifyChange();
    await vi.advanceTimersByTimeAsync(2000);
    expect(store.save).toHaveBeenNthCalledWith(1, { id: null, body: "v1", expectedModifiedAt: undefined });

    body = "v2";
    controller.notifyChange();
    await vi.advanceTimersByTimeAsync(2000);
    expect(store.save).toHaveBeenNthCalledWith(2, {
      id: "fake-id",
      body: "v2",
      expectedModifiedAt: "2026-01-01T00:00:00.001Z",
    });

    controller.dispose();
  });

  it("resetBaseline cancels a pending debounce so a stale queued save never fires", async () => {
    const store = makeFakeStore();
    let body = "old content";
    const controller = new AutoSaveController(store, () => body, () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });

    controller.notifyChange();
    await vi.advanceTimersByTimeAsync(500);

    controller.resetBaseline({ id: null, body: "", modifiedAt: null });
    body = ""; // simulating the editor having been cleared alongside the reset

    await vi.advanceTimersByTimeAsync(5000);
    expect(store.save).not.toHaveBeenCalled();

    controller.dispose();
  });

  it("resetBaseline re-points the controller at the new id/modifiedAt for the next save", async () => {
    const store = makeFakeStore();
    let body = "";
    const controller = new AutoSaveController(store, () => body, () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });

    controller.resetBaseline({ id: "switched-to-id", body: "loaded body", modifiedAt: "2026-01-01T00:00:00.000Z" });
    expect(controller.currentId).toBe("switched-to-id");

    body = "loaded body edited";
    controller.notifyChange();
    await vi.advanceTimersByTimeAsync(2000);

    expect(store.save).toHaveBeenCalledWith({
      id: "switched-to-id",
      body: "loaded body edited",
      expectedModifiedAt: "2026-01-01T00:00:00.000Z",
    });

    controller.dispose();
  });
});

describe("AutoSaveController behavior against a real backend", () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await fsp.rm(dir, { recursive: true, force: true });
  });

  it("creates the file on the first flush, not when the controller is constructed", async () => {
    expect(await store.list()).toHaveLength(0);

    let body = "hello";
    const controller = new AutoSaveController(store, () => body, () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });
    expect(await store.list()).toHaveLength(0);

    await controller.flush();
    const list = await store.list();
    expect(list).toHaveLength(1);
    expect(controller.currentId).toBe(list[0]!.id);
  });

  it("skips the save when the body is unchanged since the last write", async () => {
    const saveSpy = vi.spyOn(store, "save");
    const body = "";
    const controller = new AutoSaveController(store, () => body, () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });

    await controller.flush();
    expect(saveSpy).not.toHaveBeenCalled();
    expect(await store.list()).toHaveLength(0);
  });

  it("an empty-body skip from the core is not treated as an error and no conflict fires", async () => {
    const body = "";
    const conflicts: unknown[] = [];
    const controller = new AutoSaveController(store, () => body, (info) => conflicts.push(info), {
      id: null,
      body: "not-empty-initial-baseline-so-flush-actually-calls-save",
      modifiedAt: null,
    });

    await controller.flush();
    expect(conflicts).toEqual([]);
    expect(await store.list()).toHaveLength(0);
  });

  it("surfaces a conflict instead of silently dropping the write when the file changed underneath it", async () => {
    const created = await store.save({ id: null, body: "original" });
    if (created.status !== "saved") throw new Error("unreachable");

    await new Promise((resolve) => setTimeout(resolve, 10));
    const elsewhere = await store.save({
      id: created.id,
      body: "changed elsewhere",
      expectedModifiedAt: created.modifiedAt,
    });
    expect(elsewhere.status).toBe("saved");

    const body = "local edit that should not clobber the other writer";
    const conflicts: Array<{ reason: string; currentBody: string | null }> = [];
    const controller = new AutoSaveController(store, () => body, (info) => conflicts.push(info), {
      id: created.id,
      body: 'original',
      modifiedAt: created.modifiedAt,
    });

    await controller.flush();

    expect(conflicts).toHaveLength(1);
    expect(conflicts[0]!.reason).toBe("modified");
    expect(conflicts[0]!.currentBody).toBe("changed elsewhere");

    const onDisk = await store.read(created.id);
    expect(onDisk.body).toBe("changed elsewhere");
  });

  it("invokes onSaved with the id and modifiedAt after a real save, and not on a skipped-empty save", async () => {
    let body = "hello";
    const saved: Array<{ id: string; modifiedAt: string }> = [];
    const controller = new AutoSaveController(
      store,
      () => body,
      () => {},
      { id: null, body: "", modifiedAt: null },
      { onSaved: (info) => saved.push(info) },
    );

    await controller.flush();
    expect(saved).toHaveLength(1);
    expect(saved[0]!.id).toBe(controller.currentId);
    expect(saved[0]!.modifiedAt).toBeTruthy();

    body = ""; // now delete all content - save() skips empty bodies
    await controller.flush();
    expect(saved).toHaveLength(1); // unchanged - no onSaved for skipped-empty
  });

  it("does not invoke onSaved when the save conflicts", async () => {
    const created = await store.save({ id: null, body: "original" });
    if (created.status !== "saved") throw new Error("unreachable");
    await new Promise((resolve) => setTimeout(resolve, 10));
    await store.save({ id: created.id, body: "changed elsewhere", expectedModifiedAt: created.modifiedAt });

    const saved: unknown[] = [];
    const controller = new AutoSaveController(
      store,
      () => "local edit",
      () => {},
      { id: created.id, body: "original", modifiedAt: created.modifiedAt },
      { onSaved: (info) => saved.push(info) },
    );

    await controller.flush();
    expect(saved).toEqual([]);
  });

  it("surfaces a 'deleted' conflict when the QuKi was removed out from under it", async () => {
    const created = await store.save({ id: null, body: "original" });
    if (created.status !== "saved") throw new Error("unreachable");

    await store.moveToTrash(created.id);

    const body = "edit after delete";
    const conflicts: Array<{ reason: string; currentBody: string | null }> = [];
    const controller = new AutoSaveController(store, () => body, (info) => conflicts.push(info), {
      id: created.id,
      body: 'original',
      modifiedAt: created.modifiedAt,
    });

    await controller.flush();

    expect(conflicts).toHaveLength(1);
    expect(conflicts[0]!.reason).toBe("deleted");
  });

  it("does not update the saved baseline on conflict, so the same edit is retried next time", async () => {
    const created = await store.save({ id: null, body: "original" });
    if (created.status !== "saved") throw new Error("unreachable");
    await new Promise((resolve) => setTimeout(resolve, 10));
    await store.save({ id: created.id, body: "changed elsewhere", expectedModifiedAt: created.modifiedAt });

    const body = "still trying to save this";
    let conflictCount = 0;
    const controller = new AutoSaveController(store, () => body, () => conflictCount++, {
      id: created.id,
      body: 'original',
      modifiedAt: created.modifiedAt,
    });

    await controller.flush();
    expect(conflictCount).toBe(1);

    // Same body, same stale baseline: retried and conflicts again rather
    // than silently being treated as "already saved".
    await controller.flush();
    expect(conflictCount).toBe(2);
  });
});

describe("AutoSaveController surfaces a thrown save error distinctly from a conflict", () => {
  it("invokes onSaveError, not onConflict, when store.save() throws", async () => {
    const store = makeFakeStore();
    const thrown = new Error("simulated store.save() failure");
    store.save.mockRejectedValueOnce(thrown);
    const consoleSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    const body = "hello";
    const conflicts: unknown[] = [];
    const errors: unknown[] = [];
    const controller = new AutoSaveController(
      store,
      () => body,
      (info) => conflicts.push(info),
      { id: null, body: "", modifiedAt: null },
      { onSaveError: (error) => errors.push(error) },
    );

    await controller.flush();

    expect(errors).toEqual([thrown]);
    expect(conflicts).toEqual([]);
    expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining("auto-save"), thrown);

    consoleSpy.mockRestore();
  });

  it("does not update the saved baseline on a thrown error, so the same edit is retried next time", async () => {
    const store = makeFakeStore();
    store.save.mockRejectedValueOnce(new Error("first attempt fails"));
    vi.spyOn(console, "error").mockImplementation(() => {});

    const body = "retry me";
    let errorCount = 0;
    const controller = new AutoSaveController(
      store,
      () => body,
      () => {},
      { id: null, body: "", modifiedAt: null },
      { onSaveError: () => errorCount++ },
    );

    await controller.flush();
    expect(errorCount).toBe(1);
    expect(store.save).toHaveBeenCalledTimes(1);

    // Same unchanged body: retried on the next flush rather than treated
    // as already saved, because lastSavedBody was never updated.
    await controller.flush();
    expect(store.save).toHaveBeenCalledTimes(2);

    vi.restoreAllMocks();
  });

  it("does not crash when store.save() throws and no onSaveError is configured", async () => {
    const store = makeFakeStore();
    store.save.mockRejectedValueOnce(new Error("unhandled by design in this test"));
    vi.spyOn(console, "error").mockImplementation(() => {});

    const controller = new AutoSaveController(store, () => "no handler configured", () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });

    await expect(controller.flush()).resolves.toBeUndefined();

    vi.restoreAllMocks();
  });
});

describe("AutoSaveController against a real backend: reproduces the original crypto.randomUUID() failure", () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await fsp.rm(dir, { recursive: true, force: true });
  });

  it("surfaces the exact root-cause failure (crypto.randomUUID unavailable) via onSaveError instead of an unhandled rejection", async () => {
    const randomUUIDSpy = vi.spyOn(globalThis.crypto, "randomUUID").mockImplementation(() => {
      throw new TypeError("crypto.randomUUID is not a function");
    });
    const consoleSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    const body = "first save on a fresh QuKi";
    const errors: unknown[] = [];
    const conflicts: unknown[] = [];
    const controller = new AutoSaveController(
      store,
      () => body,
      (info) => conflicts.push(info),
      { id: null, body: "", modifiedAt: null },
      { onSaveError: (error) => errors.push(error) },
    );

    await controller.flush();

    expect(errors).toHaveLength(1);
    expect((errors[0] as Error).message).toContain("crypto.randomUUID");
    expect(conflicts).toEqual([]);
    expect(await store.list()).toHaveLength(0);
    expect(consoleSpy).toHaveBeenCalled();

    randomUUIDSpy.mockRestore();
    consoleSpy.mockRestore();
  });
});

describe("AutoSaveController.overwrite", () => {
  it("is a no-op when id is null - a conflict can only ever happen for an existing id", async () => {
    const store = makeFakeStore();
    const controller = new AutoSaveController(store, () => "irrelevant", () => {}, {
      id: null,
      body: "",
      modifiedAt: null,
    });

    await expect(controller.overwrite()).resolves.toBeUndefined();
    expect(store.save).not.toHaveBeenCalled();
  });

  it("routes a thrown store.save() error through onSaveError, exactly like a normal save's catch block", async () => {
    const store = makeFakeStore();
    const thrown = new Error("simulated overwrite failure");
    store.save.mockRejectedValueOnce(thrown);
    const consoleSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    const errors: unknown[] = [];
    const saved: unknown[] = [];
    const controller = new AutoSaveController(
      store,
      () => "content",
      () => {},
      { id: "existing-id", body: "original", modifiedAt: "2026-01-01T00:00:00.000Z" },
      { onSaveError: (error) => errors.push(error), onSaved: (info) => saved.push(info) },
    );

    await controller.overwrite();

    expect(errors).toEqual([thrown]);
    expect(saved).toEqual([]);
    expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining("overwrite"), thrown);

    consoleSpy.mockRestore();
  });

  it("waits for an in-flight save to settle, then writes with force:true and the latest expectedModifiedAt baseline", async () => {
    const store = makeControllableStore();
    let body = "v1";
    const saved: Array<{ id: string; modifiedAt: string }> = [];
    const conflicts: unknown[] = [];
    const controller = new AutoSaveController(
      store,
      () => body,
      (info) => conflicts.push(info),
      { id: "existing-id", body: "v0", modifiedAt: "2026-01-01T00:00:00.000Z" },
      { onSaved: (info) => saved.push(info) },
    );

    // Simulates a normal debounce/interval save already running when the
    // user clicks Overwrite.
    const firstSavePromise = controller.flush();
    expect(store.calls).toHaveLength(1);

    body = "v2 - edited after the conflict banner appeared, before Overwrite was clicked";
    const overwritePromise = controller.overwrite();
    await flushMicrotasks();
    expect(store.calls).toHaveLength(1); // overwrite must not have written yet - still waiting

    store.resolvers[0]!({
      status: "conflict",
      id: "existing-id",
      reason: "modified",
      currentModifiedAt: "2026-01-01T00:00:00.001Z",
      currentBody: "elsewhere",
    });
    await firstSavePromise;
    await flushMicrotasks();

    expect(store.calls).toHaveLength(2);
    expect(store.calls[1]).toEqual({
      id: "existing-id",
      body: "v2 - edited after the conflict banner appeared, before Overwrite was clicked",
      expectedModifiedAt: "2026-01-01T00:00:00.000Z",
      force: true,
    });

    store.resolvers[1]!({
      status: "saved",
      id: "existing-id",
      filename: "existing-id.md",
      createdAt: "2026-01-01T00:00:00.000Z",
      modifiedAt: "2026-01-01T00:00:00.002Z",
    });
    await overwritePromise;

    expect(conflicts).toHaveLength(1); // only the earlier, normal save's conflict
    expect(saved).toEqual([{ id: "existing-id", modifiedAt: "2026-01-01T00:00:00.002Z" }]);
  });

  describe("against a real backend", () => {
    let dir: string;
    let store: QuKiStore;

    beforeEach(async () => {
      dir = await makeTempDir();
      store = new QuKiStore(new NodeFsBackend(dir));
    });

    afterEach(async () => {
      await fsp.rm(dir, { recursive: true, force: true });
    });

    it("saves whatever is live in the editor at call time, not the body from when the conflict first fired", async () => {
      const created = await store.save({ id: null, body: "original" });
      if (created.status !== "saved") throw new Error("unreachable");
      await new Promise((resolve) => setTimeout(resolve, 10));
      await store.save({ id: created.id, body: "changed elsewhere", expectedModifiedAt: created.modifiedAt });

      let body = "edit live at the moment the conflict fired";
      const conflicts: unknown[] = [];
      const saved: Array<{ id: string; modifiedAt: string }> = [];
      const controller = new AutoSaveController(
        store,
        () => body,
        (info) => conflicts.push(info),
        { id: created.id, body: "original", modifiedAt: created.modifiedAt },
        { onSaved: (info) => saved.push(info) },
      );

      await controller.flush();
      expect(conflicts).toHaveLength(1);

      // More typing happens after the conflict banner appears, before the
      // user clicks Overwrite - this newer text is what must be saved.
      body = "even newer text typed after the conflict banner appeared";
      await controller.overwrite();

      expect(saved).toHaveLength(1);
      const onDisk = await store.read(created.id);
      expect(onDisk.body).toBe("even newer text typed after the conflict banner appeared");
    });

    it("recreates a QuKi that was deleted out from under it", async () => {
      const created = await store.save({ id: null, body: "original" });
      if (created.status !== "saved") throw new Error("unreachable");
      await store.moveToTrash(created.id);

      let body = "restored via overwrite after an external delete";
      const conflicts: Array<{ reason: string }> = [];
      const saved: Array<{ id: string; modifiedAt: string }> = [];
      const controller = new AutoSaveController(
        store,
        () => body,
        (info) => conflicts.push(info),
        { id: created.id, body: "original", modifiedAt: created.modifiedAt },
        { onSaved: (info) => saved.push(info) },
      );

      await controller.flush();
      expect(conflicts).toHaveLength(1);
      expect(conflicts[0]!.reason).toBe("deleted");

      await controller.overwrite();
      expect(saved).toHaveLength(1);

      const onDisk = await store.read(created.id);
      expect(onDisk.body).toBe("restored via overwrite after an external delete");
    });

    it("re-establishes the baseline so a further normal edit afterwards saves cleanly, not stuck retrying", async () => {
      const created = await store.save({ id: null, body: "original" });
      if (created.status !== "saved") throw new Error("unreachable");
      await new Promise((resolve) => setTimeout(resolve, 10));
      await store.save({ id: created.id, body: "changed elsewhere", expectedModifiedAt: created.modifiedAt });

      let body = "overwritten content";
      const conflicts: unknown[] = [];
      const controller = new AutoSaveController(store, () => body, (info) => conflicts.push(info), {
        id: created.id,
        body: "original",
        modifiedAt: created.modifiedAt,
      });

      await controller.flush();
      expect(conflicts).toHaveLength(1);

      await controller.overwrite();

      body = "one more normal edit after the overwrite";
      await controller.flush();

      expect(conflicts).toHaveLength(1); // no further conflict - the normal save now succeeds
      const onDisk = await store.read(created.id);
      expect(onDisk.body).toBe("one more normal edit after the overwrite");
    });

    it("run concurrently with a normal save on the same id, does not tear or duplicate the write", async () => {
      const created = await store.save({ id: null, body: "original" });
      if (created.status !== "saved") throw new Error("unreachable");
      await new Promise((resolve) => setTimeout(resolve, 10));
      await store.save({ id: created.id, body: "changed elsewhere", expectedModifiedAt: created.modifiedAt });

      let body = "local edit before overwrite";
      const conflicts: Array<{ reason: string }> = [];
      const saved: Array<{ id: string; modifiedAt: string }> = [];
      const controller = new AutoSaveController(
        store,
        () => body,
        (info) => conflicts.push(info),
        { id: created.id, body: "original", modifiedAt: created.modifiedAt },
        { onSaved: (info) => saved.push(info) },
      );

      // Both issued synchronously, back to back, unawaited - exercises "a
      // normal save is in flight when overwrite() is called" without
      // needing to hand-orchestrate microtask timing.
      const normalPromise = controller.flush();
      body = "final content the user wants written";
      const overwritePromise = controller.overwrite();
      await Promise.all([normalPromise, overwritePromise]);

      expect(conflicts).toHaveLength(1);
      expect(conflicts[0]!.reason).toBe("modified");
      expect(saved).toHaveLength(1);

      const onDisk = await store.read(created.id);
      expect(onDisk.body).toBe("final content the user wants written");
    });
  });
});
