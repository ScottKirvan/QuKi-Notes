import { describe, expect, it } from "vitest";

import { extractPreview } from "./preview.js";

describe("extractPreview", () => {
  it("shows (empty) for an empty string", () => {
    expect(extractPreview("")).toBe("(empty)");
  });

  it("shows (empty) for null (unreadable)", () => {
    expect(extractPreview(null)).toBe("(empty)");
  });

  it("shows (empty) for undefined (unreadable)", () => {
    expect(extractPreview(undefined)).toBe("(empty)");
  });

  it("shows (empty) for whitespace-only content", () => {
    expect(extractPreview("   \n\n  \t \n")).toBe("(empty)");
  });

  it("uses the first non-blank line, skipping leading blank lines", () => {
    expect(extractPreview("\n\n  \nActual content here")).toBe("Actual content here");
  });

  it("strips a single leading '#' heading marker", () => {
    expect(extractPreview("# Title\nbody")).toBe("Title");
  });

  it("strips a multi-level heading marker (h6)", () => {
    expect(extractPreview("###### Deep heading")).toBe("Deep heading");
  });

  it("does not strip a '#' that is not a real heading marker (no space after it)", () => {
    expect(extractPreview("#notaheading rest")).toBe("#notaheading rest");
  });

  it("does not treat a mid-line '#' as a heading marker", () => {
    expect(extractPreview("not # heading")).toBe("not # heading");
  });

  it("shows (empty) when the first non-blank line is only a heading marker with no text", () => {
    expect(extractPreview("###   \nsecond line")).toBe("(empty)");
  });

  it("does not strip a run of '#' with no following space (not a real heading marker)", () => {
    expect(extractPreview("###\nsecond line")).toBe("###");
  });

  it("truncates to 80 characters with an ellipsis", () => {
    const longLine = "x".repeat(120);
    const result = extractPreview(longLine);
    expect(result).toBe(`${"x".repeat(80)}…`);
    expect(result.length).toBe(81);
  });

  it("does not truncate a line at exactly 80 characters", () => {
    const line = "x".repeat(80);
    expect(extractPreview(line)).toBe(line);
  });

  it("does not truncate a line under 80 characters", () => {
    expect(extractPreview("short line")).toBe("short line");
  });

  it("trims trailing whitespace from the preview line", () => {
    expect(extractPreview("some text   \nignored")).toBe("some text");
  });
});
