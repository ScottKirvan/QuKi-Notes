import { describe, expect, it } from "vitest";

import { wrapSelection } from "./wrap";
import type { EditorValue } from "./types";

function v(text: string, anchor: number, head = anchor): EditorValue {
  return { text, selection: { anchor, head } };
}

// Ported from formatting_toolbar_test.dart's "wrapSelection" and
// "FormattingToolbar widget" groups.
describe("wrapSelection", () => {
  it("wraps selected text with bold markers", () => {
    const result = wrapSelection(v("hello world", 6, 11), "**", "**");
    expect(result.text).toBe("hello **world**");
  });

  it("inserts markers at cursor when no selection, caret placed between them", () => {
    const result = wrapSelection(v("hello", 5), "_", "_");
    expect(result.text).toBe("hello__");
    expect(result.selection).toEqual({ anchor: 6, head: 6 });
  });

  it("wraps with italic markers (underscore, not asterisk — deliberate)", () => {
    const result = wrapSelection(v("word", 0, 4), "_", "_");
    expect(result.text).toBe("_word_");
  });

  it("wraps with strikethrough markers", () => {
    const result = wrapSelection(v("word", 0, 4), "~~", "~~");
    expect(result.text).toBe("~~word~~");
  });

  it("wraps with inline code markers", () => {
    const result = wrapSelection(v("word", 0, 4), "`", "`");
    expect(result.text).toBe("`word`");
  });

  it("places the caret after the closing delimiter for a real selection", () => {
    const result = wrapSelection(v("hello world", 6, 11), "**", "**");
    expect(result.selection).toEqual({ anchor: 15, head: 15 });
  });

  it("a reversed selection (head before anchor) wraps the same range", () => {
    const result = wrapSelection(v("word", 4, 0), "~~", "~~");
    expect(result.text).toBe("~~word~~");
  });
});
