import type { RemoteImageFetcher } from "./remoteImageFetcher";

interface CacheEntry {
  bytes: Uint8Array;
  contentType: string;
  size: number;
}

// Generous for the handful of remote images a single session is likely to
// display, small enough not to be a meaningful memory concern. Not a
// `const` because tests override it (via __setMaxCacheBytesForTests) to
// exercise real eviction at a tractable scale rather than asserting it only
// by inference.
let maxCacheBytes = 50 * 1024 * 1024;

/**
 * Session-lifetime, size-capped cache of URL -> fetched image bytes.
 *
 * This is deliberately not the same shape as imageUrlCache's refcounted
 * blob: URL cache for local images. That cache ties a blob: URL's lifetime
 * to how many mounted widgets currently reference it, which is the right
 * model for OPFS reads (cheap to redo, no reason to keep bytes around once
 * nothing displays them). A remote fetch is a real network request — worth
 * avoiding on every reveal recomputation and on revisiting a note later in
 * the same session — so bytes are kept here independent of any widget's
 * mount state, evicted only by a size cap (oldest-accessed first), never by
 * a widget unmounting.
 *
 * Because eviction can happen at any time (not just when nothing references
 * an entry), this cache never hands out a shared blob: URL — a widget that
 * still had one open would go blank the moment its entry was evicted. Each
 * ImageWidget instead mints and revokes its own blob: URL from these bytes
 * (see widgets.ts), so eviction only ever affects a future fetch, never a
 * currently-displayed image.
 */
const cache = new Map<string, CacheEntry>();
let totalCachedBytes = 0;

const inFlight = new Map<string, Promise<CacheEntry>>();

function touch(url: string, entry: CacheEntry): void {
  // Map iteration order is insertion order; deleting and re-setting moves
  // this entry to the most-recently-used end, so a plain forward iteration
  // in evictUntilFits visits least-recently-used entries first.
  cache.delete(url);
  cache.set(url, entry);
}

function evictUntilFits(incomingSize: number): void {
  for (const [url, entry] of cache) {
    if (totalCachedBytes + incomingSize <= maxCacheBytes) break;
    cache.delete(url);
    totalCachedBytes -= entry.size;
  }
}

/**
 * Returns the given remote image's bytes and content type, from cache when
 * available. Concurrent calls for the same URL share one in-flight fetch. A
 * rejected fetch is never cached, so the next call retries from scratch.
 */
export async function fetchRemoteImageBytes(
  url: string,
  fetcher: RemoteImageFetcher,
): Promise<{ bytes: Uint8Array; contentType: string }> {
  const cached = cache.get(url);
  if (cached) {
    touch(url, cached);
    return cached;
  }

  let pending = inFlight.get(url);
  if (!pending) {
    pending = fetcher(url)
      .then((result) => {
        const entry: CacheEntry = { ...result, size: result.bytes.byteLength };
        // A single image bigger than the whole cap is served but not
        // retained, rather than evicting every other cached image to make
        // room for it.
        if (entry.size <= maxCacheBytes) {
          evictUntilFits(entry.size);
          cache.set(url, entry);
          totalCachedBytes += entry.size;
        }
        return entry;
      })
      .finally(() => {
        inFlight.delete(url);
      });
    inFlight.set(url, pending);
  }
  return pending;
}

/** Test-only: reset cache state between unit tests. */
export function __resetRemoteImageCacheForTests(): void {
  cache.clear();
  inFlight.clear();
  totalCachedBytes = 0;
  maxCacheBytes = 50 * 1024 * 1024;
}

/** Test-only: override the size cap to exercise eviction at a small scale. */
export function __setMaxCacheBytesForTests(bytes: number): void {
  maxCacheBytes = bytes;
}
