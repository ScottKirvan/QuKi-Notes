import { describe, expect, it } from "vitest";

import { DEFAULT_FONT_SIZE, FONT_SIZES, fontSizePx, parseFontSize } from "./fontSize";

describe("font size steps", () => {
  it("offers Small, Normal, Large and Extra large, in that order", () => {
    expect(FONT_SIZES.map((size) => size.label)).toEqual(["Small", "Normal", "Large", "Extra large"]);
  });

  it("keeps Normal at the editor's original 16px and defaults to it", () => {
    expect(DEFAULT_FONT_SIZE).toBe("normal");
    expect(fontSizePx("normal")).toBe(16);
  });

  it("grows strictly from each step to the next", () => {
    const px = FONT_SIZES.map((size) => size.px);
    for (let i = 1; i < px.length; i++) expect(px[i]).toBeGreaterThan(px[i - 1]!);
  });

  it("reads back every stored step", () => {
    for (const size of FONT_SIZES) expect(parseFontSize(size.id)).toBe(size.id);
  });

  it("falls back to Normal for nothing stored or an unknown value", () => {
    expect(parseFontSize(null)).toBe("normal");
    expect(parseFontSize("huge")).toBe("normal");
    expect(parseFontSize("")).toBe("normal");
  });
});
