import { EditorSelection, EditorState, Transaction, type Extension } from "@codemirror/state";
import { EditorView, runScopeHandlers } from "@codemirror/view";

const LINE_MARKUP_PREFIX =
  /^(?:[ \t]*>[ \t]?)*(?:[ \t]*(?:[-*+]|\d{1,9}[.)])(?=[ \t]|$)(?:[ \t]+\[[ xX]\](?=[ \t]|$))?[ \t]?)?/;

function markerPrefixEnd(state: EditorState, pos: number): number {
  const line = state.doc.lineAt(pos);
  return line.from + (LINE_MARKUP_PREFIX.exec(line.text)?.[0] ?? "").length;
}

/**
 * BEHAVIOR_SPEC.md §4: Backspace deletes list, task and quote markers one
 * character at a time. A rendered marker is a replaced range, so when the
 * browser deletes in the DOM itself (Android without EditContext) the whole
 * widget goes in one change that CodeMirror reads back as "input.type" and
 * no keymap ever sees. This narrows any backward deletion, however it
 * arrived, that removes more than one character of a line's marker prefix
 * ending at the caret to the single character before the caret.
 */
const narrowMarkerDeletion = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged || !(tr.isUserEvent("input.type") || tr.isUserEvent("delete.backward"))) return tr;
  const { ranges } = tr.startState.selection;
  if (ranges.length !== 1 || !ranges[0].empty) return tr;
  const caret = ranges[0].head;

  let deleted: { from: number; to: number } | null = null;
  let changeCount = 0;
  tr.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
    changeCount++;
    if (inserted.length === 0) deleted = { from: fromA, to: toA };
  });
  if (changeCount !== 1 || deleted === null) return tr;
  const { from, to } = deleted as { from: number; to: number };
  if (to !== caret || to - from < 2) return tr;

  if (from < tr.startState.doc.lineAt(caret).from) return tr;
  if (to > markerPrefixEnd(tr.startState, caret)) return tr;
  if (!/\S/.test(tr.startState.sliceDoc(from, to))) return tr;

  return {
    changes: { from: caret - 1, to: caret },
    selection: EditorSelection.cursor(caret - 1),
    effects: tr.effects,
    annotations: Transaction.userEvent.of(tr.annotation(Transaction.userEvent) ?? "delete.backward"),
    scrollIntoView: tr.scrollIntoView,
  };
});

/**
 * Whether the caret sits inside a line's marker prefix with something to
 * delete before it - where a backward deletion the DOM swallowed still has
 * to delete a character.
 */
export function caretInMarkerPrefix(state: EditorState): boolean {
  const { ranges } = state.selection;
  if (ranges.length !== 1 || !ranges[0].empty) return false;
  const caret = ranges[0].head;
  const lineFrom = state.doc.lineAt(caret).from;
  if (caret === lineFrom || caret > markerPrefixEnd(state, caret)) return false;
  return /\S/.test(state.sliceDoc(lineFrom, caret));
}

/**
 * With the caret right after a marker drawn at the end of its line,
 * @codemirror/view (since 6.43.14) puts the DOM caret after the widget's
 * trailing cm-widgetBuffer, so a browser-native backward delete removes only
 * that buffer and the document does not change at all - no transaction for
 * narrowMarkerDeletion to see. Once CodeMirror has read the DOM back (its
 * Chrome Android key fallback runs in an animation frame queued before this
 * one), a deletion that left the document untouched runs Backspace's key
 * bindings, as a key press would.
 */
const swallowedMarkerDeletion = EditorView.domEventHandlers({
  input(event, view) {
    if ((event as InputEvent).inputType !== "deleteContentBackward") return false;
    const before = view.state;
    if (!caretInMarkerPrefix(before)) return false;
    requestAnimationFrame(() => {
      if (view.composing || view.state.doc !== before.doc || !view.state.selection.eq(before.selection)) return;
      const backspace = new KeyboardEvent("keydown", { key: "Backspace", keyCode: 8 });
      runScopeHandlers(view, backspace, "editor");
    });
    return false;
  },
});

export const markerBackspaceGuard: Extension = [narrowMarkerDeletion, swallowedMarkerDeletion];
