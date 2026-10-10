import type { Extension } from "@codemirror/state";
import { indentUnit } from "@codemirror/language";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";

/**
 * The editor's markdown language plus the tab indent unit. Enter's list
 * continuation (insertNewlineContinueMarkup) rebuilds the new line's
 * indentation as spaces unless the indent unit is a tab, and the app counts
 * a tab as one depth but four spaces as two (toolbar/indentDedent.ts,
 * reveal/types.ts) - so without it Enter after a tab-indented item doubled
 * the new item's depth.
 */
export function markdownEditing(): Extension {
  return [indentUnit.of("\t"), markdown({ extensions: GFM })];
}
