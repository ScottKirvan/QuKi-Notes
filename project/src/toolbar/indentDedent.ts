import type { EditorValue, EditorSelection } from "./types";
import { collectTouchedLineStarts, isHeadingLine, lineBoundsAt } from "./lines";

/**
 * Ported from indent_dedent.dart's `_LineKind`: `list` and `paragraph` are
 * eligible for indent/dedent; `excluded` (blockquote, block image, heading)
 * takes a tab at the cursor on indent and is a no-op on dedent;
 * `excludedHr` (horizontal rule) is a no-op in both directions.
 */
type LineKind = "list" | "paragraph" | "excluded" | "excludedHr";

function isDigit(ch: string): boolean {
  const code = ch.charCodeAt(0);
  return code >= 0x30 && code <= 0x39;
}

function isOlLine(line: string): boolean {
  let i = 0;
  while (i < line.length && isDigit(line[i])) i++;
  if (i === 0) return false;
  return i + 1 < line.length && line[i] === "." && line[i + 1] === " ";
}

function isHrLine(line: string): boolean {
  if (line.length === 0) return false;
  const first = line[0];
  const hrChar = first === "-" || first === "*" || first === "_" ? first : null;
  if (hrChar === null) return false;
  let count = 0;
  for (const c of line) {
    if (c === hrChar) {
      count++;
    } else if (c === " ") {
      continue;
    } else {
      return false;
    }
  }
  return count >= 3;
}

function isBlockImageLine(line: string): boolean {
  if (!line.startsWith("![")) return false;
  if (!line.endsWith(")")) return false;
  const lastOpen = line.lastIndexOf("(");
  return lastOpen >= 2;
}

/**
 * [depth, wsLen] — the width-2-per-tab indent model: a tab counts as width
 * 2, a space as width 1, and depth is width / 2 (rounded down).
 */
function lineIndent(line: string): [number, number] {
  let width = 0;
  let i = 0;
  while (i < line.length && (line[i] === " " || line[i] === "\t")) {
    width += line[i] === "\t" ? 2 : 1;
    i++;
  }
  return [Math.floor(width / 2), i];
}

function classifyLine(line: string): LineKind {
  const [, wsLen] = lineIndent(line);
  const remainder = wsLen > 0 ? line.slice(wsLen) : line;

  if (wsLen > 0) {
    if (remainder.startsWith("- [ ] ") || remainder.startsWith("- [x] ") || remainder.startsWith("- [X] ")) {
      return "list";
    }
    if (
      !isHrLine(remainder) &&
      (remainder.startsWith("- ") || remainder.startsWith("* ") || remainder.startsWith("+ "))
    ) {
      return "list";
    }
    if (isOlLine(remainder)) return "list";
    return "paragraph";
  }

  if (line.startsWith("- [ ] ") || line.startsWith("- [x] ") || line.startsWith("- [X] ")) {
    return "list";
  }
  if (isHrLine(line)) return "excludedHr";
  if (line.startsWith(">")) return "excluded";
  if (line.startsWith("- ") || line.startsWith("* ") || line.startsWith("+ ")) return "list";
  if (isBlockImageLine(line)) return "excluded";
  if (isOlLine(line)) return "list";
  if (isHeadingLine(line)) return "excluded";
  return "paragraph";
}

/** Removes up to width 2 of leading indentation (a tab or two spaces' worth). */
function dedentWidthLen(line: string): number {
  let removedWidth = 0;
  let i = 0;
  while (i < line.length && (line[i] === " " || line[i] === "\t") && removedWidth < 2) {
    removedWidth += line[i] === "\t" ? 2 : 1;
    i++;
  }
  return i;
}

function removedLenForDedent(line: string, kind: LineKind): number {
  switch (kind) {
    case "list": {
      const [depth] = lineIndent(line);
      if (depth === 0) return 0;
      return dedentWidthLen(line);
    }
    case "paragraph":
      return line.startsWith("\t") ? 1 : 0;
    case "excluded":
    case "excludedHr":
      return 0;
  }
}

