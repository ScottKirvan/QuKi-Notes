import { afterEach, describe, expect, it, vi } from "vitest";
import { acquireImageUrl, releaseImageUrl, __resetImageUrlCacheForTests } from "./imageUrlCache";
import type { ImageResolver } from "./imageResolver";

function fakeBytes(): Uint8Array {
  return new Uint8Array([1, 2, 3, 4]);
}

afterEach(() => {
  __resetImageUrlCacheForTests();
  vi.restoreAllMocks();
});

describe("imageUrlCache", () => {
  it("resolves a real blob: URL from resolver-provided bytes", async () => {
    const resolver: ImageResolver = vi.fn(async () => fakeBytes());
    const url = await acquireImageUrl("media/a.png", resolver);
    expect(url.startsWith("blob:")).toBe(true);
    releaseImageUrl("media/a.png");
  });

  it("dedupes concurrent/overlapping acquires for the same path — resolver runs once", async () => {
    const resolver: ImageResolver = vi.fn(async () => fakeBytes());
    const [urlA, urlB] = await Promise.all([
      acquireImageUrl("media/b.png", resolver),
      acquireImageUrl("media/b.png", resolver),
    ]);
    expect(urlA).toBe(urlB);
    expect(resolver).toHaveBeenCalledTimes(1);
    releaseImageUrl("media/b.png");
    releaseImageUrl("media/b.png");
  });

  it("does not revoke while a second reference is still held", async () => {
    const revokeSpy = vi.spyOn(URL, "revokeObjectURL");
    const resolver: ImageResolver = vi.fn(async () => fakeBytes());
    await acquireImageUrl("media/c.png", resolver);
    await acquireImageUrl("media/c.png", resolver); // second reference

    releaseImageUrl("media/c.png"); // drop to 1 reference
    expect(revokeSpy).not.toHaveBeenCalled();

    releaseImageUrl("media/c.png"); // drop to 0 — now it revokes
    await Promise.resolve();
    await Promise.resolve();
    expect(revokeSpy).toHaveBeenCalledTimes(1);
  });

  it("revokes the blob URL once the last reference is released", async () => {
    const revokeSpy = vi.spyOn(URL, "revokeObjectURL");
    const resolver: ImageResolver = vi.fn(async () => fakeBytes());
    const url = await acquireImageUrl("media/d.png", resolver);

    releaseImageUrl("media/d.png");
    // revocation runs off the entry's own promise continuation, not
    // synchronously inside release — flush microtasks before asserting.
    await Promise.resolve();
    await Promise.resolve();

    expect(revokeSpy).toHaveBeenCalledWith(url);
  });

  it("re-resolves from scratch after the cache has fully drained", async () => {
    const resolver: ImageResolver = vi.fn(async () => fakeBytes());
    await acquireImageUrl("media/e.png", resolver);
    releaseImageUrl("media/e.png");
    await Promise.resolve();

    await acquireImageUrl("media/e.png", resolver);
    expect(resolver).toHaveBeenCalledTimes(2);
    releaseImageUrl("media/e.png");
  });

  it("propagates a resolver rejection to the caller instead of hanging or throwing uncaught", async () => {
    const resolver: ImageResolver = vi.fn(async () => {
      throw new Error("OPFS entry not found");
    });
    await expect(acquireImageUrl("media/missing.png", resolver)).rejects.toThrow("OPFS entry not found");
    // Releasing after a failed resolve must not throw.
    expect(() => releaseImageUrl("media/missing.png")).not.toThrow();
  });

  it("picks the MIME type from the file extension so the blob decodes as an image", async () => {
    const resolver: ImageResolver = vi.fn(async () => fakeBytes());
    const createSpy = vi.spyOn(URL, "createObjectURL");
    await acquireImageUrl("media/f.jpg", resolver);
    const blobArg = createSpy.mock.calls[0]![0] as Blob;
    expect(blobArg.type).toBe("image/jpeg");
    releaseImageUrl("media/f.jpg");
  });
});
