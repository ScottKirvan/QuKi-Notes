import type { BlockContext, Line, MarkdownConfig } from "@lezer/markdown";

/*
 * The app indents with tabs, one tab per depth (BEHAVIOR_SPEC.md §12
 * Indentation), but CommonMark counts a tab as four columns, and a line indented
 * four columns past where a list item may start is not a list item: on the
 * first line, or after a blank line or a heading, it is an indented code block;
 * after a paragraph it is more of that paragraph. So `\t- item` on its own,
 * or under `text`, or two tabs under `- a`, parsed as code or as text.
 *
 * This extension makes such a line a list item anyway, exactly as it would be
 * with less indentation: where an indented code block could start, it starts
 * the list instead, and it ends a paragraph wherever the same marker unindented
 * would. The item and its list begin at the marker rather than at the start of
 * the line, as they do inside a parent item; Enter's list continuation
 * (@codemirror/lang-markdown) only reads spaces, never tabs, before an item's
 * start.
 *
 * Every other indented line is left as CommonMark has it.
 */

const SPACE_OR_END = /^(?:[ \t]|$)/;

function isHorizontalRule(line: Line): boolean {
  const rest = line.text.slice(line.pos);
  const char = rest[0];
  if (char !== "-" && char !== "*" && char !== "_") return false;
  let count = 0;
  for (const c of rest) {
    if (c === char) count++;
    else if (c !== " " && c !== "\t") return false;
  }
  return count >= 3;
}

interface Marker {
  list: "BulletList" | "OrderedList";
  size: number;
  number: string;
}

function listMarker(line: Line): Marker | null {
  const rest = line.text.slice(line.pos);
  const bullet = /^[-+*]/.exec(rest);
  if (bullet && SPACE_OR_END.test(rest.slice(1)) && !isHorizontalRule(line)) {
    return { list: "BulletList", size: 1, number: "" };
  }
  const ordered = /^(\d{1,9})[.)]/.exec(rest);
  if (ordered && SPACE_OR_END.test(rest.slice(ordered[0].length))) {
    return { list: "OrderedList", size: ordered[0].length, number: ordered[1]! };
  }
  return null;
}

function isIndentedPastCode(line: Line): boolean {
  return line.indent >= line.baseIndent + 4;
}

function inList(cx: BlockContext, list: Marker["list"]): boolean {
  for (let depth = cx.depth - 1; depth >= 0; depth--) {
    if (cx.parentType(depth).name === list) return true;
  }
  return false;
}

// CommonMark's rule for a list item that would end a paragraph: it cannot be
// empty, and a numbered one must be numbered 1, unless it continues a list.
function endsParagraph(cx: BlockContext, line: Line, marker: Marker): boolean {
  if (inList(cx, marker.list)) return true;
  const hasContent = line.skipSpace(line.pos + marker.size) < line.text.length;
  return hasContent && (marker.list === "BulletList" || marker.number === "1");
}

// The column an item's content starts at, the way @lezer/markdown works it out
// for an item it recognises itself.
function contentColumn(line: Line, afterMarker: number): number {
  const markerEnd = line.countIndent(afterMarker, line.pos, line.indent);
  const contentStart = line.skipSpace(afterMarker);
  const content = line.countIndent(contentStart, afterMarker, markerEnd);
  return content >= markerEnd + 5 || contentStart === line.text.length ? markerEnd + 1 : content;
}

export const IndentedListItems: MarkdownConfig = {
  parseBlock: [
    {
      name: "IndentedListItem",
      before: "IndentedCode",
      parse(cx, line) {
        if (!isIndentedPastCode(line)) return false;
        const marker = listMarker(line);
        if (!marker) return false;
        const markerChar = line.text.charCodeAt(line.pos + marker.size - 1);
        const column = contentColumn(line, line.pos + marker.size);
        cx.startComposite(marker.list, line.pos, markerChar);
        cx.startComposite("ListItem", line.pos, column - line.baseIndent);
        const from = cx.lineStart + line.pos;
        cx.addElement(cx.elt("ListMark", from, from + marker.size));
        line.moveBaseColumn(column);
        return null;
      },
      leaf() {
        return {
          nextLine(cx, line, leaf) {
            if (!isIndentedPastCode(line)) return false;
            const marker = listMarker(line);
            if (!marker || !endsParagraph(cx, line, marker)) return false;
            for (const parser of leaf.parsers) {
              if (parser !== this && parser.finish(cx, leaf)) return true;
            }
            cx.addLeafElement(
              leaf,
              cx.elt(
                "Paragraph",
                leaf.start,
                leaf.start + leaf.content.length,
                cx.parser.parseInline(leaf.content, leaf.start),
              ),
            );
            return true;
          },
          finish() {
            return false;
          },
        };
      },
    },
  ],
};
