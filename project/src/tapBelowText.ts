import { Prec, StateEffect, StateField, type EditorState, type Extension, type TransactionSpec } from "@codemirror/state";
import { EditorView } from "@codemirror/view";

const setPaddingStart = StateEffect.define<number | null>();

/**
 * Where the blank lines added by a tap below the text begin, or null. Blank
 * lines from there to the end with nothing typed after them are padding, not
 * content: they keep the caret where the user tapped but are never saved.
 */
const paddingStart = StateField.define<number | null>({
  create: () => null,
  update(value, tr) {
    for (const effect of tr.effects) if (effect.is(setPaddingStart)) return effect.value;
    return value === null ? null : tr.changes.mapPos(value, -1);
  },
});

function isBlank(text: string): boolean {
  return /^\s*$/.test(text);
}

/** Appends `lines` blank lines and puts the caret at the start of the last one. */
export function padBelowText(state: EditorState, lines: number): TransactionSpec {
  const end = state.doc.length;
  const existing = state.field(paddingStart, false) ?? null;
  const start = existing !== null && isBlank(state.doc.sliceString(existing)) ? existing : end;
  return {
    changes: { from: end, insert: "\n".repeat(lines) },
    selection: { anchor: end + lines },
    effects: setPaddingStart.of(start),
    userEvent: "input",
    scrollIntoView: true,
  };
}

export function forgetTapPadding(): TransactionSpec {
  return { effects: setPaddingStart.of(null) };
}

/** The QuKi's text as it should be saved or sent: without padding nothing was typed after. */
export function bodyWithoutUnusedPadding(state: EditorState): string {
  const doc = state.doc.toString();
  const start = state.field(paddingStart, false) ?? null;
  if (start === null || !isBlank(doc.slice(start))) return doc;
  return doc.slice(0, start);
}

/** How many blank lines a tap at `clientY` needs, or 0 when it isn't below the last line. */
export function linesNeededToReach(clientY: number, lastLineBottom: number, lineHeight: number): number {
  if (clientY <= lastLineBottom) return 0;
  return Math.floor((clientY - lastLineBottom) / lineHeight) + 1;
}

/**
 * A tap below the last line starts a line where the user tapped, padding
 * with blank lines, instead of sending the caret to the end of the text
 * (the manifesto's "velocity": no hunting for the end to add space).
 */
export function tapBelowTextStartsALine(focusEditor: () => void): Extension {
  return [
    paddingStart,
    Prec.highest(
      EditorView.domEventHandlers({
        mousedown(event, view) {
          if (event.button !== 0 || event.shiftKey || event.ctrlKey || event.metaKey || event.altKey) return false;
          const lastLineBottom = view.documentTop + view.lineBlockAt(view.state.doc.length).bottom;
          const lines = linesNeededToReach(event.clientY, lastLineBottom, view.defaultLineHeight);
          if (lines === 0) return false;
          event.preventDefault();
          view.dispatch(padBelowText(view.state, lines));
          focusEditor();
          return true;
        },
      }),
    ),
  ];
}
