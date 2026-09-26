import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
} from "@codemirror/view";
import { StateField, type EditorState, type Range } from "@codemirror/state";
import type { SyntaxNode } from "@lezer/common";
import { extractElements } from "./extractElements";
import { computeRevealedIds, caretForReveal } from "./computeReveal";
import { plainTextMode } from "./plainTextMode";
import { editModeField, isEditMode } from "./editModeField";
import { listPrefixLength } from "./listPrefix";
import { buildTableModel } from "./tableModel";
import {
  BulletWidget,
  CheckboxWidget,
  HorizontalRuleWidget,
  ImageWidget,
  LinkWidget,
  OrderedMarkerWidget,
  TableWidget,
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

// The selection is drawn in a layer behind the text and a collapsed code
// span's background is opaque, so it would hide a selection running through
// it; this marks the selected part so the stylesheet can paint over the chip,
// and flags an end that reaches the chip's edge so the paint can also cover
// the chip's padding there.
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
    if (from >= to) continue;
    const classes = ["cm-quki-code-selected"];
    if (from === textFrom) classes.push("cm-quki-code-selected-start");
    if (to === textTo) classes.push("cm-quki-code-selected-end");
    ranges.push(Decoration.mark({ class: classes.join(" ") }).range(from, to));
  }
  return ranges;
}

// The Autolink extension's matched text carries its own scheme for
// http(s)/mailto/xmpp, but a bare "www." match and a bare email address have
// none — those two need a scheme prepended before the text is usable as an
// href.
function autolinkHref(raw: string): string {
  if (
    raw.startsWith("http://") ||
    raw.startsWith("https://") ||
    raw.startsWith("mailto:") ||
    raw.startsWith("xmpp:")
  ) {
    return raw;
  }
  if (raw.startsWith("www.")) {
    return `http://${raw}`;
  }
  return `mailto:${raw}`;
}

// Mirrors selectedCodeText's fix for InlineCode: the block's own background
// is opaque and sits in the text layer, above the (behind-text) selection
// layer, so it would otherwise hide a selection running through it. Unlike
// the inline chip, the block content carries no extra horizontal padding of
// its own, so no start/end edge case is needed - the plain mark covers
// exactly the selected characters.
function selectedCodeBlockText(
  state: EditorState,
  from: number,
  to: number,
): Range<Decoration>[] {
  const ranges: Range<Decoration>[] = [];
  for (const selected of state.selection.ranges) {
    const start = Math.max(selected.from, from);
    const end = Math.min(selected.to, to);
    if (start >= end) continue;
    ranges.push(Decoration.mark({ class: "cm-quki-code-selected" }).range(start, end));
  }
  return ranges;
}

