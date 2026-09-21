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
  checked: boolean | null;
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
      widget?: { checked?: boolean };
      class?: string;
      attributes?: { style?: string };
    };
    out.push({
      from,
      to,
      widget: spec.widget ? spec.widget.constructor.name : null,
      cls: spec.class ?? null,
      style: spec.attributes?.style ?? null,
      checked: spec.widget?.checked ?? null,
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
        { from: 6, to: 8, widget: "BulletWidget", cls: null, style: null, checked: null },
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

  it("given an indented item, when decorated, then its leading whitespace collapses together with the marker", () => {
    const doc = "- top\n\t- nested";
    const decos = widgets(decorationsFor(doc, doc.length), "BulletWidget");
    expect(decos.map((d) => [d.from, d.to])).toEqual([
      [0, 2],
      [6, 9],
    ]);
  });

  it("given the caret inside the indentation before the marker, when decorated, then the whole line reveals as raw source", () => {
    for (const caret of [6, 7]) {
      const decos = widgets(decorationsFor("- top\n  - nested", caret), "BulletWidget");
      expect(decos.map((d) => d.from)).toEqual([0]);
    }
  });

  it("given the caret one character past an indented marker's space, when decorated, then the indented marker collapses again", () => {
    const doc = "- top\n  - nested";
    expect(widgets(decorationsFor(doc, 10), "BulletWidget").map((d) => d.from)).toEqual([0]);
    expect(widgets(decorationsFor(doc, 11), "BulletWidget").map((d) => d.from)).toEqual([0, 6]);
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

describe("task checkbox collapse", () => {
  it("given an unchecked task and the caret elsewhere, when decorated, then the marker collapses to an unchecked checkbox", () => {
    const [box] = widgets(decorationsFor("plain\n- [ ] milk", 0), "CheckboxWidget");
    expect(box).toEqual(expect.objectContaining({ from: 6, to: 12, checked: false }));
  });

  it.each(["x", "X"])("given a - [%s] task, when decorated, then the checkbox is checked", (mark) => {
    const [box] = widgets(decorationsFor(`plain\n- [${mark}] milk`, 0), "CheckboxWidget");
    expect(box.checked).toBe(true);
  });

  it("given a task, when decorated, then no bullet is drawn for it", () => {
    const decos = decorationsFor("plain\n- [ ] milk", 0);
    expect(widgets(decos, "BulletWidget")).toEqual([]);
  });

  it("given the caret inside the marker, when decorated, then the raw marker shows and no checkbox is drawn", () => {
    expect(widgets(decorationsFor("- [ ] milk", 3), "CheckboxWidget")).toEqual([]);
  });

  it("given the caret at the boundary just after the marker's space, when decorated, then the raw marker still shows", () => {
    expect(widgets(decorationsFor("- [ ] milk", 6), "CheckboxWidget")).toEqual([]);
  });

  it("given the caret one character into the text, when decorated, then the checkbox is collapsed again", () => {
    expect(widgets(decorationsFor("- [ ] milk", 7), "CheckboxWidget")).toHaveLength(1);
  });

  it("given a nested task, when decorated, then its leading whitespace collapses together with the checkbox", () => {
    const doc = "- top\n\t- [ ] sub";
    const [box] = widgets(decorationsFor(doc, doc.length), "CheckboxWidget");
    expect([box.from, box.to]).toEqual([6, 13]);
  });

  it("given a checked task, when decorated, then its content is struck through", () => {
    const decos = decorationsFor("plain\n- [x] milk", 0);
    expect(byClass(decos, "cm-quki-checked-text")).toEqual([
      expect.objectContaining({ from: 12, to: 16 }),
    ]);
  });

  it("given a checked task with the caret in its marker, when decorated, then the content stays struck through", () => {
    const decos = decorationsFor("- [x] milk", 1);
    expect(byClass(decos, "cm-quki-checked-text")).toEqual([
      expect.objectContaining({ from: 6, to: 10 }),
    ]);
  });

  it("given an unchecked task, when decorated, then its content is not struck through", () => {
    expect(byClass(decorationsFor("plain\n- [ ] milk", 0), "cm-quki-checked-text")).toEqual([]);
  });

  it("given a checked task with no content, when decorated, then there is nothing to strike through", () => {
    expect(byClass(decorationsFor("plain\n- [x] ", 0), "cm-quki-checked-text")).toEqual([]);
  });

  it("given * [ ] text, when decorated, then it is a bullet, not a checkbox", () => {
    const decos = decorationsFor("plain\n* [ ] milk", 0);
    expect(widgets(decos, "CheckboxWidget")).toEqual([]);
    expect(widgets(decos, "BulletWidget")).toHaveLength(1);
  });

  it("given plain-text mode, when decorated, then tasks get no decorations", () => {
    expect(decorationsFor("- [x] a\n- [ ] b", 0, true)).toEqual([]);
  });
});

function listLines(decos: Deco[]): Deco[] {
  return byClass(decos, "cm-quki-list-line");
}

// Content starts at CodeMirror's 6px line inset + 16px per depth level + the
// 24px marker gutter; the first row is pulled back left by that gutter.
function listStyle(contentX: number): string {
  return `padding-left:${contentX}px;text-indent:-24px`;
}

describe("list item layout indentation", () => {
  it.each([
    ["bullet", "- a"],
    ["ordered", "1. a"],
    ["task", "- [ ] a"],
  ])("given a %s item at depth 0, when collapsed, then its line hangs its wrapped rows under the content", (_kind, item) => {
    const decos = listLines(decorationsFor(`plain\n\n${item}`, 0));
    expect(decos).toEqual([expect.objectContaining({ from: 7, style: listStyle(30) })]);
  });

  it.each([
    ["a tab", "\t", 46],
    ["two spaces", "  ", 46],
    ["four spaces", "    ", 62],
    ["three spaces", "   ", 46],
    ["one space", " ", 30],
  ])("given an item indented with %s under a parent, when collapsed, then its content starts at the depth's indentation", (_name, ws, contentX) => {
    const doc = `- top\n${ws}- nested`;
    const decos = listLines(decorationsFor(doc, 0)).filter((d) => d.from === 6);
    expect(decos).toEqual([expect.objectContaining({ style: listStyle(contentX) })]);
  });

  it("given a nested ordered item and a nested task, when collapsed, then each is indented to its own depth", () => {
    const doc = "1. top\n\t1. sub\n- [ ] t\n\t\t- [x] deep";
    const contentXByLine = new Map(listLines(decorationsFor(doc, doc.length)).map((d) => [d.from, d.style]));
    expect(contentXByLine.get(0)).toBe(listStyle(30));
    expect(contentXByLine.get(7)).toBe(listStyle(46));
    expect(contentXByLine.get(15)).toBe(listStyle(30));
  });

  it("given a collapsed indented item, when decorated, then its leading whitespace is hidden by the same replacement that draws the marker", () => {
    const doc = "- top\n\t- nested";
    const hidden = decorationsFor(doc, doc.length).filter((d) => d.from === 6);
    expect(hidden.map((d) => [d.from, d.to, d.widget])).toEqual(
      expect.arrayContaining([[6, 9, "BulletWidget"]]),
    );
    expect(hiddenRanges(decorationsFor(doc, doc.length))).toEqual([]);
  });

  it("given the caret in an indented item's marker span, when decorated, then that line shows raw source with no layout indentation", () => {
    const doc = "- top\n  - nested\n  - other";
    const decos = decorationsFor(doc, 7);
    expect(widgets(decos, "BulletWidget").map((d) => d.from)).toEqual([0, 17]);
    expect(listLines(decos).map((d) => d.from)).toEqual([0, 17]);
  });

  it("given a revealed line between two lines at the same depth, when decorated, then the neighbours keep their indentation", () => {
    const doc = "- a\n  - b\n  - c\n  - d";
    const decos = decorationsFor(doc, doc.indexOf("- c") + 1);
    const lines = listLines(decos);
    expect(lines.map((d) => [d.from, d.style])).toEqual([
      [0, listStyle(30)],
      [4, listStyle(46)],
      [16, listStyle(46)],
    ]);
  });

  it("given a revealed task, when decorated, then its raw source shows and no checkbox or layout indentation is drawn", () => {
    const doc = "- top\n\t- [ ] sub";
    const decos = decorationsFor(doc, 8);
    expect(widgets(decos, "CheckboxWidget")).toEqual([]);
    expect(listLines(decos).map((d) => d.from)).toEqual([0]);
  });

  it("given non-list lines beside a list item, when decorated, then none of them receives the marker gutter", () => {
    const doc = "# head\n- a\nplain\n> quote";
    const decos = decorationsFor(doc, doc.length);
    expect(listLines(decos).map((d) => d.from)).toEqual([7]);
  });

  it("given a quote line beside a list item, when decorated, then the quote keeps its own indentation and gets no list layout", () => {
    const doc = "- a\n\n> q";
    const decos = decorationsFor(doc, doc.length);
    expect(listLines(decos).map((d) => d.from)).toEqual([0]);
    const [bar] = byClass(decos, "cm-quki-quote");
    expect(bar.from).toBe(5);
    expect(bar.style).toContain("padding-left:16px");
    expect(bar.style).not.toContain("text-indent");
  });

  it("given a list item quoted or nested inside a quote, when decorated, then it stays raw text with no list layout", () => {
    const decos = decorationsFor("> - a\n> > - b", 0);
    expect(listLines(decos)).toEqual([]);
  });

  it("given plain-text mode, when decorated, then no line receives layout indentation", () => {
    expect(listLines(decorationsFor("- a\n\t- b", 0, true))).toEqual([]);
  });
});

function hangLines(decos: Deco[]): number[] {
  return byClass(decos, "cm-quki-hang").map((d) => d.from);
}

describe("raw list-style lines hang their wrapped rows", () => {
  it("given the caret in a top-level item's marker, when decorated, then the raw line is marked to hang and is not also given the collapsed layout", () => {
    const doc = "- a\n- b";
    const decos = decorationsFor(doc, 1);
    expect(hangLines(decos)).toEqual([0]);
    expect(listLines(decos).map((d) => d.from)).toEqual([4]);
  });

  it.each([
    ["nested bullet", "- top\n\t- nested", 8, 6],
    ["ordered", "1. a\n2. b", 1, 0],
    ["two-digit ordered", "10. a\n\nx", 1, 0],
    ["task", "- [ ] a\n- b", 1, 0],
  ])("given the caret in a revealed %s item's marker, when decorated, then that line is marked to hang", (_name, doc, caret, lineFrom) => {
    expect(hangLines(decorationsFor(doc, caret))).toContain(lineFrom);
  });

  it("given a line that looks like a list item but the parser did not make one, when decorated, then it is marked to hang", () => {
    const doc = "- blah\n        - jdjd djdid\n- x";
    const decos = decorationsFor(doc, doc.length);
    expect(hangLines(decos)).toEqual([7]);
    expect(listLines(decos).map((d) => d.from)).toEqual([0, doc.indexOf("- x")]);
  });

  it("given collapsed items, when decorated, then none is marked to hang", () => {
    const doc = "plain\n- a\n\t- b\n1. c\n- [ ] d";
    expect(hangLines(decorationsFor(doc, 0))).toEqual([]);
  });

  it("given a line whose text only resembles a marker, when decorated, then it is not marked to hang", () => {
    const doc = "-x\n1.x\ntext - more\n> - q\n# - h";
    expect(hangLines(decorationsFor(doc, 0))).toEqual([]);
  });

  it("given a collapsed horizontal rule that looks like a bullet run, when decorated, then it is not marked to hang", () => {
    const doc = "text\n\n- - -\n\nmore";
    expect(hangLines(decorationsFor(doc, 0))).toEqual([]);
  });

  it("given plain-text mode, when decorated, then no line is marked to hang", () => {
    expect(hangLines(decorationsFor("- a\n        - b\n1. c", 0, true))).toEqual([]);
  });

  it("given a marked line, then the mark carries no inline style of its own (the measured offset is applied at layout time)", () => {
    const [deco] = byClass(decorationsFor("- a", 1), "cm-quki-hang");
    expect(deco.style).toBeNull();
  });
});
