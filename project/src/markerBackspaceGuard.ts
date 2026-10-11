import { EditorSelection, EditorState, Transaction, type Extension } from "@codemirror/state";

const LINE_MARKUP_PREFIX =
  /^(?:[ \t]*>[ \t]?)*(?:[ \t]*(?:[-*+]|\d{1,9}[.)])(?=[ \t]|$)(?:[ \t]+\[[ xX]\](?=[ \t]|$))?[ \t]?)?/;

/**
 * BEHAVIOR_SPEC.md §4: Backspace deletes list, task and quote markers one
 * character at a time. A rendered marker is a replaced range, so when the
 * browser deletes in the DOM itself (Android without EditContext) the whole
 * widget goes in one change that CodeMirror reads back as "input.type" and
 * no keymap ever sees. This narrows any backward deletion, however it
 * arrived, that removes more than one character of a line's marker prefix
 * ending at the caret to the single character before the caret.
 */
export const markerBackspaceGuard: Extension = EditorState.transactionFilter.of((tr) => {
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

  const line = tr.startState.doc.lineAt(caret);
  if (from < line.from) return tr;
  const prefix = LINE_MARKUP_PREFIX.exec(line.text)?.[0] ?? "";
  if (to > line.from + prefix.length) return tr;
  if (!/\S/.test(tr.startState.sliceDoc(from, to))) return tr;

  return {
    changes: { from: caret - 1, to: caret },
    selection: EditorSelection.cursor(caret - 1),
    effects: tr.effects,
    annotations: Transaction.userEvent.of(tr.annotation(Transaction.userEvent) ?? "delete.backward"),
    scrollIntoView: tr.scrollIntoView,
  };
});
