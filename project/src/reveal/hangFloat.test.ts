import { describe, expect, it } from "vitest";
import { floatSpan, rowTopFor, secondRowBox, type VerticalBox } from "./hangFloat";

const box = (top: number, bottom: number): VerticalBox => ({ top, bottom });

describe("secondRowBox", () => {
  it("is null for a line that fits on one row", () => {
    expect(secondRowBox([box(0, 20), box(0, 20), box(0, 20)])).toBeNull();
  });

  it("is null for no boxes", () => {
    expect(secondRowBox([])).toBeNull();
  });

  it("is the first box that sits on the next row", () => {
    const boxes = [box(0, 20), box(0, 20), box(28, 48), box(28, 48), box(56, 76)];
    expect(secondRowBox(boxes)).toEqual(box(28, 48));
  });

  it("does not mistake a slightly taller or offset box on the first row for the next row", () => {
    const boxes = [box(2, 22), box(0, 24), box(4, 20), box(1, 21), box(28, 48)];
    expect(secondRowBox(boxes)).toEqual(box(28, 48));
  });

  it("finds the next row when the line height is smaller than the glyph box", () => {
    expect(secondRowBox([box(0, 24), box(0, 24), box(14, 38)])).toEqual(box(14, 38));
  });

  it("reads lazily, stopping at the first box on the next row", () => {
    let pulled = 0;
    function* boxes(): Generator<VerticalBox> {
      for (const b of [box(0, 20), box(0, 20), box(28, 48), box(56, 76)]) {
        pulled += 1;
        yield b;
      }
    }
    expect(secondRowBox(boxes())).toEqual(box(28, 48));
    expect(pulled).toBe(3);
  });
});

describe("rowTopFor", () => {
  it("is the glyph box's top less the half-leading the line height adds above it", () => {
    expect(rowTopFor(box(30, 51), 27)).toBe(27);
  });

  it("is the glyph box's top when the line height equals the glyph box", () => {
    expect(rowTopFor(box(30, 50), 20)).toBe(30);
  });

  it("puts the row top below the glyph top when the line height is smaller than the glyph box", () => {
    expect(rowTopFor(box(30, 54), 20)).toBe(32);
  });
});

describe("floatSpan", () => {
  it("starts a little below the second row's top and ends just below the last row's center", () => {
    expect(floatSpan(27, 66, 2)).toEqual({ top: 29, height: 38 });
  });

  it("is still one pixel tall when the last row's center is not below the start", () => {
    expect(floatSpan(27, 20, 2)).toEqual({ top: 29, height: 1 });
  });
});
