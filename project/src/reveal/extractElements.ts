import type { EditorState } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import type { SyntaxNode } from "@lezer/common";
import type { RevealElement } from "./types";

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

  return { elements, nodes };
}
