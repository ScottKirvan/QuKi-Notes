import { describe, expect, it } from "vitest";
import { EditorSelection, EditorState, type Transaction } from "@codemirror/state";
import { keymap } from "@codemirror/view";
import { defaultKeymap } from "@codemirror/commands";
import { markdownEditing } from "./markdownEditing";

// Enter as main.ts binds it: markdownEditing()'s own Enter first, then
// defaultKeymap's for anything it declines.
function enterAtEnd(doc: string): string {
  const state = EditorState.create({
    doc,
    selection: EditorSelection.cursor(doc.length),
    extensions: [keymap.of(defaultKeymap), markdownEditing()],
  });
  let next: EditorState | null = null;
  const target = {
    state,
    dispatch: (tr: Transaction) => {
      next = tr.state;
    },
  };
  for (const bindings of state.facet(keymap)) {
    for (const binding of bindings) {
      if (binding.key !== "Enter" || !binding.run) continue;
      if (binding.run(target as never)) return (next ?? state).doc.toString();
    }
  }
  throw new Error("nothing handled Enter");
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

describe("Enter on an empty second item ends the list (BEHAVIOR_SPEC.md §4 list auto-continue)", () => {
  it("ends a bullet list instead of adding a blank line above the empty item", () => {
    expect(enterAtEnd("- item\n- ")).toBe("- item\n");
  });

  it("ends a numbered list", () => {
    expect(enterAtEnd("1. item\n2. ")).toBe("1. item\n");
  });

  it("ends a task list", () => {
    expect(enterAtEnd("- [ ] item\n- [ ] ")).toBe("- [ ] item\n");
  });

  it("dedents an empty second indented item one level, as for any empty indented item", () => {
    expect(enterAtEnd("- a\n\t- b\n\t- ")).toBe("- a\n\t- b\n- ");
  });

  it("ends a list that follows a paragraph", () => {
    expect(enterAtEnd("text\n- item\n- ")).toBe("text\n- item\n");
  });
});
