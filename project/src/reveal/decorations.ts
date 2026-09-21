import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
} from "@codemirror/view";
import type { EditorState, Range } from "@codemirror/state";
import type { SyntaxNode } from "@lezer/common";
import { extractElements } from "./extractElements";
import { computeRevealedIds, caretForReveal } from "./computeReveal";
import { plainTextMode } from "./plainTextMode";
import {
  BulletWidget,
  HorizontalRuleWidget,
  ImageWidget,
  LinkWidget,
  OrderedMarkerWidget,
} from "./widgets";

function headingLevel(type: string): number {
  return Number(type.slice(-1));
}

function hideMarksAndStyle(
  ranges: Range<Decoration>[],
  node: SyntaxNode,
  markType: string,
  className: string,
): void {
  const marks = node.getChildren(markType);
  if (marks.length < 2) return;
  const open = marks[0];
  const close = marks[marks.length - 1];
  ranges.push(Decoration.replace({}).range(open.from, open.to));
  ranges.push(Decoration.replace({}).range(close.from, close.to));
  if (open.to < close.from) {
    ranges.push(
      Decoration.mark({ class: className }).range(open.to, close.from),
    );
  }
}

function readLabelAndUrl(
  node: SyntaxNode,
  state: EditorState,
): { label: string; url: string } {
  // Both Link and Image share this shape: LinkMark("[" or "!["), label
  // content, LinkMark("]"), LinkMark("("), URL, LinkMark(")").
  const marks = node.getChildren("LinkMark");
  const urlNode = node.getChild("URL");
  const label =
    marks.length >= 2 ? state.sliceDoc(marks[0].to, marks[1].from) : "";
  const url = urlNode ? state.sliceDoc(urlNode.from, urlNode.to) : "";
  return { label, url };
}

export function buildDecorations(state: EditorState): DecorationSet {
  if (state.field(plainTextMode)) {
    // Rule 6: plain-text mode reveals nothing and collapses nothing — the
    // whole buffer is raw source with no decorations at all.
    return Decoration.none;
  }

  const { elements, nodes } = extractElements(state);
  const caret = caretForReveal(state.selection.main);
  const revealedIds = computeRevealedIds(elements, caret);

  const ranges: Range<Decoration>[] = [];

  for (const element of elements) {
    const node = nodes.get(element.id);
    if (!node) continue;
    const revealed = revealedIds.has(element.id);

    switch (element.type) {
      case "ATXHeading1":
      case "ATXHeading2":
      case "ATXHeading3":
      case "ATXHeading4":
      case "ATXHeading5":
      case "ATXHeading6": {
        const level = headingLevel(element.type);
        ranges.push(
          Decoration.mark({
            class: `cm-quki-heading cm-quki-heading-${level}`,
          }).range(element.start, element.end),
        );
        if (!revealed) {
          ranges.push(
            Decoration.replace({}).range(element.checkStart, element.checkEnd),
          );
        }
        break;
      }

      case "BulletItem":
        if (!revealed) {
          ranges.push(
            Decoration.replace({ widget: new BulletWidget() }).range(
              element.checkStart,
              element.checkEnd,
            ),
          );
        }
        break;

      case "OrderedItem":
        if (!revealed && element.orderedNumber !== undefined) {
          ranges.push(
            Decoration.replace({
              widget: new OrderedMarkerWidget(element.orderedNumber),
            }).range(element.checkStart, element.checkEnd),
          );
        }
        break;

      case "HorizontalRule": {
        if (!revealed) {
          ranges.push(
            Decoration.replace({ widget: new HorizontalRuleWidget() }).range(
              element.start,
              element.end,
            ),
          );
        }
        break;
      }

      case "Image": {
        if (!revealed) {
          const { label, url } = readLabelAndUrl(node, state);
          ranges.push(
            Decoration.replace({ widget: new ImageWidget(label, url) }).range(
              element.start,
              element.end,
            ),
          );
        }
        break;
      }

      case "StrongEmphasis":
        if (!revealed) {
          hideMarksAndStyle(ranges, node, "EmphasisMark", "cm-quki-strong");
        }
        break;

      case "Emphasis":
        if (!revealed) {
          hideMarksAndStyle(ranges, node, "EmphasisMark", "cm-quki-em");
        }
        break;

      case "Strikethrough":
        if (!revealed) {
          hideMarksAndStyle(
            ranges,
            node,
            "StrikethroughMark",
            "cm-quki-strike",
          );
        }
        break;

      case "InlineCode":
        if (!revealed) {
          hideMarksAndStyle(ranges, node, "CodeMark", "cm-quki-code");
        }
        break;

      case "Link": {
        if (!revealed) {
          const { label, url } = readLabelAndUrl(node, state);
          ranges.push(
            Decoration.replace({ widget: new LinkWidget(label, url) }).range(
              element.start,
              element.end,
            ),
          );
        }
        break;
      }

      default:
        break;
    }
  }

  return Decoration.set(ranges, true);
}

export const revealPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      this.decorations = buildDecorations(view.state);
    }

    update(update: ViewUpdate): void {
      const plainTextChanged =
        update.startState.field(plainTextMode) !==
        update.state.field(plainTextMode);
      if (update.docChanged || update.selectionSet || plainTextChanged) {
        this.decorations = buildDecorations(update.state);
      }
    }
  },
  {
    decorations: (instance) => instance.decorations,
  },
);
