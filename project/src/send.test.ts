import { describe, expect, it, vi } from "vitest";

import { createClipboardTransport, selectShareTransport, sendQuKi } from "./send.js";

describe("sendQuKi", () => {
  it("does not send and returns the empty-body message when the body is the empty string", async () => {
    const transport = vi.fn().mockResolvedValue("Copied to clipboard.");

    const result = await sendQuKi("", transport);

    expect(result).toEqual({
      ok: false,
      message: "Nothing to send — write something first.",
      durationMs: 2000,
      retryable: false,
    });
    expect(transport).not.toHaveBeenCalled();
  });

  it("treats whitespace-only content as non-empty, matching QuKiStore.save()'s literal-empty-string rule", async () => {
    const transport = vi.fn().mockResolvedValue("Copied to clipboard.");

    const result = await sendQuKi("   ", transport);

    expect(result.ok).toBe(true);
    expect(transport).toHaveBeenCalledWith("   ");
  });

  it("sends the body through the transport and reports the transport's own success message", async () => {
    const transport = vi.fn().mockResolvedValue("Copied to clipboard.");

    const result = await sendQuKi("hello world", transport);

    expect(transport).toHaveBeenCalledWith("hello world");
    expect(result).toEqual({
      ok: true,
      message: "Copied to clipboard.",
      durationMs: 2000,
      retryable: false,
    });
  });

  it("reports no message on success when the transport's own UI is sufficient feedback (e.g. a native share sheet)", async () => {
    const transport = vi.fn().mockResolvedValue(undefined);

    const result = await sendQuKi("hello world", transport);

    expect(result).toEqual({
      ok: true,
      message: undefined,
      durationMs: 2000,
      retryable: false,
    });
  });

  it("reports a retryable failure when the transport throws", async () => {
    const transport = vi.fn().mockRejectedValue(new Error("clipboard unavailable"));

    const result = await sendQuKi("hello world", transport);

    expect(result).toEqual({
      ok: false,
      message: "Send failed — unexpected error.",
      durationMs: 4000,
      retryable: true,
    });
  });
});

describe("createClipboardTransport", () => {
  it("writes the text to the clipboard and reports a copied message", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);

    const transport = createClipboardTransport(writeText);
    const message = await transport("hello world");

    expect(writeText).toHaveBeenCalledWith("hello world");
    expect(message).toBe("Copied to clipboard.");
  });
});

describe("selectShareTransport", () => {
  it("picks the Android transport when isAndroid is true, regardless of isElectronDesktop", () => {
    const androidTransport = vi.fn();
    const clipboardTransport = vi.fn();
    const webTransport = vi.fn();

    expect(selectShareTransport(true, true, androidTransport, clipboardTransport, webTransport)).toBe(androidTransport);
    expect(selectShareTransport(true, false, androidTransport, clipboardTransport, webTransport)).toBe(androidTransport);
  });

  it("picks the clipboard transport on Electron desktop when not Android", () => {
    const androidTransport = vi.fn();
    const clipboardTransport = vi.fn();
    const webTransport = vi.fn();

    expect(selectShareTransport(false, true, androidTransport, clipboardTransport, webTransport)).toBe(clipboardTransport);
  });

  it("picks the web transport when neither Android nor Electron desktop", () => {
    const androidTransport = vi.fn();
    const clipboardTransport = vi.fn();
    const webTransport = vi.fn();

    expect(selectShareTransport(false, false, androidTransport, clipboardTransport, webTransport)).toBe(webTransport);
  });
});
