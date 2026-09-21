import type { EditorState } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import type { SyntaxNode } from "@lezer/common";
import type { RevealElement } from "./types";
import { computeOrderedNumbers, indentDepth } from "./listNumbering";
import { quotePrefix } from "./quotePrefix";

const HEADING_TYPES = new Set([
  "ATXHeading1",
  "ATXHeading2",
  "ATXHeading3",
  "ATXHeading4",
  "ATXHeading5",
  "ATXHeading6",
]);

// Elements whose reveal unit nests (rule 1/2): the whole span is one raw
// unit, and an outer element's reveal absorbs everything inside it.
const NESTING_INLINE_TYPES = new Set([
  "StrongEmphasis",
  "Emphasis",
  "Strikethrough",
  "InlineCode",
  "Link",
]);

// Marker spans the whole line by definition (rule 4): reveal degenerates to
// the same start<=caret<=end check as any other element, just over the full
// node instead of a marker substring.
const WHOLE_LINE_TYPES = new Set(["Image", "HorizontalRule"]);

interface ListItemMarker {
  type: "BulletItem" | "OrderedItem";
  start: number;
  end: number;
  digit: number | null;
}

// Only a whole line's worth of leading whitespace may precede a list marker
// for it to collapse: anything else (a `>` quote prefix, another list's
// marker) leaves it as literal text.
function readListItemMarker(
  item: SyntaxNode,
  state: EditorState,
): ListItemMarker | null {
  const mark = item.getChild("ListMark");
  if (!mark) return null;
  if (item.getChild("Task")) return null;

  const line = state.doc.lineAt(mark.from);
  if (!/^[ \t]*$/.test(state.sliceDoc(line.from, mark.from))) return null;
  if (state.sliceDoc(mark.to, mark.to + 1) !== " ") return null;

  const markText = state.sliceDoc(mark.from, mark.to);
  if (item.parent?.name === "OrderedList") {
    if (!/^\d+\.$/.test(markText)) return null;
    return {
      type: "OrderedItem",
      start: mark.from,
      end: mark.to + 1,
      digit: Number.parseInt(markText, 10),
    };
  }
  if (markText === "-" || markText === "*" || markText === "+") {
    return { type: "BulletItem", start: mark.from, end: mark.to + 1, digit: null };
  }
  return null;
}

function assignOrderedNumbers(
  state: EditorState,
  ordered: { element: RevealElement; digit: number }[],
): void {
  if (ordered.length === 0) return;
  const digitByLine = new Map<number, number>();
  for (const { element, digit } of ordered) {
    digitByLine.set(state.doc.lineAt(element.start).number, digit);
  }
  const lines = [];
  for (let n = 1; n <= state.doc.lines; n++) {
    const text = state.doc.line(n).text;
    const indent = /^[ \t]*/.exec(text)?.[0] ?? "";
    lines.push({ depth: indentDepth(indent), digit: digitByLine.get(n) ?? null });
  }
  const numbers = computeOrderedNumbers(lines);
  for (const { element } of ordered) {
    const n = numbers[state.doc.lineAt(element.start).number - 1];
    if (n !== null && n !== undefined) element.orderedNumber = n;
  }
}

export interface ExtractResult {
  elements: RevealElement[];
  /**
   * Persistent SyntaxNode for each element id, for callers (decoration
   * building) that need to inspect an element's actual children — e.g. to
   * find the exact mark tokens to hide. The reveal-decision logic itself
   * never needs this; it's absent from RevealElement on purpose so
   * computeReveal.ts stays a plain data transform with no tree dependency.
   */
  nodes: Map<number, SyntaxNode>;
}

/**
 * Walk the document's markdown syntax tree and produce the flat list of
 * reveal candidates the reveal engine operates on.
 *
 * This is intentionally the only place that knows Lezer/@lezer/markdown
 * node names — computeReveal.ts works entirely in terms of RevealElement
 * and has no CodeMirror dependency.
 */
export function extractElements(state: EditorState): ExtractResult {
  const tree = syntaxTree(state);
  const elements: RevealElement[] = [];
  const nodes = new Map<number, SyntaxNode>();
  let nextId = 0;
  const inlineAncestorStack: number[] = [];
  const ordered: { element: RevealElement; digit: number }[] = [];

  tree.iterate({
    enter(node) {
      const type = node.name;

      if (HEADING_TYPES.has(type)) {
        const headerMark = node.node.getChild("HeaderMark");
        if (headerMark) {
          // The mandatory single space after the marker is part of the
          // marker span too (BEHAVIOR_SPEC.md worked example: "# A" reveals
          // the marker for a caret at offset 2, the boundary right after
          // the space).
          const markerLength = headerMark.to - headerMark.from + 1;
          const id = nextId++;
          elements.push({
            id,
            type,
            category: "block-marker",
            start: node.from,
            end: node.to,
            checkStart: node.from,
            checkEnd: node.from + markerLength,
            parentId: null,
          });
          nodes.set(id, node.node);
        }
        return true;
      }

      if (type === "QuoteMark") {
        const line = state.doc.lineAt(node.from);
        const prefix = node.from === line.from ? quotePrefix(line.text) : null;
        if (prefix) {
          const id = nextId++;
          elements.push({
            id,
            type: "BlockquoteLine",
            category: "block-marker",
            start: line.from,
            end: line.to,
            checkStart: line.from,
            checkEnd: line.from + prefix.length,
            parentId: null,
            quoteDepth: prefix.depth,
          });
          nodes.set(id, node.node);
        }
        return true;
      }

      if (type === "ListItem") {
        const marker = readListItemMarker(node.node, state);
        if (marker) {
          const id = nextId++;
          const element: RevealElement = {
            id,
            type: marker.type,
            category: "block-marker",
            start: marker.start,
            end: state.doc.lineAt(marker.start).to,
            checkStart: marker.start,
            checkEnd: marker.end,
            parentId: null,
          };
          elements.push(element);
          nodes.set(id, node.node);
          if (marker.digit !== null) ordered.push({ element, digit: marker.digit });
        }
        return true;
      }

      if (WHOLE_LINE_TYPES.has(type)) {
        const id = nextId++;
        elements.push({
          id,
          type,
          category: "block-marker",
          start: node.from,
          end: node.to,
          checkStart: node.from,
          checkEnd: node.to,
          parentId: null,
        });
        nodes.set(id, node.node);
        return true;
      }

      if (NESTING_INLINE_TYPES.has(type)) {
        const parentId =
          inlineAncestorStack.length > 0
            ? inlineAncestorStack[inlineAncestorStack.length - 1]
            : null;
        const id = nextId++;
        elements.push({
          id,
          type,
          category: "inline",
          start: node.from,
          end: node.to,
          checkStart: node.from,
          checkEnd: node.to,
          parentId,
        });
        nodes.set(id, node.node);
        inlineAncestorStack.push(id);
        return true;
      }

      return true;
    },
    leave(node) {
      if (NESTING_INLINE_TYPES.has(node.name)) {
        inlineAncestorStack.pop();
      }
    },
  });

  assignOrderedNumbers(state, ordered);

  return { elements, nodes };
}
