import { describe, expect, it } from "vitest";
import { EditorSelection, EditorState, type Transaction } from "@codemirror/state";
import { ensureSyntaxTree } from "@codemirror/language";
import { keymap } from "@codemirror/view";
import { defaultKeymap } from "@codemirror/commands";
import { markdownEditing } from "./markdownEditing";
import { buildDecorations } from "./reveal/decorations";
import { plainTextMode } from "./reveal/plainTextMode";

function stateFor(doc: string, caret = doc.length): EditorState {
  const state = EditorState.create({
    doc,
    selection: EditorSelection.cursor(caret),
    extensions: [keymap.of(defaultKeymap), markdownEditing(), plainTextMode],
  });
  ensureSyntaxTree(state, doc.length, 5000);
  return state;
}

interface Drawn {
  from: number;
  to: number;
  widget: string | null;
  cls: string | null;
  style: string | null;
}

// Decorations with the caret on a line of its own at the end, so nothing
// under test is revealed.
function drawn(doc: string): Drawn[] {
  const full = `${doc}\n\nend`;
  const out: Drawn[] = [];
  buildDecorations(stateFor(full)).between(0, full.length, (from, to, value) => {
    const spec = value.spec as { widget?: object; class?: string; attributes?: { style?: string } };
    out.push({
      from,
      to,
      widget: spec.widget ? spec.widget.constructor.name : null,
      cls: spec.class ?? null,
      style: spec.attributes?.style ?? null,
    });
  });
  return out;
}

function markers(doc: string): [string, number, number][] {
  return drawn(doc)
    .filter((d) => d.widget !== null)
    .map((d) => [d.widget!, d.from, d.to]);
}

function listLineStyle(doc: string, lineFrom: number): string | null {
  return drawn(doc).find((d) => d.cls === "cm-quki-list-line" && d.from === lineFrom)?.style ?? null;
}

// CodeMirror's 6px line inset + 16px per depth + the 24px marker gutter.
function depthStyle(depth: number): string {
  return `padding-left:${6 + depth * 16 + 24}px;text-indent:-24px`;
}

function enterAtEnd(doc: string): string {
  const state = stateFor(doc);
  let next: EditorState | null = null;
  const target = { state, dispatch: (tr: Transaction) => (next = tr.state) };
  for (const bindings of state.facet(keymap)) {
    for (const binding of bindings) {
      if (binding.key !== "Enter" || !binding.run) continue;
      if (binding.run(target as never)) return (next ?? state).doc.toString();
    }
  }
  throw new Error("nothing handled Enter");
}

describe("a tab-indented list item where CommonMark would see code or paragraph text", () => {
  it.each([
    ["on the first line", "\t- item", 0],
    ["right after a paragraph", "text\n\t- item", 5],
    ["right after a heading", "# Head\n\t- item", 7],
    ["after a blank line", "text\n\n\t- item", 6],
  ])("given a bullet %s, when rendered, then it is a bullet at depth 1", (_where, doc, lineFrom) => {
    expect(markers(doc)).toContainEqual(["BulletWidget", lineFrom, lineFrom + 3]);
    expect(listLineStyle(doc, lineFrom)).toBe(depthStyle(1));
  });

  it("given a task on the first line, when rendered, then it is a checkbox at depth 1", () => {
    expect(markers("\t- [ ] task")).toContainEqual(["CheckboxWidget", 0, 7]);
    expect(listLineStyle("\t- [ ] task", 0)).toBe(depthStyle(1));
  });

  it("given a numbered item on the first line, when rendered, then it is a number at depth 1", () => {
    expect(markers("\t1. one")).toContainEqual(["OrderedMarkerWidget", 0, 4]);
  });

  it("given an item two tabs deep on the first line, when rendered, then it is at depth 2", () => {
    expect(listLineStyle("\t\t- item", 0)).toBe(depthStyle(2));
  });

  it("given an item two levels under its parent, when rendered, then it is a bullet at depth 2", () => {
    const doc = "- a\n\t\t- c";
    expect(markers(doc)).toEqual([
      ["BulletWidget", 0, 2],
      ["BulletWidget", 4, 8],
    ]);
    expect(listLineStyle(doc, 4)).toBe(depthStyle(2));
  });

  it("given consecutive tab-indented items on the first lines, when rendered, then every one is a bullet", () => {
    const doc = "\t- a\n\t- b\n\t\t- c";
    expect(markers(doc).map(([, from]) => from)).toEqual([0, 5, 10]);
  });

  it("given four spaces before the marker on the first line, when rendered, then it is a bullet too", () => {
    expect(markers("    - item")).toContainEqual(["BulletWidget", 0, 6]);
  });
});

describe("what stays as it was", () => {
  it("given an indented line that is not a list item, when rendered, then nothing is drawn for it", () => {
    expect(markers("\tplain text")).toEqual([]);
  });

  it("given an indented marker inside a fenced code block, when rendered, then it stays code", () => {
    const decos = drawn("```\n\t- x\n```");
    expect(decos.filter((d) => d.widget !== null)).toEqual([]);
    expect(decos.filter((d) => d.cls === "cm-quki-codeblock-line")).toHaveLength(3);
  });

  it("given an empty indented marker right after a paragraph, then it is paragraph text, as an unindented one is", () => {
    expect(markers("text\n\t- ")).toEqual([]);
    expect(markers("text\n- ")).toEqual([]);
  });

  it("given an indented horizontal rule, when rendered, then it is not a bullet", () => {
    expect(markers("\t- - -")).toEqual([]);
  });

  it("given a table followed by an indented item, when rendered, then the table still renders", () => {
    expect(markers("| a |\n| - |\n| 1 |\n\n\t- item").map(([w]) => w)).toEqual(["TableWidget", "BulletWidget"]);
  });
});

describe("Enter on a tab-indented list item where CommonMark would see code or paragraph text", () => {
  it.each([
    ["a bullet on the first line", "\t- item", "\t- item\n\t- "],
    ["a bullet after a paragraph", "text\n\t- item", "text\n\t- item\n\t- "],
    ["a task on the first line", "\t- [ ] a", "\t- [ ] a\n\t- [ ] "],
    ["a numbered item on the first line", "\t1. a", "\t1. a\n\t2. "],
    ["a bullet two tabs deep on the first line", "\t\t- a", "\t\t- a\n\t\t- "],
    ["an item two levels under its parent", "- a\n\t\t- c", "- a\n\t\t- c\n\t\t- "],
    ["a second consecutive item", "\t- a\n\t- b", "\t- a\n\t- b\n\t- "],
  ])("continues %s at the same indentation", (_name, doc, expected) => {
    expect(enterAtEnd(doc)).toBe(expected);
  });

  it("continues a child of a tab-indented item at the child's indentation", () => {
    expect(enterAtEnd("\t- a\n\t\t- b")).toBe("\t- a\n\t\t- b\n\t\t- ");
  });

  it("ends the list on an empty tab-indented item with no parent item", () => {
    expect(enterAtEnd("\t- a\n\t- ")).toBe("\t- a\n");
  });
});
