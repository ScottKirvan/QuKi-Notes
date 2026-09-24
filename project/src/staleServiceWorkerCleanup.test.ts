import { describe, expect, it, vi } from "vitest";

import { cleanupStaleServiceWorker, type StaleServiceWorkerCleanupDeps } from "./staleServiceWorkerCleanup.js";

describe("cleanupStaleServiceWorker", () => {
  it("unregisters every existing service worker registration", async () => {
    const unregisterA = vi.fn(async () => true);
    const unregisterB = vi.fn(async () => true);
    const deps: StaleServiceWorkerCleanupDeps = {
      getRegistrations: vi.fn(async () => [{ unregister: unregisterA }, { unregister: unregisterB }]),
      cacheKeys: vi.fn(async () => []),
      deleteCache: vi.fn(async () => true),
    };

    await cleanupStaleServiceWorker(deps);

    expect(unregisterA).toHaveBeenCalledTimes(1);
    expect(unregisterB).toHaveBeenCalledTimes(1);
  });

  it("deletes every existing Cache Storage entry", async () => {
    const deleteCache = vi.fn(async () => true);
    const deps: StaleServiceWorkerCleanupDeps = {
      getRegistrations: vi.fn(async () => []),
      cacheKeys: vi.fn(async () => ["workbox-precache-v1", "workbox-runtime"]),
      deleteCache,
    };

    await cleanupStaleServiceWorker(deps);

    expect(deleteCache).toHaveBeenCalledWith("workbox-precache-v1");
    expect(deleteCache).toHaveBeenCalledWith("workbox-runtime");
    expect(deleteCache).toHaveBeenCalledTimes(2);
  });

  it("does both together when both a registration and cached entries exist", async () => {
    const unregister = vi.fn(async () => true);
    const deleteCache = vi.fn(async () => true);
    const deps: StaleServiceWorkerCleanupDeps = {
      getRegistrations: vi.fn(async () => [{ unregister }]),
      cacheKeys: vi.fn(async () => ["workbox-precache-v1"]),
      deleteCache,
    };

    await cleanupStaleServiceWorker(deps);

    expect(unregister).toHaveBeenCalledTimes(1);
    expect(deleteCache).toHaveBeenCalledWith("workbox-precache-v1");
  });

  it("is a no-op when there is nothing to clean up", async () => {
    const deps: StaleServiceWorkerCleanupDeps = {
      getRegistrations: vi.fn(async () => []),
      cacheKeys: vi.fn(async () => []),
      deleteCache: vi.fn(async () => true),
    };

    await expect(cleanupStaleServiceWorker(deps)).resolves.toBeUndefined();
  });
});