/** Ported from indent_dedent.dart's `applyIndent`. */
export function applyIndent(value: EditorValue): EditorValue {
  const { text, selection } = value;
  if (selection.anchor === selection.head) {
    return indentCollapsed(text, selection.anchor);
  }
  return indentOrDedentSelection(text, selection, true);
}

/** Ported from indent_dedent.dart's `applyDedent`. */
export function applyDedent(value: EditorValue): EditorValue {
  const { text, selection } = value;
  if (selection.anchor === selection.head) {
    return dedentCollapsed(text, selection.anchor);
  }
  return indentOrDedentSelection(text, selection, false);
}

function indentCollapsed(text: string, offset: number): EditorValue {
  const [lineStart, lineEnd] = lineBoundsAt(text, offset);
  const line = text.slice(lineStart, lineEnd);
  const kind = classifyLine(line);

  if (kind === "excludedHr") {
    return { text, selection: { anchor: offset, head: offset } };
  }

  if (kind === "excluded") {
    const newText = text.slice(0, offset) + "\t" + text.slice(offset);
    return { text: newText, selection: { anchor: offset + 1, head: offset + 1 } };
  }

  const newText = text.slice(0, lineStart) + "\t" + text.slice(lineStart);
  return { text: newText, selection: { anchor: offset + 1, head: offset + 1 } };
}

function dedentCollapsed(text: string, offset: number): EditorValue {
  const [lineStart, lineEnd] = lineBoundsAt(text, offset);
  const line = text.slice(lineStart, lineEnd);
  const kind = classifyLine(line);

  if (kind === "excluded" || kind === "excludedHr") {
    return { text, selection: { anchor: offset, head: offset } };
  }

  const removedLen = removedLenForDedent(line, kind);
  if (removedLen === 0) {
    return { text, selection: { anchor: offset, head: offset } };
  }

  const newText = text.slice(0, lineStart) + text.slice(lineStart + removedLen);
  const shifted = offset - removedLen;
  const newOffset = shifted < lineStart ? lineStart : shifted;
  return { text: newText, selection: { anchor: newOffset, head: newOffset } };
}

function indentOrDedentSelection(text: string, selection: EditorSelection, indent: boolean): EditorValue {
  const start = Math.min(selection.anchor, selection.head);
  const end = Math.max(selection.anchor, selection.head);
  const anchorEnd = end > start ? end - 1 : end;

  const lineStarts = collectTouchedLineStarts(text, start, anchorEnd);
  const eligibleLines = lineStarts.filter((ls) => {
    const lineEnd = lineBoundsAt(text, ls)[1];
    const kind = classifyLine(text.slice(ls, lineEnd));
    return kind !== "excluded" && kind !== "excludedHr";
  });

  if (eligibleLines.length === 0) {
    if (!indent) {
      return { text, selection: { ...selection } };
    }
    const newText = text.slice(0, start) + "\t" + text.slice(end);
    return { text: newText, selection: { anchor: start + 1, head: start + 1 } };
  }

  let newText = text;
  const deltas = new Map<number, number>();
  for (let i = eligibleLines.length - 1; i >= 0; i--) {
    const ls = eligibleLines[i];
    const lineEnd = lineBoundsAt(newText, ls)[1];
    const line = newText.slice(ls, lineEnd);
    if (indent) {
      newText = newText.slice(0, ls) + "\t" + newText.slice(ls);
      deltas.set(ls, 1);
    } else {
      const removedLen = removedLenForDedent(line, classifyLine(line));
      if (removedLen > 0) {
        newText = newText.slice(0, ls) + newText.slice(ls + removedLen);
      }
      deltas.set(ls, -removedLen);
    }
  }

  const remap = (offset: number): number => {
    let shift = 0;
    for (const ls of eligibleLines) {
      const delta = deltas.get(ls)!;
      if (delta > 0) {
        if (offset >= ls) shift += delta;
      } else if (delta < 0) {
        const removedLen = -delta;
        if (offset >= ls + removedLen) {
          shift += delta;
        } else if (offset > ls) {
          shift -= offset - ls;
        }
      }
    }
    return offset + shift;
  };

  return {
    text: newText,
    selection: { anchor: remap(selection.anchor), head: remap(selection.head) },
  };
}
