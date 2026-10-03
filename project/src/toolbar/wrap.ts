import type { EditorValue } from "./types";

/**
 * Wraps the selection with `prefix`/`suffix`; with a collapsed selection,
 * inserts the delimiter pair and places the caret between them
 * (BEHAVIOR_SPEC.md's "Toolbar toggle semantics"). Ported from
 * markdown_editor.dart's `wrapSelection`, used for all four inline-format
 * buttons: bold `**`/`**`, italic `_`/`_` (deliberately not `*`/`*` — see
 * formatting_toolbar.dart line 42), strikethrough `~~`/`~~`, inline code
 * `` ` ``/`` ` ``. The caller supplies the delimiter pair, matching how the
 * Dart toolbar calls this generically rather than having one function per
 * button.
 */
export function wrapSelection(value: EditorValue, prefix: string, suffix: string): EditorValue {
  const { text, selection } = value;
  const start = Math.min(selection.anchor, selection.head);
  const end = Math.max(selection.anchor, selection.head);
  const selected = text.slice(start, end);

  const newText = text.slice(0, start) + prefix + selected + suffix + text.slice(end);
  const newOffset = start + prefix.length + (selected.length === 0 ? 0 : selected.length + suffix.length);

  return { text: newText, selection: { anchor: newOffset, head: newOffset } };
}
