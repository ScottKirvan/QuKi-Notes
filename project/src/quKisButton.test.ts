import { describe, expect, it } from "vitest";

import { isQuKisButtonEnabled } from "./quKisButton";

describe("isQuKisButtonEnabled", () => {
  it("is disabled on a first launch: nothing saved and nothing typed", () => {
    expect(isQuKisButtonEnabled({ hasSavedQuKis: false, editorHasText: false })).toBe(false);
  });

  it("is enabled as soon as a character is typed, before any save has landed", () => {
    expect(isQuKisButtonEnabled({ hasSavedQuKis: false, editorHasText: true })).toBe(true);
  });

  it("is enabled whenever a QuKi is saved, even with an empty editor", () => {
    expect(isQuKisButtonEnabled({ hasSavedQuKis: true, editorHasText: false })).toBe(true);
  });

  it("is enabled with saved QuKis and text in the editor", () => {
    expect(isQuKisButtonEnabled({ hasSavedQuKis: true, editorHasText: true })).toBe(true);
  });
});
