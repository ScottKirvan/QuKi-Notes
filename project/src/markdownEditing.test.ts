import { describe, expect, it } from "vitest";
import { EditorSelection, EditorState } from "@codemirror/state";
import { insertNewlineContinueMarkup } from "@codemirror/lang-markdown";
import { markdownEditing } from "./markdownEditing";

function enterAtEnd(doc: string): string {
  const state = EditorState.create({
    doc,
    selection: EditorSelection.cursor(doc.length),
    extensions: [markdownEditing()],
  });
  let result: string | null = null;
  const handled = insertNewlineContinueMarkup({
    state,
    dispatch: (tr) => {
      result = tr.state.doc.toString();
    },
  });
  expect(handled).toBe(true);
  return result!;
}

describe("Enter at the end of a list item (BEHAVIOR_SPEC.md §4 list auto-continue)", () => {
  it("continues an indented task at the same tab indentation, not four spaces", () => {
    expect(enterAtEnd("- [ ] top\n\t- [ ] a")).toBe("- [ ] top\n\t- [ ] a\n\t- [ ] ");
  });

  it("continues a checked indented task as an unchecked one at the same indentation", () => {
    expect(enterAtEnd("- [ ] top\n\t- [x] a")).toBe("- [ ] top\n\t- [x] a\n\t- [ ] ");
  });

  it("continues an indented bullet at the same tab indentation", () => {
    expect(enterAtEnd("- top\n\t- a")).toBe("- top\n\t- a\n\t- ");
  });

  it("continues an indented numbered item at the same tab indentation", () => {
    expect(enterAtEnd("1. top\n\t1. a")).toBe("1. top\n\t1. a\n\t2. ");
  });

  it("continues a task two levels deep at the same two tabs", () => {
    expect(enterAtEnd("- [ ] top\n\t- [ ] a\n\t\t- [ ] b")).toBe("- [ ] top\n\t- [ ] a\n\t\t- [ ] b\n\t\t- [ ] ");
  });

  it("keeps space indentation as spaces", () => {
    expect(enterAtEnd("- [ ] top\n  - [ ] a")).toBe("- [ ] top\n  - [ ] a\n  - [ ] ");
  });

  it("still continues a top-level task with no indentation", () => {
    expect(enterAtEnd("- [ ] a")).toBe("- [ ] a\n- [ ] ");
  });

  it("still ends an indented list when Enter is pressed on its empty item", () => {
    expect(enterAtEnd("- [ ] top\n\t- [ ] ")).toBe("- [ ] top\n- [ ] ");
  });

  it("still ends a top-level list when Enter is pressed on its empty item", () => {
    expect(enterAtEnd("- [ ] a\n- [ ] b\n- [ ] ")).toBe("- [ ] a\n- [ ] b\n");
  });
});
