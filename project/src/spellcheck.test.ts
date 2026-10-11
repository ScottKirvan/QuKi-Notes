import { ensureSyntaxTree } from "@codemirror/language";
import { EditorState } from "@codemirror/state";
import type { Decoration } from "@codemirror/view";
import { describe, expect, it } from "vitest";

import { markdownEditing } from "./markdownEditing";
import { codeSpellcheckExclusions } from "./spellcheck";

interface Found {
  kind: "mark" | "line";
  text: string;
}

function exclusions(doc: string): Found[] {
  const state = EditorState.create({ doc, extensions: [markdownEditing()] });
  ensureSyntaxTree(state, state.doc.length, 5000);
  const found: Found[] = [];
  codeSpellcheckExclusions(state).between(0, state.doc.length, (from, to, value: Decoration) => {
    const spec = value.spec as { attributes?: Record<string, string> };
    expect(spec.attributes?.spellcheck).toBe("false");
    found.push(from === to ? { kind: "line", text: state.doc.lineAt(from).text } : { kind: "mark", text: state.sliceDoc(from, to) });
  });
  return found;
}

describe("codeSpellcheckExclusions", () => {
  it("excludes nothing from plain prose", () => {
    expect(exclusions("Teh prose line\n\nanother linne")).toEqual([]);
  });

  it("excludes an inline code span, backticks included", () => {
    expect(exclusions("Some `inlinecodde` here")).toEqual([{ kind: "mark", text: "`inlinecodde`" }]);
  });

  it("excludes every line of a fenced code block, fences included", () => {
    expect(exclusions("before\n```js\nfencedd codde\nmore\n```\nafter")).toEqual([
      { kind: "line", text: "```js" },
      { kind: "line", text: "fencedd codde" },
      { kind: "line", text: "more" },
      { kind: "line", text: "```" },
    ]);
  });

  it("excludes an unclosed fenced block through the end of the document", () => {
    expect(exclusions("```\nopen codde").map((f) => f.text)).toEqual(["```", "open codde"]);
  });
});
