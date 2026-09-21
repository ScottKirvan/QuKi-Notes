export type ElementCategory = "inline" | "block-marker";

/**
 * A single reveal-candidate parsed out of the CodeMirror/Lezer markdown
 * syntax tree.
 *
 * `start`/`end` is the element's full source extent (end is one past the
 * last character, matching the convention in the reveal spec).
 *
 * `checkStart`/`checkEnd` is the range actually compared against the caret
 * to decide reveal. For inline elements this equals `start`/`end`. For
 * block markers (headings) and whole-line elements (images, horizontal
 * rules) it is the marker span only — see rules 3 and 4 in
 * BEHAVIOR_SPEC.md section 12.
 *
 * List-item and blockquote elements (`BulletItem`, `OrderedItem`,
 * `TaskItem`, `BlockquoteLine`) are one per source line: `start` is the
 * line's first character, `end` is the end of that line, and
 * `checkStart`/`checkEnd` is the marker span. For a list item the marker span
 * includes the item's leading whitespace, so the whitespace that collapses
 * into layout indentation reappears as raw text when the marker is revealed.
 * The optional fields below carry what the collapsed rendering needs.
 *
 * `parentId` links an inline element to its nearest inline ancestor, which
 * is how the outermost-element rule (rule 1) is resolved. Block-marker
 * elements are never nested for reveal purposes, so their `parentId` is
 * always null.
 */
export interface RevealElement {
  id: number;
  type: string;
  category: ElementCategory;
  start: number;
  end: number;
  checkStart: number;
  checkEnd: number;
  parentId: number | null;
  /**
   * List, ordered and task items: layout depth from the leading whitespace
   * (a space is one column, a tab two, depth is columns divided by two,
   * rounded down).
   */
  indentDepth?: number;
  /** OrderedItem only: the block-relative number to render. */
  orderedNumber?: number;
  /** TaskItem only. */
  checked?: boolean;
  /** BlockquoteLine only: how many `>` levels the marker consumed. */
  quoteDepth?: number;
}
