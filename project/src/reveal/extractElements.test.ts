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

  it("given an item indented with a tab under a parent item, then the marker span starts at the tab", () => {
    const nested = listElements("- top\n\t- apple")[1];
    expect(nested.start).toBe(6);
    expect(nested.checkStart).toBe(6);
    expect(nested.checkEnd).toBe(9);
  });

  it("given an item indented with spaces under a parent item, then the marker span starts at the first space", () => {
    const nested = listElements("- top\n  - apple")[1];
    expect(nested.start).toBe(6);
    expect(nested.checkStart).toBe(6);
    expect(nested.checkEnd).toBe(10);
  });

  it("given an ordered item indented under a parent item, then the marker span starts at its indentation", () => {
    const nested = listElements("1. top\n   1. apple")[1];
    expect(nested.start).toBe(7);
    expect(nested.checkStart).toBe(7);
    expect(nested.checkEnd).toBe(7 + 3 + 3);
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

function taskElements(doc: string): RevealElement[] {
  return elementsFor(doc).filter((el) => el.type === "TaskItem");
}

describe("task items", () => {
  it("given - [ ] item, then it is one task element whose marker span is all six characters", () => {
    const els = elementsFor("- [ ] buy milk");
    expect(els.map((el) => el.type)).toEqual(["TaskItem"]);
    const [task] = els;
    expect(task.category).toBe("block-marker");
    expect(task.checkStart).toBe(0);
    expect(task.checkEnd).toBe(6);
    expect(task.start).toBe(0);
    expect(task.end).toBe(14);
    expect(task.checked).toBe(false);
  });

  it.each(["x", "X"])("given - [%s] item, then it is a checked task", (mark) => {
    const [task] = taskElements(`- [${mark}] done`);
    expect(task.checked).toBe(true);
    expect(task.checkEnd).toBe(6);
  });

  it("given an empty task item, then it is still a task", () => {
    const [task] = taskElements("- [ ] ");
    expect(task.checkEnd).toBe(6);
  });

  it("given a task, then it is never also extracted as a plain unordered item", () => {
    const types = elementsFor("- [ ] a\n- [x] b\n- c").map((el) => el.type);
    expect(types).toEqual(["TaskItem", "TaskItem", "BulletItem"]);
  });

  it("given a nested task, then the marker span starts at its indentation", () => {
    const [, nested] = taskElements("- [ ] top\n\t- [x] nested");
    expect(nested.start).toBe(10);
    expect(nested.checkStart).toBe(10);
    expect(nested.checkEnd).toBe(17);
    expect(nested.checked).toBe(true);
  });

  it.each(["* [ ] x", "+ [x] x"])("given %j, then it is a plain unordered item, not a task", (line) => {
    expect(taskElements(line)).toEqual([]);
    expect(listElements(line).map((el) => el.type)).toEqual(["BulletItem"]);
  });

  it("given an ordered item with a checkbox-looking start, then it is an ordered item, not a task", () => {
    expect(taskElements("1. [ ] x")).toEqual([]);
    expect(listElements("1. [ ] x").map((el) => el.type)).toEqual(["OrderedItem"]);
  });

  it("given - [ ] with no space after the bracket, then it is a plain unordered item", () => {
    expect(taskElements("- [ ]")).toEqual([]);
  });

  it("given two spaces before the bracket, then it is not a task", () => {
    expect(taskElements("-  [ ] x")).toEqual([]);
  });
});

describe("bare autolinks", () => {
  function urlElements(doc: string): RevealElement[] {
    return elementsFor(doc).filter((el) => el.type === "URL");
  }

  it("given a bare http(s) URL, then it is an inline element spanning the matched text", () => {
    const doc = "visit http://example.com now";
    const [el] = urlElements(doc);
    expect(el.category).toBe("inline");
    expect(el.checkStart).toBe(6);
    expect(el.checkEnd).toBe(24);
    expect(el.start).toBe(6);
    expect(el.end).toBe(24);
    expect(el.parentId).toBeNull();
  });

  it("given a bare www. URL, then it is still one URL element over just the matched text", () => {
    const doc = "visit www.example.com now";
    const [el] = urlElements(doc);
    expect(el.start).toBe(6);
    expect(el.end).toBe(21);
  });

  it("given a bare email address, then it is a URL element", () => {
    const [el] = urlElements("email me foo@bar.com please");
    expect(el.start).toBe(9);
    expect(el.end).toBe(20);
  });

  it("given mailto: and xmpp: autolinks, then each is its own URL element", () => {
    const els = urlElements("mailto:foo@bar.com and xmpp:foo@bar.com/res");
    expect(els).toHaveLength(2);
  });

  it("given an autolink nested inside emphasis, then its parent is the emphasis element", () => {
    const doc = "cursor http://x.com inside **bold http://y.com text**";
    const els = elementsFor(doc);
    const bold = els.find((el) => el.type === "StrongEmphasis");
    const [outer, inner] = els.filter((el) => el.type === "URL");
    expect(outer.parentId).toBeNull();
    expect(inner.parentId).toBe(bold?.id);
  });

  it("given a bracketed link whose label contains what looks like a bare URL, then no separate URL element is extracted for it", () => {
    const doc = "[see https://example.com here](http://target.com)";
    expect(urlElements(doc)).toEqual([]);
    expect(elementsFor(doc).map((el) => el.type)).toEqual(["Link"]);
  });

  it("given an image whose alt text and destination look like bare URLs, then no separate URL element is extracted for either", () => {
    const doc = "![alt http://img.com](http://dest.com)";
    expect(urlElements(doc)).toEqual([]);
  });
});

describe("list item indent depth", () => {
  function depthOf(doc: string, line: number): number | undefined {
    const items = elementsFor(doc).filter((el) => ["BulletItem", "OrderedItem", "TaskItem"].includes(el.type));
    return items[line].indentDepth;
  }

  it("given an item with no leading whitespace, then its depth is 0", () => {
    expect(depthOf("- a", 0)).toBe(0);
  });

  it.each([
    ["one tab", "\t", 1],
    ["two spaces", "  ", 1],
    ["four spaces", "    ", 2],
    ["one space", " ", 0],
    ["three spaces", "   ", 1],
  ])("given %s before the marker, then the depth is floor(columns / 2) with a tab counting two", (_name, ws, depth) => {
    expect(depthOf(`- top\n${ws}- x`, 1)).toBe(depth);
  });

  it.each([
    ["two tabs", "\t\t"],
    ["a tab and two spaces", "\t  "],
  ])("given %s before the marker under a nested parent, then the depth is 2", (_name, ws) => {
    expect(depthOf(`- top\n\t- mid\n${ws}- x`, 2)).toBe(2);
  });

  it("given a nested task and a nested ordered item, then each carries its own depth", () => {
    expect(depthOf("- [ ] top\n  - [ ] sub", 1)).toBe(1);
    expect(depthOf("1. top\n    1. sub", 1)).toBe(2);
  });

  it("given a heading, a quote and an image, then none carries an indent depth", () => {
    const els = elementsFor("# h\n\n> q\n\n![a](b.png)");
    expect(els.every((el) => el.indentDepth === undefined)).toBe(true);
  });
});

describe("GFM tables", () => {
  function tableElements(doc: string): RevealElement[] {
    return elementsFor(doc).filter((el) => el.type === "Table");
  }

  it("given a pipe table, then it is one block-marker element spanning the whole table", () => {
    const doc = "| A | B |\n|---|---|\n| 1 | 2 |";
    const [table] = tableElements(doc);
    expect(table.category).toBe("block-marker");
    expect(table.start).toBe(0);
    expect(table.end).toBe(doc.length);
    expect(table.checkStart).toBe(0);
    expect(table.checkEnd).toBe(doc.length);
    expect(table.parentId).toBeNull();
  });

  it("given a table with several rows, then it is still exactly one element for the whole table", () => {
    const doc = "| A |\n|---|\n| 1 |\n| 2 |\n| 3 |";
    expect(tableElements(doc)).toHaveLength(1);
  });

  it("given a table whose cells contain bold, links and code, then no separate inline elements are extracted for them", () => {
    const doc = "| A |\n|---|\n| **bold** [link](https://x.com) `code` |";
    const els = elementsFor(doc);
    expect(els.map((el) => el.type)).toEqual(["Table"]);
  });

  it("given a table beside a heading and a paragraph, then only the table itself becomes a Table element", () => {
    const doc = "# heading\n\nplain text\n\n| A |\n|---|\n| 1 |\n\nmore text";
    const types = elementsFor(doc).map((el) => el.type);
    expect(types.filter((t) => t === "Table")).toEqual(["Table"]);
  });

  it("given text that merely contains a pipe character, then it is not a table", () => {
    expect(tableElements("a | b | c")).toEqual([]);
  });
});
