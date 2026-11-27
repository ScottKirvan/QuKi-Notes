import { syntaxTree } from "@codemirror/language";
import type { EditorState } from "@codemirror/state";
import type { SyntaxNode } from "@lezer/common";

import { headingLevel } from "./lines";

/** The formats a toolbar button can show as active. */
export type ActiveFormat = "bold" | "italic" | "strikethrough" | "code" | "heading" | "unordered" | "ordered" | "task";

/** Inline formats: the syntax node that carries them and the child that marks each end. */
const INLINE_FORMATS: Record<string, { format: ActiveFormat; mark: string }> = {
  StrongEmphasis: { format: "bold", mark: "EmphasisMark" },
  Emphasis: { format: "italic", mark: "EmphasisMark" },
  Strikethrough: { format: "strikethrough", mark: "StrikethroughMark" },
  InlineCode: { format: "code", mark: "CodeMark" },
};

function markdownContentBounds(node: SyntaxNode, markName: string): [number, number] | null {
  const first = node.firstChild;
  const last = node.lastChild;
  if (!first || !last || first === last || first.name !== markName || last.name !== markName) return null;
  return [first.to, last.from];
}

/**
 * Inline formats that wrap the whole range [from, to]. A format is active
 * only when the range sits between the node's opening and closing marks
 * (ends included, so a caret right after the opening mark or right before
 * the closing one is inside, which is where typing would continue the
 * format; a caret in front of the opening mark, in the marks themselves, or
 * after the closing mark is not). A range reaching across the end of a
 * format is not covered by it. The walk goes through every ancestor, so
 * bold inside italic reports both, and inside a heading, list, quote,
 * link or table cell it works the same. An escaped or unclosed marker never
 * becomes a node in the tree, so it never counts.
 */
function inlineFormatsAt(state: EditorState, from: number, to: number): Set<ActiveFormat> {
  const found = new Set<ActiveFormat>();
  for (let node: SyntaxNode | null = syntaxTree(state).resolveInner(from, 0); node; node = node.parent) {
    const spec = INLINE_FORMATS[node.name];
    if (!spec) continue;
    const bounds = markdownContentBounds(node, spec.mark);
    if (bounds && from >= bounds[0] && to <= bounds[1]) found.add(spec.format);
  }
  return found;
}

const MARK_NODES = new Set(["EmphasisMark", "StrikethroughMark", "CodeMark"]);

const EMPTY_PAIRS: [string, ActiveFormat][] = [
  ["**", "bold"],
  ["__", "bold"],
  ["~~", "strikethrough"],
  ["*", "italic"],
  ["_", "italic"],
  ["`", "code"],
];

/**
 * A collapsed caret between a just-inserted empty delimiter pair, such as
 * `**|**`. The markdown parser makes no span out of an empty pair, but it is
 * exactly what the toolbar buttons insert with nothing selected, so the
 * button must read as pressed there. The pair must be a whole run: a longer
 * run of the same character (`***|***`) is left to the parser.
 */
function emptyPairAt(state: EditorState, pos: number, found: Set<ActiveFormat>): void {
  const tree = syntaxTree(state);
  // Markers the parser did pair up (a caret between the two characters of a
  // real closing `**`, say) are not an empty pair.
  for (const side of [-1, 1] as const) {
    if (MARK_NODES.has(tree.resolveInner(pos, side).name)) return;
  }
  const line = state.doc.lineAt(pos);
  const before = state.sliceDoc(line.from, pos);
  const after = state.sliceDoc(pos, line.to);
  for (const [pair, format] of EMPTY_PAIRS) {
    if (found.has(format)) continue;
    if (!before.endsWith(pair) || !after.startsWith(pair)) continue;
    const char = pair[0]!;
    if (before[before.length - pair.length - 1] === char || after[pair.length] === char) continue;
    for (let node: SyntaxNode | null = tree.resolveInner(pos, 0); node; node = node.parent) {
      if (node.name === "InlineCode" || node.name === "FencedCode" || node.name === "CodeBlock") return;
    }
    found.add(format);
  }
}

type ListFormat = "unordered" | "ordered" | "task";

/**
 * The list format of the line starting at `lineFrom`, or null. Same marker
 * rules as the toolbar's list buttons act on and as reveal collapses: the
 * marker leads the line (only whitespace before it, so `> - a` is not a
 * list line to the buttons), one space follows it, a task is `- [ ]` with a
 * `-` bullet. Only the line carrying the marker counts, not a wrapped or
 * continuation line of the same item.
 */
function listFormatOfLine(state: EditorState, lineFrom: number, lineText: string): ListFormat | null {
  const indent = /^[ \t]*/.exec(lineText)![0].length;
  const mark = syntaxTree(state).resolveInner(lineFrom + indent, 1);
  if (mark.name !== "ListMark" || mark.from !== lineFrom + indent) return null;
  const item = mark.parent;
  if (!item || item.name !== "ListItem") return null;
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
    return "task";
  }
  if (item.parent?.name === "OrderedList") return /^\d+\.$/.test(markText) ? "ordered" : null;
  return markText === "-" || markText === "*" || markText === "+" ? "unordered" : null;
}

function isHeadingLine(state: EditorState, lineFrom: number, lineText: string): boolean {
  if (headingLevel(lineText) === 0) return false;
  for (let node: SyntaxNode | null = syntaxTree(state).resolveInner(lineFrom, 1); node; node = node.parent) {
    if (/^ATXHeading[1-6]$/.test(node.name)) return true;
  }
  return false;
}

/**
 * The formats active at the main selection, read from the editor's syntax
 * tree. Inline formats (bold, italic, strikethrough, code) are active when
 * the selection sits inside one such span. Line formats (heading, the three
 * lists) are active when every line the selection touches has it, where a
 * selection that ends at the very start of a line does not touch that line,
 * the same lines the toolbar's list buttons act on. Pure: no DOM, no state
 * outside the argument.
 */
export function activeFormats(state: EditorState): Set<ActiveFormat> {
  const { from, to } = state.selection.main;
  const active = inlineFormatsAt(state, from, to);
  if (from === to) emptyPairAt(state, from, active);

  const firstLine = state.doc.lineAt(from);
  const lastLine = state.doc.lineAt(to > from ? to - 1 : to);
  let allHeadings = true;
  let sharedList: ListFormat | null | undefined;
  for (let n = firstLine.number; n <= lastLine.number; n++) {
    const line = state.doc.line(n);
    if (!isHeadingLine(state, line.from, line.text)) allHeadings = false;
    const list = listFormatOfLine(state, line.from, line.text);
    sharedList = sharedList === undefined || sharedList === list ? list : null;
  }
  if (allHeadings) active.add("heading");
  if (sharedList) active.add(sharedList);
  return active;
}
