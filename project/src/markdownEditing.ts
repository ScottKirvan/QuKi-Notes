import type { Extension } from "@codemirror/state";
import { Prec } from "@codemirror/state";
import { indentUnit } from "@codemirror/language";
import { insertNewlineContinueMarkup, markdown } from "@codemirror/lang-markdown";
import { keymap } from "@codemirror/view";
import { GFM } from "@lezer/markdown";

/**
 * The editor's markdown language, tuned to BEHAVIOR_SPEC.md §4:
 * - A tab indent unit. Enter's list continuation (insertNewlineContinueMarkup)
 *   rebuilds the new line's indentation as spaces unless the indent unit is a
 *   tab, and the app counts a tab as one depth but four spaces as two
 *   (toolbar/indentDedent.ts, reveal/types.ts) - without it Enter after a
 *   tab-indented item doubled the new item's depth.
 * - Only Enter from markdown()'s own keymap: that keymap also binds Backspace
 *   to deleteMarkupBackward, which removes a whole list or quote marker at
 *   once, where Backspace must delete one character at a time.
 */
export function markdownEditing(): Extension {
  return [
    indentUnit.of("\t"),
    markdown({ extensions: GFM, addKeymap: false }),
    Prec.high(keymap.of([{ key: "Enter", run: insertNewlineContinueMarkup }])),
  ];
}
