import type { EditorValue, EditorSelection } from "./types";
import { clamp, collectTouchedLineStarts, headingLevel, lineBoundsAt } from "./lines";

function nextHeadingLevel(level: number): number {
  if (level === 0) return 1;
  if (level === 1) return 2;
  if (level === 2) return 3;
  return 0;
}

function prefixForLevel(level: number): string {
  return level > 0 ? "#".repeat(level) + " " : "";
}

/**
 * Cycles the heading level of the line(s) touched by the selection: normal
 * -> H1 -> H2 -> H3 -> normal, with any line already at H4-H6 dropping to
 * normal on the next press.
 *
 * BEHAVIOR_SPEC.md ("Formatting toolbar — ten buttons") is explicit that
 * this rewrite REPLACES the old Dart behavior — `toggleLinePrefix('# ')`,
 * an H1-only on/off toggle — with this cycle. There is no Dart source or
 * test for the cycle itself, so it's implemented fresh here; only the
 * general shape of "operate on the line(s) the selection touches, with a
 * collapsed-vs-range split and an offset remap for the range case" is
 * carried over from the Dart list-marker-toggle machinery this is modeled
 * on.
 *
 * [Proposed — unconfirmed] For a multi-line selection, the spec says "the
 * next state from the first line" is applied to all touched lines. This is
 * read here as: the line at the LOWER of the two selection offsets (i.e.
 * by document position — `Math.min(anchor, head)` — not by which offset is
 * the anchor) decides the next level via the cycle above, and that exact
 * resulting prefix (add/replace/remove) is then applied uniformly to every
 * line the selection touches, converging a mixed selection to one level.
 * This is my reading of ambiguous spec prose, not something confirmed with
 * Scott.
 */
export function cycleHeading(value: EditorValue): EditorValue {
  const { text, selection } = value;
  if (selection.anchor === selection.head) {
    return cycleHeadingCollapsed(text, selection.anchor);
  }
  return cycleHeadingMultiLine(text, selection);
}

function cycleHeadingCollapsed(text: string, rawOffset: number): EditorValue {
  const offset = clamp(rawOffset, 0, text.length);
  const [lineStart, lineEnd] = lineBoundsAt(text, offset);
  const line = text.slice(lineStart, lineEnd);

  const level = headingLevel(line);
  const oldPrefixLen = level > 0 ? level + 1 : 0;
  const newPrefix = prefixForLevel(nextHeadingLevel(level));
  const newLine = newPrefix + line.slice(oldPrefixLen);
  const delta = newPrefix.length - oldPrefixLen;

  const newOffset = clamp(offset + delta, lineStart, lineStart + newLine.length);
  const newText = text.slice(0, lineStart) + newLine + text.slice(lineEnd);
  return { text: newText, selection: { anchor: newOffset, head: newOffset } };
}

interface HeadingLineEdit {
  ls: number;
  oldPrefixLen: number;
  newLine: string;
}

function cycleHeadingMultiLine(text: string, selection: EditorSelection): EditorValue {
  const start = Math.min(selection.anchor, selection.head);
  const end = Math.max(selection.anchor, selection.head);
  const anchorEnd = end > start ? end - 1 : end;

  const lineStarts = collectTouchedLineStarts(text, start, anchorEnd);

  const topLineEnd = lineBoundsAt(text, lineStarts[0])[1];
  const topLine = text.slice(lineStarts[0], topLineEnd);
  const targetPrefix = prefixForLevel(nextHeadingLevel(headingLevel(topLine)));

  const edits: HeadingLineEdit[] = lineStarts.map((ls) => {
    const lineEnd = lineBoundsAt(text, ls)[1];
    const line = text.slice(ls, lineEnd);
    const level = headingLevel(line);
    const oldPrefixLen = level > 0 ? level + 1 : 0;
    return { ls, oldPrefixLen, newLine: targetPrefix + line.slice(oldPrefixLen) };
  });

  let newText = text;
  for (let i = edits.length - 1; i >= 0; i--) {
    const edit = edits[i];
    const lineEnd = lineBoundsAt(newText, edit.ls)[1];
    newText = newText.slice(0, edit.ls) + edit.newLine + newText.slice(lineEnd);
  }

  const remap = (offset: number): number => {
    let shift = 0;
    for (const edit of edits) {
      const spliceStart = edit.ls;
      const spliceOldEnd = edit.ls + edit.oldPrefixLen;
      const delta = targetPrefix.length - edit.oldPrefixLen;
      if (offset <= spliceStart) {
        continue;
      } else if (offset >= spliceOldEnd) {
        shift += delta;
      } else {
        shift += spliceStart - offset;
      }
    }
    return offset + shift;
  };

  return {
    text: newText,
    selection: { anchor: remap(selection.anchor), head: remap(selection.head) },
  };
}
