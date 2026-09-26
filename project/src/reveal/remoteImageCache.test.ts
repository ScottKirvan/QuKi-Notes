import { afterEach, describe, expect, it, vi } from "vitest";
import {
  fetchRemoteImageBytes,
  __resetRemoteImageCacheForTests,
  __setMaxCacheBytesForTests,
} from "./remoteImageCache";
import type { RemoteImageFetcher } from "./remoteImageFetcher";

function fakeBytes(length = 4): Uint8Array {
  return new Uint8Array(length).fill(7);
}

afterEach(() => {
  __resetRemoteImageCacheForTests();
  vi.restoreAllMocks();
});

describe("remoteImageCache", () => {
  it("fetches and returns bytes + content type from the fetcher", async () => {
    const fetcher: RemoteImageFetcher = vi.fn(async () => ({ bytes: fakeBytes(), contentType: "image/png" }));
    const result = await fetchRemoteImageBytes("https://example.com/a.png", fetcher);
    expect(result.contentType).toBe("image/png");
    expect(result.bytes).toEqual(fakeBytes());
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("does not refetch a URL already in cache", async () => {
    const fetcher: RemoteImageFetcher = vi.fn(async () => ({ bytes: fakeBytes(), contentType: "image/png" }));
    await fetchRemoteImageBytes("https://example.com/b.png", fetcher);
    await fetchRemoteImageBytes("https://example.com/b.png", fetcher);
    await fetchRemoteImageBytes("https://example.com/b.png", fetcher);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("dedupes concurrent/overlapping fetches for the same URL — fetcher runs once", async () => {
    const fetcher: RemoteImageFetcher = vi.fn(async () => ({ bytes: fakeBytes(), contentType: "image/png" }));
    const [a, b] = await Promise.all([
      fetchRemoteImageBytes("https://example.com/c.png", fetcher),
      fetchRemoteImageBytes("https://example.com/c.png", fetcher),
    ]);
    expect(a).toEqual(b);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it("fetches different URLs independently", async () => {
    const fetcher: RemoteImageFetcher = vi.fn(async (url: string) => ({
      bytes: fakeBytes(),
      contentType: url.endsWith(".jpg") ? "image/jpeg" : "image/png",
    }));
    const png = await fetchRemoteImageBytes("https://example.com/d.png", fetcher);
    const jpg = await fetchRemoteImageBytes("https://example.com/d.jpg", fetcher);
    expect(png.contentType).toBe("image/png");
    expect(jpg.contentType).toBe("image/jpeg");
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it("propagates a fetcher rejection to the caller instead of hanging or throwing uncaught", async () => {
    const fetcher: RemoteImageFetcher = vi.fn(async () => {
      throw new Error("404 Not Found");
    });
    await expect(fetchRemoteImageBytes("https://example.com/missing.png", fetcher)).rejects.toThrow(
      "404 Not Found",
    );
  });

  it("retries from scratch after a rejected fetch rather than caching the failure", async () => {
    const fetcher: RemoteImageFetcher = vi
      .fn()
      .mockRejectedValueOnce(new Error("network error"))
      .mockResolvedValueOnce({ bytes: fakeBytes(), contentType: "image/png" });
    await expect(fetchRemoteImageBytes("https://example.com/e.png", fetcher)).rejects.toThrow("network error");
    const result = await fetchRemoteImageBytes("https://example.com/e.png", fetcher);
    expect(result.contentType).toBe("image/png");
    expect(fetcher).toHaveBeenCalledTimes(2);
  });

  it("evicts the least-recently-used entry once the size cap is exceeded", async () => {
    __setMaxCacheBytesForTests(10); // 10 bytes: room for two 5-byte images, not three
    const fetcher: RemoteImageFetcher = vi.fn(async () => ({ bytes: fakeBytes(5), contentType: "image/png" }));

    await fetchRemoteImageBytes("https://example.com/g1.png", fetcher);
    await fetchRemoteImageBytes("https://example.com/g2.png", fetcher);
    // g3 pushes the cache over its cap — g1 (least recently used) is evicted, g2 survives.
    await fetchRemoteImageBytes("https://example.com/g3.png", fetcher);
    expect(fetcher).toHaveBeenCalledTimes(3);

    await fetchRemoteImageBytes("https://example.com/g1.png", fetcher); // evicted — refetches
    expect(fetcher).toHaveBeenCalledTimes(4);

    await fetchRemoteImageBytes("https://example.com/g3.png", fetcher); // still cached — no refetch
    expect(fetcher).toHaveBeenCalledTimes(4);
  });

  it("touching a cached entry protects it from eviction ahead of one fetched earlier but used more recently", async () => {
    __setMaxCacheBytesForTests(10);
    const fetcher: RemoteImageFetcher = vi.fn(async () => ({ bytes: fakeBytes(5), contentType: "image/png" }));

    await fetchRemoteImageBytes("https://example.com/h1.png", fetcher);
    await fetchRemoteImageBytes("https://example.com/h2.png", fetcher);
    await fetchRemoteImageBytes("https://example.com/h1.png", fetcher); // touch h1 — h2 is now LRU
    expect(fetcher).toHaveBeenCalledTimes(2);

    await fetchRemoteImageBytes("https://example.com/h3.png", fetcher); // evicts h2, not h1
    expect(fetcher).toHaveBeenCalledTimes(3);

    await fetchRemoteImageBytes("https://example.com/h1.png", fetcher); // still cached
    expect(fetcher).toHaveBeenCalledTimes(3);
    await fetchRemoteImageBytes("https://example.com/h2.png", fetcher); // evicted — refetches
    expect(fetcher).toHaveBeenCalledTimes(4);
  });

  it("serves a single image larger than the whole cap without retaining it", async () => {
    __setMaxCacheBytesForTests(10);
    const fetcher: RemoteImageFetcher = vi.fn(async () => ({ bytes: fakeBytes(20), contentType: "image/png" }));

    const first = await fetchRemoteImageBytes("https://example.com/huge.png", fetcher);
    expect(first.bytes.byteLength).toBe(20);
    // Not retained (bigger than the cap) — asking again refetches rather
    // than reusing a cached copy that was never stored.
    await fetchRemoteImageBytes("https://example.com/huge.png", fetcher);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
});
