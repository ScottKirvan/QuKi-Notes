import type { EditorView } from "@codemirror/view";
import { toggleCheckbox } from "./checkboxToggle";

/**
 * Applies the checkbox toggle for the line containing `pos`. The selection
 * is passed back explicitly: the edit swaps one six-character marker for
 * another of the same length, so every offset stays valid and the cursor is
 * exactly where the tap found it. No scroll is requested.
 */
export function toggleCheckboxAt(view: EditorView, pos: number): boolean {
  const line = view.state.doc.lineAt(pos);
  const edit = toggleCheckbox(line.text);
  if (edit === null) return false;
  view.dispatch({
    changes: {
      from: line.from + edit.from,
      to: line.from + edit.to,
      insert: edit.insert,
    },
    selection: view.state.selection,
  });
  return true;
}
