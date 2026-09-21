import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { buildDecorations } from "./decorations";
import { plainTextMode, setPlainTextMode } from "./plainTextMode";

interface Deco {
  from: number;
  to: number;
  widget: string | null;
  cls: string | null;
  style: string | null;
}

function decorationsFor(doc: string, caret: number, plain = false): Deco[] {
  let state = EditorState.create({
    doc,
    selection: { anchor: caret },
    extensions: [markdown({ extensions: GFM }), plainTextMode],
  });
  if (plain) {
    state = state.update({ effects: setPlainTextMode.of(true) }).state;
  }
  const out: Deco[] = [];
  buildDecorations(state).between(0, doc.length, (from, to, value) => {
    const spec = value.spec as {
      widget?: object;
      class?: string;
      attributes?: { style?: string };
    };
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

function widgets(decos: Deco[], name: string): Deco[] {
  return decos.filter((d) => d.widget === name);
}

describe("unordered list marker collapse", () => {
  it.each(["-", "*", "+"])(
    "given a %s item and the caret on another line, when decorated, then the marker collapses to a bullet",
    (bullet) => {
      const doc = `plain\n${bullet} apple`;
      const decos = decorationsFor(doc, 0);
      expect(widgets(decos, "BulletWidget")).toEqual([
        { from: 6, to: 8, widget: "BulletWidget", cls: null, style: null },
      ]);
    },
  );

  it("given the caret at the start of the marker, when decorated, then the raw marker shows", () => {
    expect(widgets(decorationsFor("- apple", 0), "BulletWidget")).toEqual([]);
  });

  it("given the caret at the boundary just after the marker's space, when decorated, then the raw marker still shows", () => {
    expect(widgets(decorationsFor("- apple", 2), "BulletWidget")).toEqual([]);
  });

  it("given the caret one character past the marker, when decorated, then the marker is collapsed again", () => {
    expect(widgets(decorationsFor("- apple", 3), "BulletWidget")).toHaveLength(1);
  });

  it("given the caret at the end of the item's text, when decorated, then the marker stays collapsed", () => {
    expect(widgets(decorationsFor("- apple", 7), "BulletWidget")).toHaveLength(1);
  });

  it("given an indented item, when decorated, then only the marker collapses, not its indentation", () => {
    const doc = "- top\n\t- nested";
    const decos = widgets(decorationsFor(doc, doc.length), "BulletWidget");
    expect(decos.map((d) => [d.from, d.to])).toEqual([
      [0, 2],
      [7, 9],
    ]);
  });

  it("given the caret inside the indentation before the marker, when decorated, then the marker stays collapsed", () => {
    const decos = widgets(decorationsFor("- top\n  - nested", 6), "BulletWidget");
    expect(decos.map((d) => d.from)).toEqual([0, 8]);
  });
});

describe("ordered list marker collapse", () => {
  it("given 1. / 1. / 1. with the caret elsewhere, when decorated, then the markers collapse to numbers 1, 2, 3", () => {
    const doc = "1. a\n1. b\n1. c\n\nend";
    const decos = decorationsFor(doc, doc.length);
    expect(widgets(decos, "OrderedMarkerWidget")).toHaveLength(3);
    const numbers = decos
      .filter((d) => d.widget === "OrderedMarkerWidget")
      .map((d) => d.from);
    expect(numbers).toEqual([0, 5, 10]);
  });

  it("given the caret in the marker of the second item, when decorated, then only that item's raw marker shows", () => {
    const doc = "1. a\n1. b\n1. c";
    const decos = widgets(decorationsFor(doc, 6), "OrderedMarkerWidget");
    expect(decos.map((d) => d.from)).toEqual([0, 10]);
  });

  it("given an ordered item, when decorated, then the marker span covers digits, dot and space", () => {
    const decos = widgets(decorationsFor("x\n\n12. twelve", 0), "OrderedMarkerWidget");
    expect(decos.map((d) => [d.from, d.to])).toEqual([[3, 7]]);
  });
});

describe("plain-text mode", () => {
  it("given plain-text mode, when decorated, then there are no decorations at all", () => {
    const doc = "- a\n1. b\n\n- c";
    expect(decorationsFor(doc, 0, true)).toEqual([]);
    expect(decorationsFor(doc, doc.length, true)).toEqual([]);
  });
});

function byClass(decos: Deco[], cls: string): Deco[] {
  return decos.filter((d) => d.cls === cls);
}

function hiddenRanges(decos: Deco[]): [number, number][] {
  return decos
    .filter((d) => d.widget === null && d.cls === null && d.from < d.to)
    .map((d) => [d.from, d.to]);
}

describe("blockquote marker collapse", () => {
  it("given a quote line and the caret elsewhere, when decorated, then the marker is hidden", () => {
    const decos = decorationsFor("plain\n\n> quoted", 0);
    expect(hiddenRanges(decos)).toEqual([[7, 9]]);
  });

  it("given the caret in the marker, when decorated, then the raw marker shows and the line has no quote bar", () => {
    const decos = decorationsFor("> quoted", 0);
    expect(hiddenRanges(decos)).toEqual([]);
    expect(byClass(decos, "cm-quki-quote")).toEqual([]);
  });

  it("given the caret at the boundary just after the marker's space, when decorated, then the raw marker still shows", () => {
    expect(hiddenRanges(decorationsFor("> quoted", 2))).toEqual([]);
  });

  it("given the caret one character into the content, when decorated, then the marker is hidden again", () => {
    expect(hiddenRanges(decorationsFor("> quoted", 3))).toEqual([[0, 2]]);
  });

  it("given a collapsed quote line, when decorated, then the content is muted and the line carries the quote bar", () => {
    const decos = decorationsFor("plain\n\n> quoted", 0);
    expect(byClass(decos, "cm-quki-quote-text")).toEqual([
      expect.objectContaining({ from: 9, to: 15 }),
    ]);
    const bar = byClass(decos, "cm-quki-quote");
    expect(bar).toHaveLength(1);
    expect(bar[0].from).toBe(7);
  });

  it("given the caret in the marker, when decorated, then the content stays muted", () => {
    const decos = decorationsFor("> quoted", 1);
    expect(byClass(decos, "cm-quki-quote-text")).toEqual([
      expect.objectContaining({ from: 2, to: 8 }),
    ]);
  });

  it("given a bare > line with no content, when decorated, then the marker hides and no content style is added", () => {
    const decos = decorationsFor("plain\n\n>", 0);
    expect(hiddenRanges(decos)).toEqual([[7, 8]]);
    expect(byClass(decos, "cm-quki-quote-text")).toEqual([]);
  });

  it("given a quote spanning several lines, when the caret is in one, then only that line's marker shows", () => {
    const decos = decorationsFor("> a\n> b\n> c", 5);
    expect(hiddenRanges(decos)).toEqual([
      [0, 2],
      [8, 10],
    ]);
    expect(byClass(decos, "cm-quki-quote").map((d) => d.from)).toEqual([0, 8]);
  });

  it("given a nested quote, when collapsed, then one bar per level is drawn and the whole marker hides", () => {
    const decos = decorationsFor("plain\n\n> > deep", 0);
    expect(hiddenRanges(decos)).toEqual([[7, 11]]);
    const [bar] = byClass(decos, "cm-quki-quote");
    expect(bar.style).toContain("padding-left:32px");
    expect(bar.style?.match(/linear-gradient/g)).toHaveLength(2);
  });

  it("given a single-level quote, when collapsed, then the bar is one gradient and the content is indented 16px", () => {
    const [bar] = byClass(decorationsFor("plain\n\n> q", 0), "cm-quki-quote");
    expect(bar.style).toContain("padding-left:16px");
    expect(bar.style?.match(/linear-gradient/g)).toHaveLength(1);
  });

  it("given a lazy continuation line, when decorated, then that line is not styled as a quote", () => {
    const decos = decorationsFor("> a\nlazy", 8);
    expect(byClass(decos, "cm-quki-quote-text").every((d) => d.to <= 3)).toBe(true);
  });

  it("given plain-text mode, when decorated, then quote lines get no decorations", () => {
    expect(decorationsFor("> a\n> > b", 0, true)).toEqual([]);
  });
});
