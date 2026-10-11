import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { calloutTypeOf } from "./callout";
import { extractElements } from "./extractElements";
import type { RevealElement } from "./types";

function quoteElements(doc: string): RevealElement[] {
  const state = EditorState.create({ doc, extensions: [markdown({ extensions: GFM })] });
  return extractElements(state).elements.filter(
    (el) => el.type === "BlockquoteLine" || el.type === "CalloutTitle",
  );
}

describe("calloutTypeOf", () => {
  it.each([
    ["> [!NOTE]", "note"],
    ["> [!TIP]", "tip"],
    ["> [!IMPORTANT]", "important"],
    ["> [!WARNING]", "warning"],
    ["> [!CAUTION]", "caution"],
  ])("given %s, then the type is %s", (line, type) => {
    expect(calloutTypeOf(line)).toBe(type);
  });

  it.each(["> [!note]", "> [!Note]", "> [!nOtE]"])("given %s, then case is ignored", (line) => {
    expect(calloutTypeOf(line)).toBe("note");
  });

  it("given no space after the quote marker, then it is still a callout", () => {
    expect(calloutTypeOf(">[!TIP]")).toBe("tip");
  });

  it("given trailing whitespace after the marker, then it is still a callout", () => {
    expect(calloutTypeOf("> [!TIP]  ")).toBe("tip");
  });

  it.each(["> [!FOO]", "> [!INFO]", "> [!]", "> [NOTE]", "> [!NOTE", "> !NOTE"])(
    "given the unknown or malformed marker %s, then it is not a callout",
    (line) => {
      expect(calloutTypeOf(line)).toBeNull();
    },
  );

  it("given text after the marker on the same line, then it is not a callout", () => {
    expect(calloutTypeOf("> [!NOTE] hello")).toBeNull();
  });

  it("given a nested quote marker, then it is not a callout", () => {
    expect(calloutTypeOf("> > [!NOTE]")).toBeNull();
  });

  it("given a line that is not a quote, then it is not a callout", () => {
    expect(calloutTypeOf("[!NOTE]")).toBeNull();
  });
});

describe("callout extraction", () => {
  it("given a callout, then its first line is a CalloutTitle whose marker span is the whole line", () => {
    const [title] = quoteElements("> [!WARNING]\n> Careful");
    expect(title).toEqual(
      expect.objectContaining({
        type: "CalloutTitle",
        calloutType: "warning",
        start: 0,
        end: 12,
        checkStart: 0,
        checkEnd: 12,
        quoteDepth: 1,
      }),
    );
  });

  it("given a callout, then its body lines are quote lines carrying the callout type", () => {
    const [, body] = quoteElements("> [!WARNING]\n> Careful");
    expect(body).toEqual(
      expect.objectContaining({ type: "BlockquoteLine", calloutType: "warning", checkStart: 13, checkEnd: 15 }),
    );
  });

  it("given a callout, then its [!TYPE] marker is not also a link", () => {
    const state = EditorState.create({ doc: "> [!NOTE]\n> x", extensions: [markdown({ extensions: GFM })] });
    expect(extractElements(state).elements.filter((el) => el.type === "Link")).toEqual([]);
  });

  it("given an unknown type, then the quote stays an ordinary quote and [!FOO] stays a link", () => {
    const state = EditorState.create({ doc: "> [!FOO]\n> x", extensions: [markdown({ extensions: GFM })] });
    const { elements } = extractElements(state);
    expect(elements.filter((el) => el.type === "CalloutTitle")).toEqual([]);
    expect(elements.filter((el) => el.calloutType !== undefined)).toEqual([]);
    expect(elements.filter((el) => el.type === "Link")).toHaveLength(1);
  });

  it("given the marker on a quote's second line, then it is not a callout", () => {
    const elements = quoteElements("> first\n> [!NOTE]");
    expect(elements.map((el) => el.type)).toEqual(["BlockquoteLine", "BlockquoteLine"]);
    expect(elements.every((el) => el.calloutType === undefined)).toBe(true);
  });

  it("given a callout marker inside a list item, then it is not a callout", () => {
    expect(quoteElements("- > [!NOTE]\n  > x").every((el) => el.type !== "CalloutTitle")).toBe(true);
  });

  it("given a callout marker in a nested quote, then it is not a callout", () => {
    const elements = quoteElements("> > [!NOTE]\n> > x");
    expect(elements.every((el) => el.type === "BlockquoteLine" && el.calloutType === undefined)).toBe(true);
  });

  it("given a callout followed by a separate quote, then only the callout's lines carry its type", () => {
    const elements = quoteElements("> [!TIP]\n> a\n\n> plain");
    expect(elements.map((el) => el.calloutType)).toEqual(["tip", "tip", undefined]);
  });

  it("given a list, code and emphasis inside a callout, then they are still extracted", () => {
    const state = EditorState.create({
      doc: "> [!NOTE]\n> *em*\n> - item\n> ```\n> code\n> ```",
      extensions: [markdown({ extensions: GFM })],
    });
    const types = extractElements(state).elements.map((el) => el.type);
    expect(types).toContain("Emphasis");
    expect(types).toContain("FencedCode");
    expect(quoteElements("> [!NOTE]\n> *em*\n> - item\n> ```\n> code\n> ```").map((el) => el.calloutType)).toEqual(
      Array(6).fill("note"),
    );
  });
});
