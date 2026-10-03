import { describe, expect, it, vi } from "vitest";

import { createWebShareTransport } from "./webShare.js";

describe("createWebShareTransport", () => {
  it("calls navigator.share with the text and reports no message, matching the native share sheet's own feedback", async () => {
    const shareApi = vi.fn().mockResolvedValue(undefined);
    const clipboardTransport = vi.fn();

    const transport = createWebShareTransport(shareApi, clipboardTransport);
    const message = await transport("hello world");

    expect(shareApi).toHaveBeenCalledWith({ text: "hello world" });
    expect(clipboardTransport).not.toHaveBeenCalled();
    expect(message).toBeUndefined();
  });

  it("falls back to the clipboard transport when navigator.share isn't available", async () => {
    const clipboardTransport = vi.fn().mockResolvedValue("Copied to clipboard.");

    const transport = createWebShareTransport(undefined, clipboardTransport);
    const message = await transport("hello world");

    expect(clipboardTransport).toHaveBeenCalledWith("hello world");
    expect(message).toBe("Copied to clipboard.");
  });

  it("treats the person cancelling the share sheet (AbortError) as a quiet no-op, not a failure", async () => {
    const shareApi = vi.fn().mockRejectedValue(new DOMException("cancelled", "AbortError"));
    const clipboardTransport = vi.fn();

    const transport = createWebShareTransport(shareApi, clipboardTransport);
    const message = await transport("hello world");

    expect(message).toBeUndefined();
    expect(clipboardTransport).not.toHaveBeenCalled();
  });

  it("propagates any other rejection from navigator.share for sendQuKi to report as a real failure", async () => {
    const shareApi = vi.fn().mockRejectedValue(new Error("no share target"));
    const clipboardTransport = vi.fn();

    const transport = createWebShareTransport(shareApi, clipboardTransport);

    await expect(transport("hello world")).rejects.toThrow("no share target");
    expect(clipboardTransport).not.toHaveBeenCalled();
  });
});
