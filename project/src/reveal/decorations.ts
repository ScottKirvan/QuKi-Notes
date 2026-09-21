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
import { listPrefixLength } from "./listPrefix";
import {
  BulletWidget,
  CheckboxWidget,
  HorizontalRuleWidget,
  ImageWidget,
  LinkWidget,
  OrderedMarkerWidget,
} from "./widgets";

function headingLevel(type: string): number {
  return Number(type.slice(-1));
}

const QUOTE_INDENT_PX = 16;
const QUOTE_BAR_WIDTH_PX = 3;
const QUOTE_BAR_INSET_PX = 4;

// One 3px bar per nesting level, level K at (K-1)*16+4px, with the content
// indented 16px per level — the Flutter editor's geometry. Consecutive quote
// lines' backgrounds meet, so a level's bar is continuous across the lines
// that share it.
function quoteLineStyle(depth: number): string {
  const bar = "linear-gradient(var(--blockquote-border-color), var(--blockquote-border-color))";
  const images: string[] = [];
  const sizes: string[] = [];
  const positions: string[] = [];
  for (let level = 1; level <= depth; level++) {
    images.push(bar);
    sizes.push(`${QUOTE_BAR_WIDTH_PX}px 100%`);
    positions.push(`${(level - 1) * QUOTE_INDENT_PX + QUOTE_BAR_INSET_PX}px 0`);
  }
  return [
    `padding-left:${depth * QUOTE_INDENT_PX}px`,
    `background-image:${images.join(",")}`,
    `background-size:${sizes.join(",")}`,
    `background-position:${positions.join(",")}`,
    "background-repeat:no-repeat",
  ].join(";");
}

const LIST_INDENT_PX = 16;
const LIST_MARKER_GUTTER_PX = 24;
// CodeMirror's own `.cm-line` left padding, which an inline padding-left
// replaces rather than adds to.
const EDITOR_LINE_INSET_PX = 6;

// A list line's marker widget fills the 24px gutter at the line's first row,
// so the first row is pulled back by the gutter while every wrapped row
// starts at the padding edge, directly under the content.
function listLineDecoration(depth: number): Decoration {
  const contentX =
    EDITOR_LINE_INSET_PX + depth * LIST_INDENT_PX + LIST_MARKER_GUTTER_PX;
  return Decoration.line({
    class: "cm-quki-list-line",
    attributes: {
      style: `padding-left:${contentX}px;text-indent:-${LIST_MARKER_GUTTER_PX}px`,
    },
  });
}

// A list-style line shown as raw source — revealed for editing, or never
// recognised by the parser — has no gutter to hang under, so its wrapped rows
// would fall back to the left margin. The class only marks the line; where
// the text starts depends on the font and on tab widths, so hangingIndent.ts
// measures that and sizes the float that pushes the wrapped rows over.
const hangLine = Decoration.line({ class: "cm-quki-hang" });

function rawListLineDecorations(
  state: EditorState,
  skipLines: ReadonlySet<number>,
): Range<Decoration>[] {
  const ranges: Range<Decoration>[] = [];
  for (let n = 1; n <= state.doc.lines; n++) {
    const line = state.doc.line(n);
    if (skipLines.has(line.from)) continue;
    if (listPrefixLength(line.text) === null) continue;
    ranges.push(hangLine.range(line.from));
  }
  return ranges;
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

const selectedCode = Decoration.mark({ class: "cm-quki-code-selected" });

// The selection is drawn in a layer behind the text and a collapsed code
// span's background is opaque, so it would hide a selection running through
// it; this marks the selected part so the stylesheet can paint over the chip.
function selectedCodeText(
  state: EditorState,
  node: SyntaxNode,
): Range<Decoration>[] {
  const marks = node.getChildren("CodeMark");
  if (marks.length < 2) return [];
  const textFrom = marks[0].to;
  const textTo = marks[marks.length - 1].from;
  const ranges: Range<Decoration>[] = [];
  for (const selected of state.selection.ranges) {
    const from = Math.max(selected.from, textFrom);
    const to = Math.min(selected.to, textTo);
    if (from < to) ranges.push(selectedCode.range(from, to));
  }
  return ranges;
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
  const nonHangingLines = new Set<number>();

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
            listLineDecoration(element.indentDepth ?? 0).range(element.start),
          );
          nonHangingLines.add(element.start);
        }
        break;

      case "TaskItem":
        if (!revealed) {
          ranges.push(
            Decoration.replace({
              widget: new CheckboxWidget(element.checked === true),
            }).range(element.checkStart, element.checkEnd),
            listLineDecoration(element.indentDepth ?? 0).range(element.start),
          );
          nonHangingLines.add(element.start);
        }
        if (element.checked && element.checkEnd < element.end) {
          ranges.push(
            Decoration.mark({ class: "cm-quki-checked-text" }).range(
              element.checkEnd,
              element.end,
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
            listLineDecoration(element.indentDepth ?? 0).range(element.start),
          );
          nonHangingLines.add(element.start);
        }
        break;

      case "BlockquoteLine": {
        if (element.checkEnd < element.end) {
          ranges.push(
            Decoration.mark({ class: "cm-quki-quote-text" }).range(
              element.checkEnd,
              element.end,
            ),
          );
        }
        if (!revealed) {
          ranges.push(
            Decoration.replace({}).range(element.checkStart, element.checkEnd),
          );
          ranges.push(
            Decoration.line({
              class: "cm-quki-quote",
              attributes: { style: quoteLineStyle(element.quoteDepth ?? 1) },
            }).range(element.start),
          );
        }
        break;
      }

      case "HorizontalRule": {
        nonHangingLines.add(state.doc.lineAt(element.start).from);
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
          ranges.push(...selectedCodeText(state, node));
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

  ranges.push(...rawListLineDecorations(state, nonHangingLines));

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
