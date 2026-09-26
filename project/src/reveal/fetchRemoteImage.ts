import type { RemoteImageFetcher } from "./remoteImageFetcher";

/**
 * The real, browser-`fetch`-backed RemoteImageFetcher wired up in main.ts.
 * Kept separate from remoteImageFetcher.ts's facet/type definition so it can
 * be unit tested without touching CodeMirror state.
 *
 * A non-OK status, a missing/non-image Content-Type, and a network-level
 * failure (offline, DNS, CORS block — `fetch` itself rejects for these) all
 * reject; ImageWidget treats any rejection here identically, falling back to
 * its broken-image state the same way a failed local OPFS read already
 * does.
 */
export const fetchRemoteImage: RemoteImageFetcher = async (url) => {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Remote image fetch failed: ${response.status} ${response.statusText} (${url})`);
  }
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("image/")) {
    throw new Error(`Remote image URL did not return an image (content-type "${contentType}"): ${url}`);
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  return { bytes, contentType };
};
