/**
 * Offset-based editor state shared by every formatting-toolbar command in
 * this module. `anchor`/`head` follow CodeMirror's selection convention
 * (anchor = where the selection began, head = its moving end); a collapsed
 * selection has `anchor === head`. This mirrors Flutter's
 * `TextSelection.baseOffset`/`extentOffset` from the source being ported,
 * and composes with `reveal/types.ts`'s end-exclusive offset convention
 * used elsewhere in this codebase.
 */
export interface EditorSelection {
  anchor: number;
  head: number;
}

export interface EditorValue {
  text: string;
  selection: EditorSelection;
}
