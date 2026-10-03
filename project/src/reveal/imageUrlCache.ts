import type { ImageResolver } from "./imageResolver";

const EXTENSION_TO_MIME: Record<string, string> = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
};

function mimeForPath(relPath: string): string {
  const ext = relPath.slice(relPath.lastIndexOf(".") + 1).toLowerCase();
  return EXTENSION_TO_MIME[ext] ?? "application/octet-stream";
}

interface CacheEntry {
  refCount: number;
  urlPromise: Promise<string>;
}

/**
 * Reference-counted cache of relPath -> blob URL, module-scoped so every
 * ImageWidget instance for the same image (whether reused across a
 * decoration rebuild or mounted independently at two locations in the same
 * document) shares one blob: URL rather than re-reading OPFS and minting a
 * fresh one on every keystroke elsewhere in the document.
 *
 * A widget acquires on toDOM() and releases on destroy(). The entry (and
 * its blob URL) is only revoked once its refCount drops to zero — not on
 * every individual release — so two widgets pointing at the same image
 * don't fight over the URL's lifetime.
 */
const cache = new Map<string, CacheEntry>();

export function acquireImageUrl(relPath: string, resolve: ImageResolver): Promise<string> {
  let entry = cache.get(relPath);
  if (!entry) {
    const urlPromise = resolve(relPath).then((bytes) => {
      // Uint8Array<ArrayBufferLike> vs BlobPart's Uint8Array<ArrayBuffer> is
      // a TS lib-typing mismatch, not a real runtime concern (see the same
      // cast in core/src/export.ts) — bytes are never backed by a
      // SharedArrayBuffer here.
      const blob = new Blob([bytes as unknown as BlobPart], { type: mimeForPath(relPath) });
      return URL.createObjectURL(blob);
    });
    entry = { refCount: 0, urlPromise };
    cache.set(relPath, entry);
  }
  entry.refCount += 1;
  return entry.urlPromise;
}

export function releaseImageUrl(relPath: string): void {
  const entry = cache.get(relPath);
  if (!entry) return;
  entry.refCount -= 1;
  if (entry.refCount > 0) return;

  // Drop the entry immediately so a subsequent acquire (e.g. the widget
  // remounting right after) starts a fresh resolve rather than reusing a
  // URL that's about to be revoked underneath it.
  cache.delete(relPath);
  entry.urlPromise.then(
    (url) => URL.revokeObjectURL(url),
    () => {
      // Resolution never produced a URL — nothing to revoke.
    },
  );
}

/** Test-only: reset cache state between unit tests. */
export function __resetImageUrlCacheForTests(): void {
  cache.clear();
}
