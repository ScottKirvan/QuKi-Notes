export interface SendResult {
  ok: boolean;
  message: string;
  durationMs: number;
  retryable: boolean;
}

/**
 * A destination for a QuKi's body text - `navigator.clipboard.writeText` on
 * Electron/desktop, or a native Android share-sheet launch
 * (androidShare.ts's shareTextViaAndroid). Named generically rather than
 * ClipboardWriter now that clipboard is only one of its implementations.
 */
export type ShareTransport = (text: string) => Promise<void>;

/**
 * Picks which ShareTransport sendCurrentQuKi (main.ts) hands to sendQuKi -
 * the native Android share sheet where it exists, clipboard everywhere
 * else. Pulled out as its own pure function so this platform branch is
 * unit-testable without a DOM/Capacitor environment; main.ts itself has no
 * test suite (it wires real DOM elements at app startup).
 */
export function selectShareTransport(isAndroid: boolean, androidTransport: ShareTransport, clipboardTransport: ShareTransport): ShareTransport {
  return isAndroid ? androidTransport : clipboardTransport;
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
    await transport(body);
    return { ok: true, message: "Copied to clipboard.", durationMs: 2000, retryable: false };
  } catch (error) {
    console.error("QuKi send (clipboard write) failed unexpectedly:", error);
    return { ok: false, message: "Send failed — unexpected error.", durationMs: 4000, retryable: true };
  }
}
