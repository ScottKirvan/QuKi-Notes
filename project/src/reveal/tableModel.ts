import type { EditorState } from "@codemirror/state";
import type { SyntaxNode } from "@lezer/common";

/**
 * Pure conversion from a GFM `Table` syntax node to a plain-data model the
 * table widget (widgets.ts) renders from. Kept separate from decorations.ts
 * so it can be unit-tested without touching CodeMirror's view/DOM layer -
 * the same split extractElements.ts/computeReveal.ts already use.
 *
 * This is render-only: it produces exactly what's needed to draw the
 * collapsed table (issue #245). It does not attempt to normalise a
 * malformed table (ragged row lengths, a column count mismatch between the
 * header and the delimiter row) - it renders whatever cells the syntax tree
 * actually produced for each row.
 */

export type TableAlign = "left" | "center" | "right" | null;

export type InlineSpan =
  | { kind: "text"; text: string }
  | { kind: "strong"; children: InlineSpan[] }
  | { kind: "em"; children: InlineSpan[] }
  | { kind: "strike"; children: InlineSpan[] }
  | { kind: "code"; text: string }
  | { kind: "link"; url: string; children: InlineSpan[] };

export interface TableCellModel {
  align: TableAlign;
  spans: InlineSpan[];
}

export interface TableRowModel {
  cells: TableCellModel[];
}

export interface TableModel {
  align: TableAlign[];
  header: TableRowModel;
  rows: TableRowModel[];
}

const DELIMITER_CELL = /^:?-+:?$/;

/**
 * Parses a GFM delimiter row's raw text (e.g. `|:---------|:-----:|------:|`)
 * into one alignment per column. A malformed segment (doesn't match the
 * delimiter shape) yields `null`, the same as a plain `---` with no colons.
 */
export function parseTableAlignment(delimiterText: string): TableAlign[] {
  const trimmed = delimiterText.trim().replace(/^\|/, "").replace(/\|$/, "");
  return trimmed.split("|").map((raw) => {
    const segment = raw.trim();
    if (!DELIMITER_CELL.test(segment)) return null;
    const left = segment.startsWith(":");
    const right = segment.endsWith(":");
    if (left && right) return "center";
    if (right) return "right";
    if (left) return "left";
    return null;
  });
}

// Same inline-formatting node kinds extractElements.ts recognises elsewhere
// in the document (NESTING_INLINE_TYPES plus the bare-autolink URL type) -
// everything a table cell's own already-parsed subtree can contain.
const FORMATTING_TYPES = new Set([
  "StrongEmphasis",
  "Emphasis",
  "Strikethrough",
  "InlineCode",
  "Link",
  "URL",
]);

// Mirrors decorations.ts's own autolinkHref: a bare "www." match or email
// address carries no scheme of its own. Kept as a small local copy rather
// than a shared import so this module and decorations.ts's reveal switch
// (touched by a sibling change in parallel) don't collide on the same lines.
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

function directChildrenWithin(node: SyntaxNode, from: number, to: number): SyntaxNode[] {
  const result: SyntaxNode[] = [];
  for (let child = node.firstChild; child; child = child.nextSibling) {
    if (child.from >= from && child.to <= to && FORMATTING_TYPES.has(child.name)) {
      result.push(child);
    }
  }
  return result;
}

function buildSpans(state: EditorState, node: SyntaxNode, from: number, to: number): InlineSpan[] {
  const spans: InlineSpan[] = [];
  let pos = from;
  for (const child of directChildrenWithin(node, from, to)) {
    if (child.from > pos) {
      spans.push({ kind: "text", text: state.sliceDoc(pos, child.from) });
    }
    spans.push(buildSpan(state, child));
    pos = child.to;
  }
  if (pos < to) {
    spans.push({ kind: "text", text: state.sliceDoc(pos, to) });
  }
  return spans;
}

function wrappedContentRange(node: SyntaxNode, markType: string): { from: number; to: number } {
  const marks = node.getChildren(markType);
  if (marks.length < 2) return { from: node.from, to: node.to };
  return { from: marks[0]!.to, to: marks[marks.length - 1]!.from };
}

