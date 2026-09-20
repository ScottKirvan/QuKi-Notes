import { describe, expect, it, vi } from "vitest";

import { guardLatest } from "./asyncGuard.js";

function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

describe("guardLatest", () => {
  it("delivers the result when calls resolve in the order they were started", async () => {
    const raw = vi.fn(async (n: number) => n * 2);
    const guarded = guardLatest(raw);

    await expect(guarded(1)).resolves.toBe(2);
    await expect(guarded(2)).resolves.toBe(4);
  });

  it("discards a stale response that resolves after a newer call has already started", async () => {
    const first = deferred<string>();
    const second = deferred<string>();
    const raw = vi.fn().mockImplementationOnce(() => first.promise).mockImplementationOnce(() => second.promise);
    const guarded = guardLatest(raw as (q: string) => Promise<string>);

    const p1 = guarded("older query");
    const p2 = guarded("newer query");

    // The newer call's underlying request resolves first...
    second.resolve("newer result");
    await expect(p2).resolves.toBe("newer result");

    // ...and the older, now-superseded request resolves after it. Its
    // result must be discarded, not delivered to whoever awaited it.
    first.resolve("older result");
    await expect(p1).resolves.toBeUndefined();
  });

  it("lets a call through when it is the only one in flight, even if slow", async () => {
    const slow = deferred<string>();
    const raw = vi.fn(() => slow.promise);
    const guarded = guardLatest(raw);

    const p = guarded();
    slow.resolve("eventually");
    await expect(p).resolves.toBe("eventually");
  });

  it("discards every earlier call when three are started before any resolve", async () => {
    const d1 = deferred<number>();
    const d2 = deferred<number>();
    const d3 = deferred<number>();
    const raw = vi
      .fn()
      .mockImplementationOnce(() => d1.promise)
      .mockImplementationOnce(() => d2.promise)
      .mockImplementationOnce(() => d3.promise);
    const guarded = guardLatest(raw as () => Promise<number>);

    const p1 = guarded();
    const p2 = guarded();
    const p3 = guarded();

    d1.resolve(1);
    d2.resolve(2);
    d3.resolve(3);

    await expect(p3).resolves.toBe(3);
    await expect(p1).resolves.toBeUndefined();
    await expect(p2).resolves.toBeUndefined();
  });
});
