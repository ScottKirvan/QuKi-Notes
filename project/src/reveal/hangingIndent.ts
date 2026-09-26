import { EditorView, ViewPlugin, type ViewUpdate } from "@codemirror/view";
import { floatSpan, rowTopFor, secondRowBox, type VerticalBox } from "./hangFloat";
import { listPrefixLength } from "./listPrefix";

const WIDTH = "--quki-hang-width";
const TOP = "--quki-hang-top";
const HEIGHT = "--quki-hang-height";

// Rows narrower than this fraction of the line's width would be unreadable, so
// a prefix that wide is left un-hung rather than squeezing the text.
const MAX_HANG_FRACTION = 0.75;

// Where the float begins below its estimate of the second row's top.
const FLOAT_TOP_MARGIN = 2;

// Far more rounds than any real line needs; the float grows by whole rows.
const MAX_ROUNDS = 200;

const WIDGET_SELECTOR = "img.cm-quki-image";

type Rendered = Text | Element;

interface Start {
  line: HTMLElement;
  rendered: Rendered[];
  width: number;
  top: number;
}

interface Growing extends Start {
  bottom: number;
}

function contentTop(line: HTMLElement): number {
  const style = getComputedStyle(line);
  return (
    line.getBoundingClientRect().top +
    Number.parseFloat(style.borderTopWidth) +
    Number.parseFloat(style.paddingTop)
  );
}

function renderedNodes(line: HTMLElement): Rendered[] {
  const nodes: Rendered[] = [];
  const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, {
    acceptNode: (node) =>
      node.nodeType === Node.TEXT_NODE || (node as Element).matches(WIDGET_SELECTOR)
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_SKIP,
  });
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    nodes.push(node as Rendered);
  }
  return nodes;
}

function characterBox(text: Text, index: number): DOMRect {
  const range = document.createRange();
  range.setStart(text, index);
  range.setEnd(text, index + 1);
  return range.getBoundingClientRect();
}

function* boxesInOrder(nodes: readonly Rendered[]): Generator<VerticalBox> {
  for (const node of nodes) {
    if (node instanceof Text) {
      for (let i = 0; i < node.length; i++) {
        const box = characterBox(node, i);
        if (box.height > 0) yield box;
      }
    } else {
      yield node.getBoundingClientRect();
    }
  }
}

function lastBox(nodes: readonly Rendered[]): VerticalBox | null {
  for (let n = nodes.length - 1; n >= 0; n--) {
    const node = nodes[n]!;
    if (node instanceof Text) {
      for (let i = node.length - 1; i >= 0; i--) {
        const box = characterBox(node, i);
        if (box.height > 0) return box;
      }
    } else {
      return node.getBoundingClientRect();
    }
  }
  return null;
}

function clearFloat(line: HTMLElement): void {
  for (const property of [WIDTH, TOP, HEIGHT]) {
    if (line.style.getPropertyValue(property) !== "") line.style.removeProperty(property);
  }
}

function setFloat({ line, width, top, bottom }: Growing): void {
  line.style.setProperty(WIDTH, `${width}px`);
  line.style.setProperty(TOP, `${top + FLOAT_TOP_MARGIN}px`);
  line.style.setProperty(HEIGHT, `${bottom - top - FLOAT_TOP_MARGIN}px`);
}

// Read from the line as the browser lays it out with no float at all: how far
// the line's text starts from its left content edge (it depends on the font,
// on tab stops and on how wide the marker and whitespace actually are, none of
// which can be known from the source), and where its second row begins.
function measureStart(view: EditorView, line: HTMLElement): Start | null {
  const lineStart = view.posAtDOM(line, 0);
  const doc = view.state.doc.lineAt(lineStart);
  const prefix = listPrefixLength(doc.text);
  if (prefix === null) return null;

  const first = view.coordsAtPos(doc.from, 1);
  const text = view.coordsAtPos(doc.from + prefix, 1);
  if (!first || !text) return null;
  // The text must begin on the first row; a prefix that itself wraps has
  // nothing sensible to hang under.
  if (text.top >= first.bottom) return null;

  const style = getComputedStyle(line);
  const paddingLeft = Number.parseFloat(style.paddingLeft);
  const contentWidth =
    line.clientWidth - paddingLeft - Number.parseFloat(style.paddingRight);
  const width = text.left - (line.getBoundingClientRect().left + paddingLeft);
  if (width <= 0 || width > contentWidth * MAX_HANG_FRACTION) return null;

  const rendered = renderedNodes(line);
  const second = secondRowBox(boxesInOrder(rendered));
  if (second === null) return null;
  const lineHeight = Number.parseFloat(style.lineHeight);
  const top = Number.isFinite(lineHeight)
    ? rowTopFor(second, lineHeight) - contentTop(line)
    : (second.top + second.bottom - first.top - first.bottom) / 2;
  return { line, rendered, width, top };
}

/*
 * A raw list-style line's wrapped rows start under the text after the marker:
 * a float (`.cm-quki-hang::before`) as wide as the marker pushes every row
 * after the first to the right. Its shape begins at the second row, so the
 * first row is laid out exactly as it is without the float — unlike padding
 * with a negative text-indent, which moves the content edge that every tab
 * stop in the first row is measured from. (`text-indent: <length> hanging`
 * would also leave the first row alone, but it needs Chromium 146; the desktop
 * app's Electron is Chromium 130.)
 *
 * The float has to end inside the last row: any shorter and the last rows are
 * not pushed over, any longer and it makes the line taller, and a tall enough
 * float makes the editor show a scrollbar, which narrows every line. But where
 * the last row is depends on how many rows the narrowed line has, which can
 * only be seen with the float in place. So the float starts as a sliver over the
 * second row and is grown to the last row of what the browser laid out with it,
 * until the last row is one it covers.
 *
 * All of this happens here in the read phase, in one pass: the float is first
 * made inert so that whatever an earlier layout left behind can't disturb what
 * is measured.
 */
function layoutHangs(view: EditorView): void {
  const lines = Array.from(view.contentDOM.querySelectorAll<HTMLElement>(".cm-quki-hang"));
  for (const line of lines) clearFloat(line);

  const growing: Growing[] = [];
  for (const line of lines) {
    const start = measureStart(view, line);
    if (start) growing.push({ ...start, bottom: start.top + FLOAT_TOP_MARGIN + 1 });
  }
  for (const float of growing) setFloat(float);

  let unsettled = growing;
  for (let round = 0; round < MAX_ROUNDS && unsettled.length > 0; round++) {
    const grown: Growing[] = [];
    for (const float of unsettled) {
      const last = lastBox(float.rendered);
      if (!last) continue;
      const span = floatSpan(
        float.top,
        (last.top + last.bottom) / 2 - contentTop(float.line),
        FLOAT_TOP_MARGIN,
      );
      const bottom = span.top + span.height;
      if (bottom > float.bottom + 0.01) {
        float.bottom = bottom;
        grown.push(float);
      }
    }
    for (const float of grown) setFloat(float);
    unsettled = grown;
  }
}

const hangRequest = {
  key: "quki-hanging-indent",
  read: layoutHangs,
};

export const hangingIndent = ViewPlugin.fromClass(
  class {
    constructor(view: EditorView) {
      view.requestMeasure(hangRequest);
    }

    update(update: ViewUpdate): void {
      if (
        update.transactions.length > 0 ||
        update.viewportChanged ||
        update.geometryChanged
      ) {
        update.view.requestMeasure(hangRequest);
      }
    }
  },
);