function buildSpan(state: EditorState, node: SyntaxNode): InlineSpan {
  switch (node.name) {
    case "StrongEmphasis": {
      const { from, to } = wrappedContentRange(node, "EmphasisMark");
      return { kind: "strong", children: buildSpans(state, node, from, to) };
    }
    case "Emphasis": {
      const { from, to } = wrappedContentRange(node, "EmphasisMark");
      return { kind: "em", children: buildSpans(state, node, from, to) };
    }
    case "Strikethrough": {
      const { from, to } = wrappedContentRange(node, "StrikethroughMark");
      return { kind: "strike", children: buildSpans(state, node, from, to) };
    }
    case "InlineCode": {
      const { from, to } = wrappedContentRange(node, "CodeMark");
      return { kind: "code", text: state.sliceDoc(from, to) };
    }
    case "Link": {
      const marks = node.getChildren("LinkMark");
      const urlNode = node.getChild("URL");
      const from = marks.length >= 1 ? marks[0]!.to : node.from;
      const to = marks.length >= 2 ? marks[1]!.from : node.to;
      const url = urlNode ? state.sliceDoc(urlNode.from, urlNode.to) : "";
      return { kind: "link", url, children: buildSpans(state, node, from, to) };
    }
    case "URL": {
      const raw = state.sliceDoc(node.from, node.to);
      return { kind: "link", url: autolinkHref(raw), children: [{ kind: "text", text: raw }] };
    }
    default:
      return { kind: "text", text: state.sliceDoc(node.from, node.to) };
  }
}

function buildRow(state: EditorState, rowNode: SyntaxNode | null, align: TableAlign[]): TableRowModel {
  if (!rowNode) return { cells: [] };
  const cells = rowNode.getChildren("TableCell").map((cell, index) => ({
    align: align[index] ?? null,
    spans: buildSpans(state, cell, cell.from, cell.to),
  }));
  return { cells };
}

// @lezer/markdown's GFM Table extension's row-continuation parsing is
// permissive to a fault (confirmed directly against its source,
// TableParser.nextLine in @lezer/markdown/dist/index.js): once a table is
// recognised, EVERY following non-blank line becomes another TableRow
// unconditionally, with no re-check that it still looks like one - even a
// line with no pipe character at all. So a table immediately followed by an
// ordinary paragraph, with no blank line between them, gets that paragraph
// silently absorbed as bogus extra rows. Nothing in @lezer/markdown or
// @codemirror/lang-markdown configures this, and the parser's own row/pipe
// helpers aren't exported, so it's corrected here: a genuine row needs at
// least one pipe to delimit its cells, and row-taking stops at the first
// line that has none - not a filter, since a later coincidental pipe further
// down must not un-truncate the table once a real break has been found.
function isGenuineRow(state: EditorState, row: SyntaxNode): boolean {
  return state.sliceDoc(row.from, row.to).includes("|");
}

export function genuineTableRows(state: EditorState, table: SyntaxNode): SyntaxNode[] {
  const rows: SyntaxNode[] = [];
  for (const row of table.getChildren("TableRow")) {
    if (!isGenuineRow(state, row)) break;
    rows.push(row);
  }
  return rows;
}

/**
 * Where the table actually ends once any bogus trailing rows (see
 * genuineTableRows above) are excluded: the end of the last genuine row, or
 * the delimiter row if the table has no genuine body rows at all.
 */
export function tableRealEnd(state: EditorState, table: SyntaxNode): number {
  const rows = genuineTableRows(state, table);
  if (rows.length > 0) return rows[rows.length - 1]!.to;
  const delimiter = table.getChild("TableDelimiter");
  return delimiter ? delimiter.to : table.to;
}

/**
 * Builds the render model for one `Table` syntax node. `table` must be a
 * node named `"Table"` from the GFM Table extension's tree shape: a
 * `TableHeader`, one direct-child `TableDelimiter` (the alignment row), and
 * zero or more `TableRow` children - only the genuine ones (see
 * genuineTableRows) are rendered; any bogus trailing rows are excluded so
 * this always agrees with tableRealEnd, which extractElements.ts uses for
 * the element's own span.
 */
export function buildTableModel(state: EditorState, table: SyntaxNode): TableModel {
  const delimiter = table.getChild("TableDelimiter");
  const align = delimiter ? parseTableAlignment(state.sliceDoc(delimiter.from, delimiter.to)) : [];
  const header = buildRow(state, table.getChild("TableHeader"), align);
  const rows = genuineTableRows(state, table).map((row) => buildRow(state, row, align));
  return { align, header, rows };
}
