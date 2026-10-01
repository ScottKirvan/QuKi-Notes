export interface SendResult {
  ok: boolean;
  /**
   * The outcome message to show in a toast, or undefined when the
   * transport's own UI already gave the person feedback (the Android and
   * Web Share system share sheets are each their own confirmation - no
   * app-level message belongs on top of them). Always present on failure.
   */
  message: string | undefined;
  durationMs: number;
  retryable: boolean;
}

/**
 * A destination for a QuKi's body text - `navigator.clipboard.writeText` on
 * Electron/desktop, a native Android share-sheet launch (androidShare.ts's
 * shareTextViaAndroid), or the Web Share sheet (webShare.ts's
 * createWebShareTransport). Named generically rather than ClipboardWriter
 * now that clipboard is only one of its implementations.
 *
 * Resolves to the message sendQuKi should report on success, or undefined
 * when the transport's own UI is sufficient feedback on its own.
 */
export type ShareTransport = (text: string) => Promise<string | undefined>;

/**
 * Picks which ShareTransport sendCurrentQuKi (main.ts) hands to sendQuKi -
 * the native Android share sheet where it exists, the Electron clipboard
 * fallback on desktop (navigator.share has no Electron bridge at all - see
 * main.ts's Send wiring for why), or the Web Share transport (which itself
 * falls back to clipboard when navigator.share isn't available) everywhere
 * else. Pulled out as its own pure function so this platform branch is
 * unit-testable without a DOM/Capacitor environment; main.ts itself has no
 * test suite (it wires real DOM elements at app startup).
 */
export function selectShareTransport(
  isAndroid: boolean,
  isElectronDesktop: boolean,
  androidTransport: ShareTransport,
  clipboardTransport: ShareTransport,
  webTransport: ShareTransport,
): ShareTransport {
  if (isAndroid) return androidTransport;
  if (isElectronDesktop) return clipboardTransport;
  return webTransport;
}

/**
 * The plain "write the text and say so" transport - Electron/desktop's only
 * transport, and Web Share's fallback when navigator.share isn't available.
 * Takes the actual clipboard write as a parameter so this stays
 * unit-testable without a real Clipboard API.
 */
export function createClipboardTransport(writeText: (text: string) => Promise<void>): ShareTransport {
  return async (text: string): Promise<string> => {
    await writeText(text);
    return "Copied to clipboard.";
  };
}

/**
 * BEHAVIOR_SPEC.md §4 "Send": the empty-body guard uses the same definition
 * of empty as STORAGE_CONTRACT.md rule 16 / QuKiStore.save() - the literal
 * empty string, not a whitespace-only check - so this agrees with what
 * auto-save itself would have skipped writing.
 *
 * The caller is responsible for flushing auto-save before calling this (see
 * BEHAVIOR_SPEC.md §4: "Content is flushed to disk before sending") and for
 * reading the body straight from the editor afterward, so `body` here is
 * always the latest content, not a stale copy.
 */
export async function sendQuKi(body: string, transport: ShareTransport): Promise<SendResult> {
  if (body === "") {
    return { ok: false, message: "Nothing to send — write something first.", durationMs: 2000, retryable: false };
  }
  try {
    const message = await transport(body);
    return { ok: true, message, durationMs: 2000, retryable: false };
  } catch (error) {
    console.error("QuKi send failed unexpectedly:", error);
    return { ok: false, message: "Send failed — unexpected error.", durationMs: 4000, retryable: true };
  }
}
