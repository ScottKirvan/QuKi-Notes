/**
 * Line-parsing helpers shared by the formatting-toolbar commands. Ported
 * from markdown_editor.dart and indent_dedent.dart, which each defined
 * their own identical copies of line-bounds lookup, list-marker detection
 * and heading detection — collapsed here into one source of truth. This is
 * a DRY refactor of duplicated Dart logic, not a behavior change.
 */

const LEADING_WS_RE = /^[ \t]*/;
const TASK_PREFIX_RE = /^- \[[ xX]\] /;
const UNORDERED_PREFIX_RE = /^[-*] /;
const ORDERED_PREFIX_RE = /^\d+\. /;

export function leadingWs(line: string): string {
  return LEADING_WS_RE.exec(line)![0];
}

export function clamp(value: number, min: number, max: number): number {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/** [lineStart, lineEnd) bounds of the line containing `offset`. */
export function lineBoundsAt(text: string, offset: number): [number, number] {
  const lineStart = offset > 0 ? text.lastIndexOf("\n", offset - 1) + 1 : 0;
  const rawEnd = text.indexOf("\n", offset);
  const lineEnd = rawEnd === -1 ? text.length : rawEnd;
  return [lineStart, lineEnd];
}

/**
 * Walks the lines touched by a selection from `start` through the line
 * containing `anchorEnd`, returning each line's start offset. Ported from
 * the identical loop duplicated in markdown_editor.dart's
 * `_applyListMarkerToggleMultiLine` and indent_dedent.dart's
 * `_indentOrDedentSelection`.
 */
export function collectTouchedLineStarts(text: string, start: number, anchorEnd: number): number[] {
  const lineStarts: number[] = [];
  let pos = lineBoundsAt(text, start)[0];
  while (true) {
    lineStarts.push(pos);
    const lineEnd = lineBoundsAt(text, pos)[1];
    if (lineEnd >= anchorEnd || lineEnd >= text.length) break;
    pos = lineEnd + 1;
  }
  return lineStarts;
}

export type ListMarkerType = "unordered" | "ordered" | "checkbox";

export interface ListMarkerMatch {
  type: ListMarkerType;
  wsLen: number;
  markerLen: number;
}

/**
 * Detects a line's existing list marker. Priority order — task before
 * unordered before ordered — is deliberate: BEHAVIOR_SPEC.md's "Toolbar
 * toggle semantics" calls this "the checkbox wins", since `- [ ] x` would
 * otherwise also match the plain unordered pattern. Ported from
 * markdown_editor.dart's `_detectListMarker`.
 */
export function detectListMarker(line: string): ListMarkerMatch | null {
  const ws = leadingWs(line);
  const rest = line.slice(ws.length);

  const task = TASK_PREFIX_RE.exec(rest);
  if (task) {
    return { type: "checkbox", wsLen: ws.length, markerLen: task[0].length };
  }
  const unordered = UNORDERED_PREFIX_RE.exec(rest);
  if (unordered) {
    return { type: "unordered", wsLen: ws.length, markerLen: unordered[0].length };
  }
  const ordered = ORDERED_PREFIX_RE.exec(rest);
  if (ordered) {
    return { type: "ordered", wsLen: ws.length, markerLen: ordered[0].length };
  }
  return null;
}

/**
 * Heading level 1-6 for a line starting with `#` through `######` followed
 * by a space, 0 otherwise. Mirrors the six explicit `startsWith` checks in
 * the Dart source's `_isHeadingLine` exactly — seven-or-more leading `#`
 * characters do not count as a heading, matching those checks (none of the
 * six explicit patterns match a run of 7 hashes followed by a space).
 */
export function headingLevel(line: string): number {
  let n = 0;
  while (n < line.length && line[n] === "#") n++;
  if (n >= 1 && n <= 6 && line.charAt(n) === " ") return n;
  return 0;
}

export function isHeadingLine(line: string): boolean {
  return headingLevel(line) > 0;
}
