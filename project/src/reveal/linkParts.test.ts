import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { ensureSyntaxTree } from "@codemirror/language";
import type { SyntaxNode } from "@lezer/common";
import { linkParts } from "./linkParts";

function partsFor(doc: string, type: "Link" | "Image"): { label: string; destination: string | null } {
  const state = EditorState.create({ doc, extensions: [markdown({ extensions: GFM })] });
  let found: SyntaxNode | null = null;
  ensureSyntaxTree(state, doc.length, 5000)!.iterate({
    enter(node) {
      if (found === null && node.name === type) found = node.node;
    },
  });
  if (!found) throw new Error(`no ${type} parsed from: ${doc}`);
  const { labelFrom, labelTo, destination } = linkParts(found);
  return {
    label: state.sliceDoc(labelFrom, labelTo),
    destination: destination ? state.sliceDoc(destination.from, destination.to) : null,
  };
}

describe("linkParts", () => {
  it("given a plain link, then the label and destination are its own", () => {
    expect(partsFor("[text](https://example.com)", "Link")).toEqual({
      label: "text",
      destination: "https://example.com",
    });
  });

  it("given a URL in the label, then the destination is still the link's own target", () => {
    expect(partsFor("[see http://example.com more](https://real.example.org)", "Link")).toEqual({
      label: "see http://example.com more",
      destination: "https://real.example.org",
    });
  });

  it("given a URL in an image's alt text, then the destination is the image's own source", () => {
    expect(partsFor("![from www.example.com](pic.png)", "Image")).toEqual({
      label: "from www.example.com",
      destination: "pic.png",
    });
  });

  it("given a link with a title, then the destination excludes the title", () => {
    expect(partsFor('[x](https://real.example.org "see http://t.example")', "Link").destination).toBe(
      "https://real.example.org",
    );
  });

  it("given a reference link whose label holds a URL, then there is no destination", () => {
    expect(partsFor("[see http://example.com][ref]\n\n[ref]: https://real.example.org", "Link").destination).toBeNull();
  });
});
