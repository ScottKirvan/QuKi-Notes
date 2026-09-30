import type { ShareTransport } from "./send.js";

/**
 * The shape of `navigator.share` this module actually calls - just enough
 * of the real `Navigator.share(data: ShareData)` to type-check a plain
 * object literal, and small enough to fake in a test without touching the
 * DOM. Passed in rather than read from `navigator` internally so this stays
 * unit-testable in plain Node (this project's tests run without a DOM,
 * matching the existing convention - see ElectronIpcBackend's doc comment).
 */
export type WebShareApi = (data: { text: string }) => Promise<void>;

/**
 * STORAGE_CONTRACT.md's web-Send transport: the real OS share sheet via
 * `navigator.share()`, falling back to the clipboard transport when it
 * isn't available at all (Safari without it, a non-secure context, an
 * older browser) - `shareApi` is undefined in exactly those cases, decided
 * by the caller (main.ts) from `typeof navigator.share`.
 *
 * Resolves to undefined on a completed share, not a message: like Android's
 * native share sheet (androidShare.ts), the browser's own share UI is
 * already the person's feedback that something happened, so no app-level
 * toast belongs on top of it.
 *
 * The person backing out of the share sheet rejects the promise with an
 * AbortError (the Web Share API spec's documented cancellation signal) -
 * that's a deliberate no-op, not a failure, so it resolves quietly rather
 * than surfacing sendQuKi's generic "Send failed" error and Retry action.
 * Any other rejection (no share target, permission denied) is a genuine
 * failure and propagates unchanged for sendQuKi to report as such.
 */
export function createWebShareTransport(shareApi: WebShareApi | undefined, clipboardTransport: ShareTransport): ShareTransport {
  return async (text: string): Promise<string | undefined> => {
    if (!shareApi) return clipboardTransport(text);
    try {
      await shareApi({ text });
      return undefined;
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return undefined;
      throw error;
    }
  };
}
