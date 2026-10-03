import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { extractElements } from "./extractElements";
import { computeRevealedIds, caretForReveal } from "./computeReveal";
import type { RevealElement } from "./types";

function elementsFor(doc: string): RevealElement[] {
  const state = EditorState.create({
    doc,
    extensions: [markdown({ extensions: GFM })],
  });
  return extractElements(state).elements;
}

function typesRevealed(elements: RevealElement[], caret: number | null) {
  const ids = computeRevealedIds(elements, caret);
  return elements.filter((el) => ids.has(el.id)).map((el) => el.type);
}

describe("rule 1/2 — outermost element reveals, never the innermost", () => {
  const doc = "**bold *italic* text**";
  // offsets: 0123456789...
  // "**bold *italic* text**"
  //  0         1         2
  //  0123456789012345678901

  it("caret inside the inner emphasis reveals the whole outer StrongEmphasis, not just Emphasis", () => {
    const elements = elementsFor(doc);
    const strong = elements.find((el) => el.type === "StrongEmphasis")!;
    const emphasis = elements.find((el) => el.type === "Emphasis")!;
    expect(strong).toBeTruthy();
    expect(emphasis).toBeTruthy();

    // A caret strictly inside "*italic*" (inside the word "italic").
    const caretInsideInner = doc.indexOf("italic") + 2;
    expect(caretInsideInner).toBeGreaterThan(emphasis.start);
    expect(caretInsideInner).toBeLessThan(emphasis.end);

    const revealed = computeRevealedIds(elements, caretInsideInner);

    expect(revealed.has(strong.id)).toBe(true);
    // The inner element is absorbed into the outer reveal (its raw text is
    // part of the outer span already shown), not "independently revealed",
    // but it must never be revealed while the outer stays collapsed.
    expect(revealed.has(emphasis.id)).toBe(true);
  });

  it("caret outside both elements collapses both", () => {
    const elements = elementsFor(`${doc} plain text here`);
    const caretFarAway = doc.length + 10;
    const revealed = typesRevealed(elements, caretFarAway);
    expect(revealed).toEqual([]);
  });

  it("caret between the outer delimiter and the inner element reveals the outer only (inner absorbed)", () => {
    const elements = elementsFor(doc);
    const strong = elements.find((el) => el.type === "StrongEmphasis")!;
    const emphasis = elements.find((el) => el.type === "Emphasis")!;
    // The space right after "**bold" and before "*italic*" — inside
    // StrongEmphasis's span but strictly outside Emphasis's own span.
    const caret = doc.indexOf(" *italic");
    expect(caret).toBeLessThan(emphasis.start);

    const revealed = computeRevealedIds(elements, caret);
    expect(revealed.has(strong.id)).toBe(true);
  });
});

describe("rule 2 — end boundary is inclusive", () => {
  const doc = "**x**";
  // "**x**" occupies offsets 0..4, so end (one past the last char) is 5 —
  // the worked example straight from BEHAVIOR_SPEC.md section 12.

  it("caret immediately past the closing delimiter still reveals it", () => {
    const elements = elementsFor(doc);
    const strong = elements.find((el) => el.type === "StrongEmphasis")!;
    expect(strong.start).toBe(0);
    expect(strong.end).toBe(5);

    const revealed = computeRevealedIds(elements, 5);
    expect(revealed.has(strong.id)).toBe(true);
  });

  it("one more keystroke worth of caret position collapses it", () => {
    const elements = elementsFor(`${doc} `);
    const strong = elements.find((el) => el.type === "StrongEmphasis")!;

    const revealed = computeRevealedIds(elements, 6);
    expect(revealed.has(strong.id)).toBe(false);
  });
});