// Collapses a fenced code block's opening and closing fence lines and
// backgrounds every line of the block, fence lines included. Only ever
// called when the block isn't revealed - see the "FencedCode" case below.
//
// Each fence line's marker text (and info string) is hidden in place,
// leaving the line's own newline untouched: CodeMirror refuses a decoration
// from a ViewPlugin (this reveal engine's decoration source) that replaces a
// line break - only a StateField may do that - so the fence line can't be
// erased outright the way a single-line marker can. Left blank and painted
// with the same background as the content lines, it reads as the top/bottom
// edge of one continuous block instead of a bare gap.
function fencedCodeDecorations(
  state: EditorState,
  node: SyntaxNode,
  nonHangingLines: Set<number>,
): Range<Decoration>[] {
  const marks = node.getChildren("CodeMark");
  if (marks.length < 2) return [];
  const openLine = state.doc.lineAt(marks[0]!.from);
  const closeLine = state.doc.lineAt(marks[marks.length - 1]!.from);

  const ranges: Range<Decoration>[] = [
    Decoration.replace({}).range(openLine.from, openLine.to),
    Decoration.replace({}).range(closeLine.from, closeLine.to),
  ];

  for (let n = openLine.number; n <= closeLine.number; n++) {
    const line = state.doc.line(n);
    ranges.push(Decoration.line({ class: "cm-quki-codeblock-line" }).range(line.from));
    nonHangingLines.add(line.from);
  }

  const contentFrom = openLine.to + 1;
  const contentTo = closeLine.from - 1;
  if (contentFrom < contentTo) {
    ranges.push(...selectedCodeBlockText(state, contentFrom, contentTo));
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
  // Rule 6's caret===null contract, reused here: outside real edit mode the
  // caret's position (main.ts's loadDocumentIntoEditor always resets it to
  // { anchor: 0 } on load, including for an existing QuKi opened straight
  // into reading mode) is not a meaningful editing position, so nothing
  // should reveal on account of it - every other decoration below (list
  // collapse, checkboxes, images, ...) still applies normally, since it
  // only depends on `revealed`, not on plain-text mode's separate
  // Decoration.none early return above.
  const caret = isEditMode(state) ? caretForReveal(state.selection.main) : null;
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

      case "URL": {
        if (!revealed) {
          const raw = state.sliceDoc(element.start, element.end);
          ranges.push(
            Decoration.replace({
              widget: new LinkWidget(raw, autolinkHref(raw)),
            }).range(element.start, element.end),
          );
        }
        break;
      }

      // Render-only, issue #245: the table renders as a real <table> widget
      // while collapsed and reverts wholly to raw source the moment the
      // caret enters it, same as Image/HorizontalRule above. Spans multiple
      // lines, so the replace decoration must be block-level.
      case "Table": {
        if (!revealed) {
          const model = buildTableModel(state, node);
          ranges.push(
            Decoration.replace({ widget: new TableWidget(model), block: true }).range(
              element.start,
              element.end,
            ),
          );
        }
        break;
      }

      case "FencedCode": {
        if (!revealed) {
          ranges.push(...fencedCodeDecorations(state, node, nonHangingLines));
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

// CodeMirror forbids a ViewPlugin from supplying block-level decorations
// (the table widget, spanning multiple lines, needs one) - only a StateField
// may. buildDecorations() itself stays the single pure source of truth (and
// what the test suite exercises directly); this just partitions its output
// for the two different extension points that actually register it with the
// live view. Written generically over any `block: true` spec, not
// table-specific, so another whole-element block widget added later needs no
// change here.
function splitByBlock(decorations: DecorationSet, docLength: number): { line: DecorationSet; block: DecorationSet } {
  const line: Range<Decoration>[] = [];
  const block: Range<Decoration>[] = [];
  decorations.between(0, docLength, (from, to, value) => {
    const isBlock = (value.spec as { block?: boolean }).block === true;
    (isBlock ? block : line).push(value.range(from, to));
  });
  return { line: Decoration.set(line, true), block: Decoration.set(block, true) };
}

function revealInputsChanged(prev: EditorState, next: EditorState): boolean {
  return (
    !prev.doc.eq(next.doc) ||
    !prev.selection.eq(next.selection) ||
    prev.field(plainTextMode) !== next.field(plainTextMode) ||
    prev.field(editModeField, false) !== next.field(editModeField, false)
  );
}

export const revealPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      this.decorations = splitByBlock(buildDecorations(view.state), view.state.doc.length).line;
    }

    update(update: ViewUpdate): void {
      if (revealInputsChanged(update.startState, update.state)) {
        this.decorations = splitByBlock(buildDecorations(update.state), update.state.doc.length).line;
      }
    }
  },
  {
    decorations: (instance) => instance.decorations,
  },
);

export const blockRevealField = StateField.define<DecorationSet>({
  create(state) {
    return splitByBlock(buildDecorations(state), state.doc.length).block;
  },
  update(value, tr) {
    if (!revealInputsChanged(tr.startState, tr.state)) return value;
    return splitByBlock(buildDecorations(tr.state), tr.state.doc.length).block;
  },
  provide: (field) => EditorView.decorations.from(field),
});
