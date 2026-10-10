import { describe, expect, it } from "vitest";

import { bottomScrollMargin, shouldRevealCaretAfterResize } from "./caretClearance";

describe("bottomScrollMargin", () => {
  it("keeps the toolbar plus two lines clear below the caret while the toolbar shows", () => {
    expect(bottomScrollMargin(36, 22.4)).toBeCloseTo(36 + 44.8);
  });

  it("follows the editor's line height", () => {
    expect(bottomScrollMargin(36, 30)).toBe(96);
  });

  it("keeps no margin while the toolbar is hidden (reading mode)", () => {
    expect(bottomScrollMargin(0, 22.4)).toBe(0);
  });
});

describe("shouldRevealCaretAfterResize", () => {
  it("reveals the caret when the editor shrinks while the toolbar shows (the keyboard rose)", () => {
    expect(shouldRevealCaretAfterResize(700, 400, 36)).toBe(true);
  });

  it("leaves the scroll alone when the editor grows (the keyboard went down)", () => {
    expect(shouldRevealCaretAfterResize(400, 700, 36)).toBe(false);
  });

  it("leaves the scroll alone when the size did not change", () => {
    expect(shouldRevealCaretAfterResize(400, 400, 36)).toBe(false);
  });

  it("leaves the scroll alone while reading (toolbar hidden)", () => {
    expect(shouldRevealCaretAfterResize(700, 400, 0)).toBe(false);
  });
});
