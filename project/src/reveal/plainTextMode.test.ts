import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { describe, expect, it } from "vitest";

import { PLAIN_TEXT_CLASS, plainTextMode, setPlainTextMode } from "./plainTextMode";

function editorClasses(state: EditorState): string[] {
  return state
    .facet(EditorView.editorAttributes)
    .flatMap((attrs) => (attrs as { class?: string }).class?.split(" ") ?? []);
}

describe("plainTextMode's editor class", () => {
  it("is absent until plain-text mode is switched on", () => {
    const state = EditorState.create({ doc: "x", extensions: [plainTextMode] });
    expect(editorClasses(state)).not.toContain(PLAIN_TEXT_CLASS);
  });

  it("is on the editor while plain-text mode is on, and gone again when it is switched off", () => {
    const initial = EditorState.create({ doc: "x", extensions: [plainTextMode] });
    const on = initial.update({ effects: setPlainTextMode.of(true) }).state;
    expect(editorClasses(on)).toContain(PLAIN_TEXT_CLASS);
    const off = on.update({ effects: setPlainTextMode.of(false) }).state;
    expect(editorClasses(off)).not.toContain(PLAIN_TEXT_CLASS);
  });
});
