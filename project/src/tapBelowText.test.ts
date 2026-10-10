import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";

import { bodyWithoutUnusedPadding, forgetTapPadding, linesNeededToReach, padBelowText, tapBelowTextStartsALine } from "./tapBelowText";

function stateWith(doc: string): EditorState {
  return EditorState.create({ doc, extensions: [tapBelowTextStartsALine(() => {})] });
}

function pad(state: EditorState, lines: number): EditorState {
  return state.update(padBelowText(state, lines)).state;
}

function typeAtCaret(state: EditorState, text: string): EditorState {
  const at = state.selection.main.head;
  return state.update({ changes: { from: at, insert: text }, selection: { anchor: at + text.length } }).state;
}

describe("linesNeededToReach", () => {
  it("is 0 for a tap on or above the last line", () => {
    expect(linesNeededToReach(100, 100, 20)).toBe(0);
    expect(linesNeededToReach(50, 100, 20)).toBe(0);
  });

  it("counts the line the tap lands on", () => {
    expect(linesNeededToReach(101, 100, 20)).toBe(1);
    expect(linesNeededToReach(119, 100, 20)).toBe(1);
    expect(linesNeededToReach(120, 100, 20)).toBe(2);
    expect(linesNeededToReach(195, 100, 20)).toBe(5);
  });
});

describe("padBelowText", () => {
  it("adds blank lines after the text and puts the caret at the start of the last one", () => {
    const padded = pad(stateWith("first line"), 3);
    expect(padded.doc.toString()).toBe("first line\n\n\n");
    expect(padded.selection.main.head).toBe(padded.doc.length);
    expect(padded.doc.lineAt(padded.selection.main.head).number).toBe(4);
  });

  it("leaves the text above untouched", () => {
    const padded = typeAtCaret(pad(stateWith("keep me\n- as is"), 2), "new");
    expect(padded.doc.toString()).toBe("keep me\n- as is\n\nnew");
  });
});

describe("bodyWithoutUnusedPadding", () => {
  it("is the whole text when nothing was padded", () => {
    expect(bodyWithoutUnusedPadding(stateWith("text\n\n"))).toBe("text\n\n");
  });

  it("drops padding nothing was typed after", () => {
    expect(bodyWithoutUnusedPadding(pad(stateWith("text"), 4))).toBe("text");
  });

  it("is empty for a blank QuKi that was only tapped, so no QuKi gets created", () => {
    expect(bodyWithoutUnusedPadding(pad(stateWith(""), 6))).toBe("");
  });

  it("keeps the padding once something is typed after it", () => {
    const typed = typeAtCaret(pad(stateWith("text"), 2), "more");
    expect(bodyWithoutUnusedPadding(typed)).toBe("text\n\nmore");
  });

  it("keeps blank lines that were already in the QuKi before the tap", () => {
    expect(bodyWithoutUnusedPadding(pad(stateWith("text\n\n"), 2))).toBe("text\n\n");
  });

  it("treats a second tap further down as more of the same padding", () => {
    expect(bodyWithoutUnusedPadding(pad(pad(stateWith("text"), 2), 3))).toBe("text");
  });

  it("keeps the padding's start right when text is typed above it", () => {
    const padded = pad(stateWith("text"), 3);
    const editedAbove = padded.update({ changes: { from: 0, insert: "new " } }).state;
    expect(bodyWithoutUnusedPadding(editedAbove)).toBe("new text");
  });

  it("forgets the padding when a different QuKi is loaded", () => {
    const padded = pad(stateWith("text"), 3);
    const loaded = padded.update({ changes: { from: 0, to: padded.doc.length, insert: "other\n\n" } }, forgetTapPadding()).state;
    expect(bodyWithoutUnusedPadding(loaded)).toBe("other\n\n");
  });
});
