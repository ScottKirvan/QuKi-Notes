import { describe, expect, it } from "vitest";
import { EditorSelection, EditorState, type TransactionSpec } from "@codemirror/state";
import { markdownEditing } from "./markdownEditing";

// Shapes the transactions @codemirror/view 6.43 dispatches when it reads a
// deletion back from the DOM (applyDefaultInsert: "input.type", or
// "input.type.compose" mid-composition) - what an Android keyboard's
// Backspace becomes without EditContext when the browser removes a whole
// rendered marker widget in one go.
function stateAt(doc: string, caretBefore: string | number): EditorState {
  const caret = typeof caretBefore === "number" ? caretBefore : doc.indexOf(caretBefore);
  return EditorState.create({
    doc,
    selection: EditorSelection.cursor(caret),
    extensions: [markdownEditing()],
  });
}

function domDelete(state: EditorState, from: number, to: number, userEvent = "input.type"): EditorState {
  const spec: TransactionSpec = { changes: { from, to }, userEvent };
  return state.update(spec).state;
}

function swallowBeforeCaret(doc: string, caretBefore: string | number, length: number, userEvent?: string): EditorState {
  const state = stateAt(doc, caretBefore);
  const caret = state.selection.main.head;
  return domDelete(state, caret - length, caret, userEvent);
}

describe("a deletion that swallows a whole marker before the caret deletes one character", () => {
  it("a checkbox marker", () => {
    const after = swallowBeforeCaret("- [ ] buy milk", "buy", "- [ ] ".length);
    expect(after.doc.toString()).toBe("- [ ]buy milk");
    expect(after.selection.main.head).toBe("- [ ]".length);
  });

  it("an empty checkbox item", () => {
    const after = swallowBeforeCaret("- [ ] ", 6, 6);
    expect(after.doc.toString()).toBe("- [ ]");
  });

  it("a checked checkbox marker, even mid-composition", () => {
    const after = swallowBeforeCaret("- [x] done", "done", 6, "input.type.compose");
    expect(after.doc.toString()).toBe("- [x]done");
  });

  it("bullet, numbered and quote markers", () => {
    expect(swallowBeforeCaret("- apple", "apple", 2).doc.toString()).toBe("-apple");
    expect(swallowBeforeCaret("* apple", "apple", 2).doc.toString()).toBe("*apple");
    expect(swallowBeforeCaret("+ apple", "apple", 2).doc.toString()).toBe("+apple");
    expect(swallowBeforeCaret("1. one", "one", 3).doc.toString()).toBe("1.one");
    expect(swallowBeforeCaret("1) one", "one", 3).doc.toString()).toBe("1)one");
    expect(swallowBeforeCaret("> quoted", "quoted", 2).doc.toString()).toBe(">quoted");
    expect(swallowBeforeCaret("> > deeper", "deeper", 4).doc.toString()).toBe("> >deeper");
    expect(swallowBeforeCaret("> - [ ] task", "task", 6).doc.toString()).toBe("> - [ ]task");
  });

  it("an indented marker, keeping the indentation", () => {
    const doc = "- parent\n\t- [ ] child";
    expect(swallowBeforeCaret(doc, "child", 6).doc.toString()).toBe("- parent\n\t- [ ]child");
    expect(swallowBeforeCaret("- parent\n  - child", "child", 2).doc.toString()).toBe("- parent\n  -child");
  });

  it("a keyboard Backspace tagged delete.backward", () => {
    const after = swallowBeforeCaret("- [ ] buy", "buy", 6, "delete.backward");
    expect(after.doc.toString()).toBe("- [ ]buy");
  });
});

describe("deletions that are left alone", () => {
  it("deleting a real selection", () => {
    const state = EditorState.create({
      doc: "- [ ] buy milk",
      selection: EditorSelection.range(0, 6),
      extensions: [markdownEditing()],
    });
    expect(domDelete(state, 0, 6).doc.toString()).toBe("buy milk");
  });

  it("deleting ordinary text", () => {
    expect(swallowBeforeCaret("- [ ] buy milk", " milk", 3).doc.toString()).toBe("- [ ]  milk");
  });

  it("a deletion that doesn't end at the caret", () => {
    const state = stateAt("- [ ] buy milk", "milk");
    expect(domDelete(state, 0, 6).doc.toString()).toBe("buy milk");
  });

  it("a deletion running past the marker into the text", () => {
    expect(swallowBeforeCaret("- [ ] buy milk", " milk", 9).doc.toString()).toBe(" milk");
  });

  it("a deletion across a line break", () => {
    expect(swallowBeforeCaret("one\n- two", "two", 3).doc.toString()).toBe("onetwo");
  });

  it("deleting only indentation", () => {
    expect(swallowBeforeCaret("    - item", "-", 4, "delete.backward").doc.toString()).toBe("- item");
  });

  it("a programmatic change, cut, word deletion, undo", () => {
    for (const userEvent of [undefined, "delete.cut", "delete.group.backward", "undo"]) {
      const state = stateAt("- [ ] buy", "buy");
      const spec: TransactionSpec = userEvent ? { changes: { from: 0, to: 6 }, userEvent } : { changes: { from: 0, to: 6 } };
      expect(state.update(spec).state.doc.toString()).toBe("buy");
    }
  });
});
