import { EditorView, ViewPlugin, type ViewUpdate } from "@codemirror/view";
import { listPrefixLength } from "./listPrefix";

const HANG_PROPERTY = "--quki-hang";

// Rows narrower than this fraction of the line's width would be unreadable, so
// a prefix that wide is left un-hung rather than squeezing the text.
const MAX_HANG_FRACTION = 0.75;

interface HangMeasurement {
  line: HTMLElement;
  hang: number | null;
}

// The distance from the line's left content edge to where its text starts is
// read back from the rendered line: it depends on the font, on tab stops and
// on how wide the marker and whitespace actually are, none of which can be
// known from the source alone. The offset is applied as text-indent with the
// `hanging` keyword, which — unlike padding — leaves the line's content edge,
// and therefore every tab stop in the first row, exactly where it was.
function measureHang(view: EditorView, line: HTMLElement): number | null {
  const lineStart = view.posAtDOM(line, 0);
  const doc = view.state.doc.lineAt(lineStart);
  const prefix = listPrefixLength(doc.text);
  if (prefix === null) return null;

  const start = view.coordsAtPos(doc.from, 1);
  const text = view.coordsAtPos(doc.from + prefix, 1);
  if (!start || !text) return null;
  // The text must begin on the first row; a prefix that itself wraps has
  // nothing sensible to hang under.
  if (text.top >= start.bottom) return null;

  const style = getComputedStyle(line);
  const contentLeft =
    line.getBoundingClientRect().left + Number.parseFloat(style.paddingLeft);
  const contentWidth =
    line.clientWidth -
    Number.parseFloat(style.paddingLeft) -
    Number.parseFloat(style.paddingRight);
  const hang = text.left - contentLeft;
  if (hang <= 0 || hang > contentWidth * MAX_HANG_FRACTION) return null;
  return hang;
}

const hangRequest = {
  key: "quki-hanging-indent",
  read(view: EditorView): HangMeasurement[] {
    const lines = view.contentDOM.querySelectorAll<HTMLElement>(".cm-quki-hang");
    return Array.from(lines, (line) => ({ line, hang: measureHang(view, line) }));
  },
  write(measurements: HangMeasurement[]): void {
    for (const { line, hang } of measurements) {
      const before = line.style.getPropertyValue(HANG_PROPERTY);
      if (hang === null) {
        if (before !== "") line.style.removeProperty(HANG_PROPERTY);
      } else if (before !== `${hang}px`) {
        line.style.setProperty(HANG_PROPERTY, `${hang}px`);
      }
    }
  },
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
