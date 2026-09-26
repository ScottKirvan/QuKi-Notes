import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";

import { buildTransaction, currentHeadingLevel, readEditorValue } from "./toolbarAdapter";
import type { EditorValue } from "./toolbar/types";

function state(doc: string, anchor: number, head = anchor): EditorState {
  return EditorState.create({ doc, selection: { anchor, head } });
}

describe("readEditorValue", () => {
  it("reads the document text and a collapsed selection as anchor === head", () => {
    expect(readEditorValue(state("hello world", 3))).toEqual({
      text: "hello world",
      selection: { anchor: 3, head: 3 },
    });
  });

  it("reads a real range selection with anchor and head distinct", () => {
    expect(readEditorValue(state("hello world", 2, 7))).toEqual({
      text: "hello world",
      selection: { anchor: 2, head: 7 },
    });
  });

  it("preserves a reversed selection (head before anchor) rather than normalizing it", () => {
    expect(readEditorValue(state("hello world", 7, 2))).toEqual({
      text: "hello world",
      selection: { anchor: 7, head: 2 },
    });
  });
});

describe("currentHeadingLevel", () => {
  it("is 0 on a plain paragraph line", () => {
    expect(currentHeadingLevel(state("hello", 2))).toBe(0);
  });

  it("reports the heading level of the line containing the caret", () => {
    expect(currentHeadingLevel(state("## Title\nbody", 5))).toBe(2);
  });

  it("uses the line under the caret on a later line, not the document start", () => {
    expect(currentHeadingLevel(state("plain\n# Heading", 8))).toBe(1);
  });

  it("is 0 on a line that only looks like a heading (no space after #)", () => {
    expect(currentHeadingLevel(state("#notaheading", 3))).toBe(0);
  });
});

describe("buildTransaction", () => {
  it("returns null for a true no-op — neither text nor selection changed", () => {
    const before: EditorValue = { text: "abc", selection: { anchor: 1, head: 1 } };
    const after: EditorValue = { text: "abc", selection: { anchor: 1, head: 1 } };
    expect(buildTransaction(before, after)).toBeNull();
  });

  it("returns a selection-only spec when only the caret moved", () => {
    const before: EditorValue = { text: "abc", selection: { anchor: 1, head: 1 } };
    const after: EditorValue = { text: "abc", selection: { anchor: 3, head: 3 } };
    expect(buildTransaction(before, after)).toEqual({ selection: { anchor: 3, head: 3 } });
  });

  it("returns a full-document replace plus selection when the text changed", () => {
    const before: EditorValue = { text: "word", selection: { anchor: 0, head: 4 } };
    const after: EditorValue = { text: "**word**", selection: { anchor: 8, head: 8 } };
    expect(buildTransaction(before, after)).toEqual({
      changes: { from: 0, to: 4, insert: "**word**" },
      selection: { anchor: 8, head: 8 },
      scrollIntoView: true,
    });
  });
});
