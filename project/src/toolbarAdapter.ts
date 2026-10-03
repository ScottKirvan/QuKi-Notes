import type { EditorState, TransactionSpec } from "@codemirror/state";
import type { EditorView } from "@codemirror/view";

import type { EditorValue } from "./toolbar/types";
import { headingLevel, lineBoundsAt } from "./toolbar/lines";

/**
 * Converts CodeMirror's live state into the `EditorValue` shape
 * `src/toolbar/*.ts`'s pure command functions expect. CodeMirror's
 * `state.selection.main` already uses `anchor`/`head` with the same
 * meaning `toolbar/types.ts` documents (anchor = where the selection
 * began, head = its moving end) — confirmed against CodeMirror's own
 * `EditorSelection.range` docs, so this is a field-for-field read, not a
 * translation.
 */
export function readEditorValue(state: EditorState): EditorValue {
  const { anchor, head } = state.selection.main;
  return { text: state.doc.toString(), selection: { anchor, head } };
}

/**
 * The heading level (0-3, since `cycleHeading` never produces more) of the
 * line containing the caret — what the toolbar's heading button icon
 * tracks per BEHAVIOR_SPEC.md ("The icon tracks the current level").
 * Reads the selection's anchor, matching reveal's own "caret position used
 * is the selection's ANCHOR" convention (BEHAVIOR_SPEC.md §12 rule 5),
 * since that's the one fixed point of an in-progress drag.
 */
export function currentHeadingLevel(state: EditorState): number {
  const text = state.doc.toString();
  const [lineStart, lineEnd] = lineBoundsAt(text, state.selection.main.anchor);
  return headingLevel(text.slice(lineStart, lineEnd));
}

/**
 * Turns a toolbar command's before/after `EditorValue` pair into a real
 * CodeMirror transaction spec — a full-document replace plus the new
 * selection, mirroring `main.ts`'s own `loadDocumentIntoEditor` shape but
 * WITHOUT the suppression flag that path uses: a toolbar button press is a
 * genuine user edit and must fire the normal docChanged path that triggers
 * auto-save.
 *
 * Returns `null` when the command was a true no-op (indent/dedent's
 * documented no-ops on headings, blockquotes, block images and horizontal
 * rules; a multi-line list-toggle with no eligible lines) — text and
 * selection both unchanged. Dispatching a same-text replace anyway would
 * still be a real transaction (CodeMirror doesn't diff content), which
 * would add a no-op entry to undo history and spuriously notify auto-save
 * for a press that changed nothing. When only the selection moved (a
 * dedent that only repositions the caret) this returns a selection-only
 * spec, so a caret-only change doesn't touch undo history either.
 */
export function buildTransaction(before: EditorValue, after: EditorValue): TransactionSpec | null {
  const textChanged = after.text !== before.text;
  const selectionChanged = after.selection.anchor !== before.selection.anchor || after.selection.head !== before.selection.head;

  if (!textChanged && !selectionChanged) return null;

  if (!textChanged) {
    return { selection: { anchor: after.selection.anchor, head: after.selection.head } };
  }

  return {
    changes: { from: 0, to: before.text.length, insert: after.text },
    selection: { anchor: after.selection.anchor, head: after.selection.head },
    scrollIntoView: true,
  };
}

/**
 * Applies one of `toolbar/*.ts`'s pure command functions to a live
 * CodeMirror view as a real, dispatched edit, then returns focus to the
 * editor — matching the Dart source's `_focusNode.requestFocus()` after
 * every controller method (formatting_toolbar.dart / markdown_editor.dart):
 * the toolbar is a way to edit without leaving the editor, not something
 * that steals focus. Shared by the toolbar's own buttons
 * (screens/formattingToolbar.ts) and the Tab/Shift-Tab keymap binding
 * (main.ts) so indent/dedent behave identically from either trigger.
 */
export function runToolbarCommand(view: EditorView, command: (value: EditorValue) => EditorValue): void {
  const before = readEditorValue(view.state);
  const after = command(before);
  const spec = buildTransaction(before, after);
  if (spec) view.dispatch(spec);
  view.focus();
}
