import { describe, expect, it } from "vitest";
import { EditorSelection, EditorState, type Transaction } from "@codemirror/state";
import { keymap } from "@codemirror/view";
import { defaultKeymap } from "@codemirror/commands";
import { markdownEditing } from "./markdownEditing";

function stateAt(doc: string, caret: number): EditorState {
  return EditorState.create({
    doc,
    selection: EditorSelection.cursor(caret),
    extensions: [keymap.of(defaultKeymap), markdownEditing()],
  });
}

function press(state: EditorState, key: string): EditorState {
  let next: EditorState | null = null;
  const target = {
    state,
    dispatch: (tr: Transaction) => {
      next = tr.state;
    },
  };
  for (const bindings of state.facet(keymap)) {
    for (const binding of bindings) {
      if (binding.key !== key || !binding.run) continue;
      if (binding.run(target as never)) return next ?? state;
    }
  }
  return state;
}

function backspaceSteps(doc: string, caretBefore: string, presses: number): string[] {
  let state = stateAt(doc, doc.indexOf(caretBefore));
  const lines: string[] = [];
  for (let i = 0; i < presses; i++) {
    state = press(state, "Backspace");
    lines.push(state.doc.lineAt(state.selection.main.head).text);
  }
  return lines;
}

describe("Backspace deletes one character at a time in list items and quotes", () => {
  it("steps back through a checkbox marker", () => {
    expect(backspaceSteps("- [ ] buy milk", "buy", 4)).toEqual(["- [ ]buy milk", "- [ buy milk", "- [buy milk", "- buy milk"]);
  });

  it("steps back through a checked checkbox marker", () => {
    expect(backspaceSteps("- [x] done", "done", 2)).toEqual(["- [x]done", "- [xdone"]);
  });

  it("steps back through bullet markers", () => {
    for (const marker of ["-", "*", "+"]) {
      expect(backspaceSteps(`${marker} apple`, "apple", 2)).toEqual([`${marker}apple`, "apple"]);
    }
  });

  it("steps back through numbered markers", () => {
    expect(backspaceSteps("1. one", "one", 3)).toEqual(["1.one", "1one", "one"]);
    expect(backspaceSteps("1) one", "one", 2)).toEqual(["1)one", "1one"]);
  });

  it("steps back through an indented checkbox marker, keeping the indentation", () => {
    const doc = "- parent\n\t- [ ] child";
    expect(backspaceSteps(doc, "child", 3)).toEqual(["\t- [ ]child", "\t- [ child", "\t- [child"]);
  });

  it("steps back through an indented bullet marker with space indentation", () => {
    const doc = "- parent\n  - child";
    expect(backspaceSteps(doc, "child", 2)).toEqual(["  -child", "  child"]);
  });

  it("steps back through quote markers, including nested quotes", () => {
    expect(backspaceSteps("> quoted", "quoted", 2)).toEqual([">quoted", "quoted"]);
    expect(backspaceSteps("> > deeper", "deeper", 3)).toEqual(["> >deeper", "> deeper", ">deeper"]);
  });

  it("steps back through a list inside a quote", () => {
    expect(backspaceSteps("> - [ ] task", "task", 2)).toEqual(["> - [ ]task", "> - [ task"]);
  });

  it("still continues a list on Enter", () => {
    const doc = "- [ ] buy milk";
    const after = press(stateAt(doc, doc.length), "Enter");
    expect(after.doc.toString()).toBe("- [ ] buy milk\n- [ ] ");
  });
});
