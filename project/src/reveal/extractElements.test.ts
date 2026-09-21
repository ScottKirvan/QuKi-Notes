import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { extractElements } from "./extractElements";
import type { RevealElement } from "./types";

function elementsFor(doc: string): RevealElement[] {
  const state = EditorState.create({
    doc,
    extensions: [markdown({ extensions: GFM })],
  });
  return extractElements(state).elements;
}

const LIST_TYPES = new Set(["BulletItem", "OrderedItem"]);

function listElements(doc: string): RevealElement[] {
  return elementsFor(doc).filter((el) => LIST_TYPES.has(el.type));
}

describe("unordered list items", () => {
  it.each(["-", "*", "+"])("given a %s item, then its marker span is the marker plus its space", (bullet) => {
    const [item] = listElements(`${bullet} apple`);
    expect(item.type).toBe("BulletItem");
    expect(item.category).toBe("block-marker");
    expect(item.checkStart).toBe(0);
    expect(item.checkEnd).toBe(2);
    expect(item.start).toBe(0);
    expect(item.end).toBe(7);
  });

  it("given an empty item that has only its marker and space, then it is still an item", () => {
    const [item] = listElements("- ");
    expect(item.type).toBe("BulletItem");
    expect(item.checkEnd).toBe(2);
  });

  it("given a marker with no space after it, then it is not an item", () => {
    expect(listElements("-")).toEqual([]);
    expect(listElements("-apple")).toEqual([]);
  });

  it("given an item indented with a tab under a parent item, then the tab is not part of the marker span", () => {
    const nested = listElements("- top\n\t- apple")[1];
    expect(nested.checkStart).toBe(7);
    expect(nested.checkEnd).toBe(9);
  });

  it("given an item indented with spaces under a parent item, then the spaces are not part of the marker span", () => {
    const nested = listElements("- top\n  - apple")[1];
    expect(nested.checkStart).toBe(8);
    expect(nested.checkEnd).toBe(10);
  });

  it("given a list item on each line, then each line gets its own element", () => {
    const items = listElements("- a\n- b\n- c");
    expect(items.map((el) => [el.checkStart, el.checkEnd])).toEqual([
      [0, 2],
      [4, 6],
      [8, 10],
    ]);
  });

  it("given a line with something other than whitespace before the marker, then it is not an item", () => {
    const items = listElements("> - quoted\n- - both");
    expect(items.map((el) => el.checkStart)).toEqual([11]);
  });
});

describe("ordered list items", () => {
  it("given 1. item, then the marker span covers the digits, the dot and the space", () => {
    const [item] = listElements("1. first");
    expect(item.type).toBe("OrderedItem");
    expect(item.checkStart).toBe(0);
    expect(item.checkEnd).toBe(3);
  });

  it("given a two-digit marker, then the span grows with the digits", () => {
    const [item] = listElements("12. twelfth");
    expect(item.checkEnd).toBe(4);
    expect(item.orderedNumber).toBe(12);
  });

  it("given a marker with no space after the dot, then it is not an item", () => {
    expect(listElements("1.")).toEqual([]);
  });

  it("given a parenthesis marker, then it is not an item", () => {
    expect(listElements("1) first")).toEqual([]);
  });

  it("given 1. 1. 1., then the numbers are 1, 2, 3 and the source digits are untouched", () => {
    const doc = "1. a\n1. b\n1. c";
    expect(listElements(doc).map((el) => el.orderedNumber)).toEqual([1, 2, 3]);
    expect(doc).toBe("1. a\n1. b\n1. c");
  });

  it("given a run starting at 5., then the numbers are 5, 6, 7", () => {
    expect(listElements("5. a\n1. b\n1. c").map((el) => el.orderedNumber)).toEqual([5, 6, 7]);
  });

  it("given a plain line between two items, then the second run keeps its own digit", () => {
    expect(listElements("1. a\nplain\n7. b").map((el) => el.orderedNumber)).toEqual([1, 7]);
  });

  it("given a blank line between two items, then the second run keeps its own digit", () => {
    expect(listElements("1. a\n\n1. b").map((el) => el.orderedNumber)).toEqual([1, 1]);
  });

  it("given a nested ordered run under an item, then the parent resumes its own count afterwards", () => {
    const doc = "1. a\n\t1. b\n\t1. c\n1. d";
    expect(listElements(doc).map((el) => el.orderedNumber)).toEqual([1, 1, 2, 2]);
  });

  it("given an unordered item between two ordered items at the same depth, then the numbering restarts", () => {
    expect(listElements("1. a\n- b\n1. c").filter((el) => el.type === "OrderedItem").map((el) => el.orderedNumber)).toEqual([1, 1]);
  });
});

function quoteElements(doc: string): RevealElement[] {
  return elementsFor(doc).filter((el) => el.type === "BlockquoteLine");
}

describe("blockquote lines", () => {
  it("given > quoted, then the marker span is the > and its one space", () => {
    const [quote] = quoteElements("> quoted");
    expect(quote.category).toBe("block-marker");
    expect(quote.start).toBe(0);
    expect(quote.end).toBe(8);
    expect(quote.checkStart).toBe(0);
    expect(quote.checkEnd).toBe(2);
    expect(quote.quoteDepth).toBe(1);
  });

  it("given >quoted with no space, then the marker span is only the >", () => {
    const [quote] = quoteElements(">quoted");
    expect(quote.checkEnd).toBe(1);
  });

  it("given a bare >, then it is still a quote line with a one-character marker", () => {
    const [quote] = quoteElements(">");
    expect(quote.checkStart).toBe(0);
    expect(quote.checkEnd).toBe(1);
  });

  it("given nested markers, then the depth counts every > and the span covers them all", () => {
    const [spaced] = quoteElements("> > deep");
    expect(spaced.quoteDepth).toBe(2);
    expect(spaced.checkEnd).toBe(4);

    const [tight] = quoteElements(">> deep");
    expect(tight.quoteDepth).toBe(2);
    expect(tight.checkEnd).toBe(3);
  });

  it("given a quote spanning several lines, then each line has its own element", () => {
    const quotes = quoteElements("> a\n> b\n>\n> c");
    expect(quotes.map((q) => [q.start, q.checkEnd])).toEqual([
      [0, 2],
      [4, 6],
      [8, 9],
      [10, 12],
    ]);
  });

  it("given a lazy continuation line with no >, then that line is not a quote line", () => {
    const quotes = quoteElements("> a\nlazy");
    expect(quotes).toHaveLength(1);
  });

  it("given a > that is not at the start of the line, then it is not a quote line", () => {
    expect(quoteElements(" > x")).toEqual([]);
    expect(quoteElements("- > x")).toEqual([]);
    expect(quoteElements("a > b")).toEqual([]);
  });

  it("given a > inside a fenced code block, then it is not a quote line", () => {
    expect(quoteElements("```\n> not a quote\n```")).toEqual([]);
  });
});
