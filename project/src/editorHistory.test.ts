import { redoDepth, undo, undoDepth } from "@codemirror/commands";
import { EditorState, type Transaction } from "@codemirror/state";
import { describe, expect, it } from "vitest";

import { replaceDocumentAndForgetHistory, resettableHistory } from "./editorHistory";

function type(state: EditorState, text: string): EditorState {
  return state.update({ changes: { from: state.doc.length, insert: text }, userEvent: "input.type" }).state;
}

function runUndo(state: EditorState): EditorState {
  let next = state;
  undo({ state, dispatch: (tr: Transaction) => (next = tr.state) });
  return next;
}

function load(state: EditorState, body: string): EditorState {
  let next = state;
  for (const spec of replaceDocumentAndForgetHistory(body, next.doc.length)) next = next.update(spec).state;
  return next;
}

describe("replaceDocumentAndForgetHistory", () => {
  it("replaces the document and puts the caret at the start", () => {
    const loaded = load(type(EditorState.create({ extensions: [resettableHistory] }), "first QuKi"), "second QuKi");
    expect(loaded.doc.toString()).toBe("second QuKi");
    expect(loaded.selection.main.head).toBe(0);
  });

  it("leaves nothing to undo, so undo cannot bring back the previous document", () => {
    const typed = type(EditorState.create({ extensions: [resettableHistory] }), "first QuKi");
    expect(undoDepth(typed)).toBeGreaterThan(0);

    const loaded = load(typed, "second QuKi");
    expect(undoDepth(loaded)).toBe(0);
    expect(redoDepth(loaded)).toBe(0);
    expect(runUndo(loaded).doc.toString()).toBe("second QuKi");
  });

  it("leaves nothing to redo either", () => {
    const undone = runUndo(type(EditorState.create({ extensions: [resettableHistory] }), "first QuKi"));
    expect(redoDepth(undone)).toBeGreaterThan(0);

    expect(redoDepth(load(undone, "second QuKi"))).toBe(0);
  });

  it("still records edits made after the load", () => {
    const loaded = load(type(EditorState.create({ extensions: [resettableHistory] }), "first QuKi"), "second QuKi");
    const edited = type(loaded, " edited");
    expect(undoDepth(edited)).toBe(1);
    expect(runUndo(edited).doc.toString()).toBe("second QuKi");
  });
});