describe("rule 3 — a block marker reveals only its own marker span", () => {
  const doc = "# A";

  it("caret at the marker/text boundary reveals the marker", () => {
    const elements = elementsFor(doc);
    const heading = elements.find((el) => el.type === "ATXHeading1")!;
    expect(heading.checkStart).toBe(0);
    expect(heading.checkEnd).toBe(2); // "# " — marker plus its mandatory space

    const revealed = computeRevealedIds(elements, 2);
    expect(revealed.has(heading.id)).toBe(true);
  });

  it("caret inside the heading text leaves the marker collapsed", () => {
    const elements = elementsFor(doc);
    const heading = elements.find((el) => el.type === "ATXHeading1")!;

    const revealed = computeRevealedIds(elements, 3);
    expect(revealed.has(heading.id)).toBe(false);
  });

  it("holds at a deeper heading level too (## H2)", () => {
    const elements = elementsFor("## H2");
    const heading = elements.find((el) => el.type === "ATXHeading2")!;
    expect(heading.checkStart).toBe(0);
    expect(heading.checkEnd).toBe(3); // "## "

    expect(computeRevealedIds(elements, 3).has(heading.id)).toBe(true);
    expect(computeRevealedIds(elements, 4).has(heading.id)).toBe(false);
  });
});

describe("rule 4 — whole-line elements degenerate to the normal check", () => {
  it("a horizontal rule reveals only when the caret is on it", () => {
    const doc = "text\n\n---\n\nmore";
    const elements = elementsFor(doc);
    const hr = elements.find((el) => el.type === "HorizontalRule")!;
    expect(hr.checkStart).toBe(hr.start);
    expect(hr.checkEnd).toBe(hr.end);

    expect(computeRevealedIds(elements, hr.start + 1).has(hr.id)).toBe(true);
    expect(computeRevealedIds(elements, 0).has(hr.id)).toBe(false);
  });
});

describe("rule 6 — plain-text mode reveals nothing and collapses nothing", () => {
  it("passing an invalid (null) caret reveals no elements, however many exist", () => {
    const doc = "# Heading\n\n**bold** *italic* ~~strike~~ `code` [link](https://example.com)";
    const elements = elementsFor(doc);
    expect(elements.length).toBeGreaterThan(0);

    const revealed = computeRevealedIds(elements, null);
    expect(revealed.size).toBe(0);
  });
});

describe("rule 5 — with a selection, reveal resolves against the anchor", () => {
  const doc = "**one** **two**";
  // "**one** **two**"
  //  0       8

  it("uses the anchor even when the head sits over a different element", () => {
    const elements = elementsFor(doc);
    const one = elements.find((el) => el.start === 0)!;
    const two = elements.find((el) => el.start === 8)!;

    // Selection created by starting inside "one" and dragging into "two".
    const selection = { anchor: 3, head: 12 };
    const caret = caretForReveal(selection);
    expect(caret).toBe(3);

    const revealed = computeRevealedIds(elements, caret);
    expect(revealed.has(one.id)).toBe(true);
    expect(revealed.has(two.id)).toBe(false);
  });

  it("flips correctly when the selection is dragged the other direction", () => {
    const elements = elementsFor(doc);
    const one = elements.find((el) => el.start === 0)!;
    const two = elements.find((el) => el.start === 8)!;

    // Same visual selection, but this time it started inside "two".
    const selection = { anchor: 12, head: 3 };
    const caret = caretForReveal(selection);
    expect(caret).toBe(12);

    const revealed = computeRevealedIds(elements, caret);
    expect(revealed.has(two.id)).toBe(true);
    expect(revealed.has(one.id)).toBe(false);
  });
});

describe("coverage across element kinds", () => {
  it("bold, italic, strikethrough, inline code and links are all extracted as inline reveal candidates", () => {
    const doc =
      "**bold** *italic* ~~strike~~ `code` [link](https://example.com)";
    const elements = elementsFor(doc);
    const types = new Set(elements.map((el) => el.type));
    expect(types.has("StrongEmphasis")).toBe(true);
    expect(types.has("Emphasis")).toBe(true);
    expect(types.has("Strikethrough")).toBe(true);
    expect(types.has("InlineCode")).toBe(true);
    expect(types.has("Link")).toBe(true);
  });

  it("headings h1 through h3 are all extracted as block-marker candidates", () => {
    const doc = "# H1\n\n## H2\n\n### H3\n";
    const elements = elementsFor(doc);
    const headingTypes = elements
      .filter((el) => el.category === "block-marker")
      .map((el) => el.type);
    expect(headingTypes).toEqual(
      expect.arrayContaining(["ATXHeading1", "ATXHeading2", "ATXHeading3"]),
    );
  });
});
