import { describe, expect, it, vi } from "vitest";

import { selectShareTransport, sendQuKi } from "./send.js";

describe("sendQuKi", () => {
  it("does not send and returns the empty-body message when the body is the empty string", async () => {
    const clipboardWriter = vi.fn().mockResolvedValue(undefined);

    const result = await sendQuKi("", clipboardWriter);

    expect(result).toEqual({
      ok: false,
      message: "Nothing to send — write something first.",
      durationMs: 2000,
      retryable: false,
    });
    expect(clipboardWriter).not.toHaveBeenCalled();
  });

  it("treats whitespace-only content as non-empty, matching QuKiStore.save()'s literal-empty-string rule", async () => {
    const clipboardWriter = vi.fn().mockResolvedValue(undefined);

    const result = await sendQuKi("   ", clipboardWriter);

    expect(result.ok).toBe(true);
    expect(clipboardWriter).toHaveBeenCalledWith("   ");
  });

  it("writes the body to the clipboard and reports success", async () => {
    const clipboardWriter = vi.fn().mockResolvedValue(undefined);

    const result = await sendQuKi("hello world", clipboardWriter);

    expect(clipboardWriter).toHaveBeenCalledWith("hello world");
    expect(result).toEqual({
      ok: true,
      message: "Copied to clipboard.",
      durationMs: 2000,
      retryable: false,
    });
  });

  it("reports a retryable failure when the clipboard write throws", async () => {
    const clipboardWriter = vi.fn().mockRejectedValue(new Error("clipboard unavailable"));

    const result = await sendQuKi("hello world", clipboardWriter);

    expect(result).toEqual({
      ok: false,
      message: "Send failed — unexpected error.",
      durationMs: 4000,
      retryable: true,
    });
  });
});

describe("selectShareTransport", () => {
  it("picks the Android transport when isAndroid is true", () => {
    const androidTransport = vi.fn();
    const clipboardTransport = vi.fn();

    expect(selectShareTransport(true, androidTransport, clipboardTransport)).toBe(androidTransport);
  });

  it("picks the clipboard transport when isAndroid is false", () => {
    const androidTransport = vi.fn();
    const clipboardTransport = vi.fn();

    expect(selectShareTransport(false, androidTransport, clipboardTransport)).toBe(clipboardTransport);
  });
});
