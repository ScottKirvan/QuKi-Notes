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

// GFM's Autolink extension emits a leaf "URL" node for a bare http(s)/www/
// mailto/xmpp URL or a bare email address. It nests under an enclosing
// inline ancestor exactly like the NESTING_INLINE_TYPES above, but — being a
// leaf — never becomes an ancestor itself.
//
// The same node type also names a Link's or Image's own destination (the
// text inside its trailing parens), and the Autolink inline parser also
// fires inside a Link's label. Both are descendants of a Link/Image node, so
// walking up from the URL node and finding one there is how "is this a real
// bare autolink, not part of an existing link/image" gets decided — matching
// BEHAVIOR_SPEC.md's "not a nested link or autolink" rule for link labels,
// and avoiding a second, redundant element over the destination text a
// Link/Image element already collapses as a whole.
function hasLinkOrImageAncestor(node: SyntaxNode): boolean {
  for (let parent = node.parent; parent; parent = parent.parent) {
    if (parent.name === "Link" || parent.name === "Image") return true;
  }
  return false;
}

interface ListItemMarker {
  type: "BulletItem" | "OrderedItem" | "TaskItem";
  start: number;
  end: number;
  digit: number | null;
  checked?: boolean;
}

// A marker collapses only when nothing but whitespace precedes it on its
// line and a single space follows it; anything else (a `>` quote prefix,
// another item's marker on the same line, `-x`) stays literal text, which
// is also what keeps the checkbox tap's six-character rule from ever being
// asked to toggle something it would ignore.
function readListItemMarker(
  item: SyntaxNode,
  state: EditorState,
): ListItemMarker | null {
  const mark = item.getChild("ListMark");
  if (!mark) return null;

  const line = state.doc.lineAt(mark.from);
  if (!/^[ \t]*$/.test(state.sliceDoc(line.from, mark.from))) return null;
  if (state.sliceDoc(mark.to, mark.to + 1) !== " ") return null;

  const markText = state.sliceDoc(mark.from, mark.to);

  const taskMarker = item.getChild("Task")?.getChild("TaskMarker");
  if (
    taskMarker &&
    markText === "-" &&
    item.parent?.name === "BulletList" &&
    taskMarker.from === mark.to + 1 &&
    state.sliceDoc(taskMarker.to, taskMarker.to + 1) === " "
  ) {
    return {
      type: "TaskItem",
      start: mark.from,
      end: taskMarker.to + 1,
      digit: null,
      checked: state.sliceDoc(taskMarker.from + 1, taskMarker.from + 2) !== " ",
    };
  }

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
          const line = state.doc.lineAt(marker.start);
          const element: RevealElement = {
            id,
            type: marker.type,
            category: "block-marker",
            start: line.from,
            end: line.to,
            checkStart: line.from,
            checkEnd: marker.end,
            parentId: null,
            indentDepth: indentDepth(state.sliceDoc(line.from, marker.start)),
            ...(marker.checked !== undefined && { checked: marker.checked }),
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

      // A GFM table reveals wholly, like Image/HorizontalRule above (issue
      // #245) - but unlike them, its children (TableCell etc.) are never
      // walked: a cell's own nested formatting (bold, a link, ...) is
      // rendered by the table widget itself from the syntax tree
      // (tableModel.ts), not by the general inline reveal mechanism, so it
      // must not also surface here as independent inline elements that could
      // reveal on their own while the table around them stays collapsed, or
      // sit half-hidden by mark decorations while the table itself reveals.
      if (type === "Table") {
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
        return false;
      }

      if (type === "URL") {
        if (hasLinkOrImageAncestor(node.node)) {
          return true;
        }
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
