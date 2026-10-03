import type { EditorValue, EditorSelection } from "./types";
import {
  clamp,
  collectTouchedLineStarts,
  detectListMarker,
  isHeadingLine,
  leadingWs,
  lineBoundsAt,
  type ListMarkerType,
} from "./lines";

const NEW_LIST_MARKER_TEXT: Record<ListMarkerType, string> = {
  unordered: "- ",
  ordered: "1. ",
  checkbox: "- [ ] ",
};

interface LineToggleEdit {
  newLine: string;
  wsLen: number;
  oldMarkerLen: number;
  newMarkerLen: number;
}

/**
 * Rewrites a line's list marker: removes it (when `remove` is true and the
 * line has one) or replaces whatever marker it has (or lacks) with
 * `targetType`'s. Heading lines are a no-op. The caller decides `remove` -
 * for a single line that's simply "does it already have this marker", but a
 * multi-line selection decides it once, uniformly, for every touched line
 * (see `applyListMarkerToggleMultiLine`).
 */
function applyMarkerToLine(line: string, targetType: ListMarkerType, remove: boolean): LineToggleEdit {
  if (isHeadingLine(line)) {
    return { newLine: line, wsLen: 0, oldMarkerLen: 0, newMarkerLen: 0 };
  }
  const match = detectListMarker(line);
  const wsLen = match ? match.wsLen : leadingWs(line).length;
  const ws = line.slice(0, wsLen);
  const oldMarkerLen = match?.markerLen ?? 0;
  const content = line.slice(wsLen + oldMarkerLen);

  const newMarker = remove ? "" : NEW_LIST_MARKER_TEXT[targetType];
  const newLine = ws + newMarker + content;
  return { newLine, wsLen, oldMarkerLen, newMarkerLen: newMarker.length };
}

/**
 * Converts a line's list marker to `targetType` in place, or removes it if
 * the line is already that type — "convert in place rather than stacking
 * markers" per BEHAVIOR_SPEC.md. Ported from markdown_editor.dart's
 * `_toggleLine`.
 */
function toggleLine(line: string, targetType: ListMarkerType): LineToggleEdit {
  const match = isHeadingLine(line) ? null : detectListMarker(line);
  return applyMarkerToLine(line, targetType, match?.type === targetType);
}

/** Ported from markdown_editor.dart's `_applyListMarkerToggle` (collapsed selection). */
function applyListMarkerToggleCollapsed(text: string, rawOffset: number, targetType: ListMarkerType): EditorValue {
  const offset = clamp(rawOffset, 0, text.length);
  const [lineStart, lineEnd] = lineBoundsAt(text, offset);
  const line = text.slice(lineStart, lineEnd);

  const edit = toggleLine(line, targetType);
  const delta = edit.newMarkerLen - edit.oldMarkerLen;
  const newOffset = clamp(offset + delta, lineStart, lineStart + edit.newLine.length);

  const newText = text.slice(0, lineStart) + edit.newLine + text.slice(lineEnd);
  return { text: newText, selection: { anchor: newOffset, head: newOffset } };
}

/**
 * Ported from markdown_editor.dart's `_applyListMarkerToggleMultiLine`
 * (range selection), but BEHAVIOR_SPEC.md §4 makes this a single uniform
 * decision, not each line's own toggleLine call: "if every touched line
 * already carries the marker being applied, the operation removes it from
 * all of them" — otherwise every touched line gets the marker, replacing
 * whatever marker (if any) it already had. Heading lines are excluded from
 * the touched-line set entirely (not merely no-op edited) and don't count
 * toward that "every line" decision; if that leaves no eligible lines the
 * whole operation is a no-op — unlike indent/dedent's multi-line case,
 * there is no "insert a tab" fallback here.
 */
function applyListMarkerToggleMultiLine(
  text: string,
  selection: EditorSelection,
  targetType: ListMarkerType,
): EditorValue {
  const start = Math.min(selection.anchor, selection.head);
  const end = Math.max(selection.anchor, selection.head);
  const anchorEnd = end > start ? end - 1 : end;

  const lineStarts = collectTouchedLineStarts(text, start, anchorEnd);
  const eligibleLines = lineStarts.filter((ls) => {
    const lineEnd = lineBoundsAt(text, ls)[1];
    return !isHeadingLine(text.slice(ls, lineEnd));
  });

  if (eligibleLines.length === 0) {
    return { text, selection: { ...selection } };
  }

  const allHaveMarker = eligibleLines.every((ls) => {
    const lineEnd = lineBoundsAt(text, ls)[1];
    return detectListMarker(text.slice(ls, lineEnd))?.type === targetType;
  });

  const edits = new Map<number, LineToggleEdit>();
  for (const ls of eligibleLines) {
    const lineEnd = lineBoundsAt(text, ls)[1];
    edits.set(ls, applyMarkerToLine(text.slice(ls, lineEnd), targetType, allHaveMarker));
  }

  let newText = text;
  for (let i = eligibleLines.length - 1; i >= 0; i--) {
    const ls = eligibleLines[i];
    const lineEnd = lineBoundsAt(newText, ls)[1];
    newText = newText.slice(0, ls) + edits.get(ls)!.newLine + newText.slice(lineEnd);
  }

  const remap = (offset: number): number => {
    let shift = 0;
    for (const ls of eligibleLines) {
      const edit = edits.get(ls)!;
      const spliceStart = ls + edit.wsLen;
      const spliceOldEnd = spliceStart + edit.oldMarkerLen;
      if (offset <= spliceStart) {
        continue;
      } else if (offset >= spliceOldEnd) {
        shift += edit.newMarkerLen - edit.oldMarkerLen;
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

function applyListToggle(value: EditorValue, targetType: ListMarkerType): EditorValue {
  const { text, selection } = value;
  if (selection.anchor === selection.head) {
    return applyListMarkerToggleCollapsed(text, selection.anchor, targetType);
  }
  return applyListMarkerToggleMultiLine(text, selection, targetType);
}

export function toggleUnorderedList(value: EditorValue): EditorValue {
  return applyListToggle(value, "unordered");
}

export function toggleOrderedList(value: EditorValue): EditorValue {
  return applyListToggle(value, "ordered");
}

export function toggleCheckboxList(value: EditorValue): EditorValue {
  return applyListToggle(value, "checkbox");
}
