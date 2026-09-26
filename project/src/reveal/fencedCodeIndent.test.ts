import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { getIndentation } from "@codemirror/language";
import { fencedCodeNoIndent } from "./fencedCodeIndent";

function indentAt(doc: string, pos: number): number | null {
  const state = EditorState.create({
    doc,
    extensions: [markdown({ extensions: GFM }), fencedCodeNoIndent],
  });
  return getIndentation(state, pos);
}

function indentAtWithoutFix(doc: string, pos: number): number | null {
  const state = EditorState.create({
    doc,
    extensions: [markdown({ extensions: GFM })],
  });
  return getIndentation(state, pos);
}

describe("fenced code blocks get no synthetic indentation", () => {
  it("given a position on an indented content line, when queried without the fix, then CodeMirror's own fallback would inherit that line's indentation (demonstrating the bug this fixes)", () => {
    const doc = "```\n  return bar++;\n```";
    const pos = doc.indexOf("return");
    expect(indentAtWithoutFix(doc, pos)).toBeNull();
  });

  it("given the same position, when queried with the fix installed, then indentation is exactly zero", () => {
    const doc = "```\n  return bar++;\n```";
    const pos = doc.indexOf("return");
    expect(indentAt(doc, pos)).toBe(0);
  });

  it("given a position on the opening fence line itself, then indentation is zero", () => {
    const doc = "```js\nvar x = 1;\n```";
    expect(indentAt(doc, 1)).toBe(0);
  });

  it("given a position on the closing fence line, then indentation is zero", () => {
    const doc = "```\ncode\n```";
    const pos = doc.lastIndexOf("```");
    expect(indentAt(doc, pos)).toBe(0);
  });

  it("given a position at the very start of the first content line (the boundary right after the opening fence's newline), then indentation is still zero", () => {
    const doc = "```\ncode\n```";
    const pos = doc.indexOf("\n") + 1;
    expect(indentAt(doc, pos)).toBe(0);
  });

  it("given a tilde-fenced block, then indentation inside it is also zero", () => {
    const doc = "~~~\n  deeply(nested(calls()));\n~~~";
    const pos = doc.indexOf("deeply");
    expect(indentAt(doc, pos)).toBe(0);
  });

  it("given a position inside a nested-brace line, then indentation is zero regardless of how deep the code itself is nested", () => {
    const doc = "```\nfunction f() {\n  if (true) {\n    while (true) {\n      x();\n```";
    const pos = doc.indexOf("x();");
    expect(indentAt(doc, pos)).toBe(0);
  });

  it("given a position outside any fenced block, then the fix defers and does not override markdown's own indentation", () => {
    const doc = "plain paragraph text";
    const pos = doc.indexOf("paragraph");
    expect(indentAt(doc, pos)).toBe(indentAtWithoutFix(doc, pos));
  });

  it("given a position inside a nested list item (not a fenced block), then the fix does not interfere with list indentation", () => {
    const doc = "- top\n  - nested item text";
    const pos = doc.indexOf("item");
    expect(indentAt(doc, pos)).toBe(indentAtWithoutFix(doc, pos));
  });
});
