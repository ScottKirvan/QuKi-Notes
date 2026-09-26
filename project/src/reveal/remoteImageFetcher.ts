import { Facet } from "@codemirror/state";

/**
 * Fetches a remote image (an `http(s)://` markdown image URL, as opposed to
 * a local `media/`-relative one — see imageResolver.ts) and returns its raw
 * bytes plus the response's actual Content-Type. Injected from main.ts,
 * where the real `fetch`-backed implementation lives; the reveal engine
 * itself has no network awareness beyond this one injected function.
 *
 * This is a separate facet from ImageResolver, not a second branch of it,
 * because the two differ in ways that matter beyond the input string:
 * - The real implementation needs to validate the HTTP response (status,
 *   Content-Type) and report a distinct failure for each, which a bytes-only
 *   return type can't carry.
 * - The Content-Type is required to build a correctly-typed Blob — a remote
 *   URL often has no reliable file extension to guess a MIME type from the
 *   way local paths do (imageUrlCache's mimeForPath).
 * - Callers (remoteImageCache.ts) cache and rate-limit fetches very
 *   differently from local OPFS reads: session-lifetime, size-capped bytes
 *   rather than a refcounted-while-mounted blob URL.
 */
export type RemoteImageFetcher = (url: string) => Promise<{ bytes: Uint8Array; contentType: string }>;

/**
 * No fetcher configured (e.g. in a test EditorState that never registers
 * this facet) combines to null rather than throwing — ImageWidget treats
 * that as "can't resolve" and falls back to its broken-image state, the
 * same path a real fetch failure takes.
 */
export const remoteImageFetcher = Facet.define<RemoteImageFetcher, RemoteImageFetcher | null>({
  combine: (values) => (values.length > 0 ? values[values.length - 1]! : null),
});
