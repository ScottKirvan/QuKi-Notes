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
    const spec = value.spec as { widget?: object; class?: string };
    out.push({
      from,
      to,
      widget: spec.widget ? spec.widget.constructor.name : null,
      cls: spec.class ?? null,
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
        { from: 6, to: 8, widget: "BulletWidget", cls: null },
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
