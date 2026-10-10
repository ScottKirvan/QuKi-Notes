import { ChangeSet, type EditorState, type StateCommand, type Transaction } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import { insertNewlineContinueMarkupCommand } from "@codemirror/lang-markdown";
import type { SyntaxNode } from "@lezer/common";

const continueMarkup = insertNewlineContinueMarkupCommand({ nonTightLists: false });

function containerColumn(state: EditorState, node: SyntaxNode): number {
  return node.from - state.doc.lineAt(node.from).from;
}

// The whitespace before an item that has no enclosing item or quote, when the
// caret's line continues it. The continuation command writes the new line's
// indentation from the enclosing items' columns, so for such an item (one
// indentedListItems.ts starts at its marker, after the tabs) it writes none.
function uncoveredIndent(state: EditorState, pos: number): string {
  const line = state.doc.lineAt(pos);
  const containers: SyntaxNode[] = [];
  for (let node: SyntaxNode | null = syntaxTree(state).resolveInner(pos, -1); node; node = node.parent) {
    if (node.name === "FencedCode") return "";
    if (node.name === "ListItem" || node.name === "Blockquote") containers.unshift(node);
  }
  while (containers.length > 0 && containerColumn(state, containers[containers.length - 1]!) > pos - line.from) {
    containers.pop();
  }
  if (containers.length !== 1 || containers[0]!.name !== "ListItem") return "";
  const item = containers[0]!;
  const lead = state.sliceDoc(state.doc.lineAt(item.from).from, item.from);
  return /^[ \t]*$/.test(lead) ? lead : "";
}

function withIndentRestored(state: EditorState, tr: Transaction): Transaction {
  const insertions: { from: number; insert: string }[] = [];
  for (const range of state.selection.ranges) {
    const indent = uncoveredIndent(state, range.head);
    if (indent === "") continue;
    const lineFrom = state.doc.lineAt(range.head).from;
    tr.changes.iterChanges((fromA, toA, fromB, _toB, inserted) => {
      if (fromA < lineFrom || toA > range.head) return;
      const text = inserted.toString();
      const lastBreak = text.lastIndexOf(state.lineBreak);
      if (lastBreak < 0) return;
      insertions.push({ from: fromB + lastBreak + state.lineBreak.length, insert: indent });
    });
  }
  if (insertions.length === 0) return tr;
  const extra = ChangeSet.of(insertions, tr.newDoc.length, state.lineBreak);
  return state.update({
    changes: tr.changes.compose(extra),
    selection: tr.selection?.map(extra),
    scrollIntoView: true,
    userEvent: "input",
  });
}

/**
 * Enter in a list or quote (BEHAVIOR_SPEC.md §4 list auto-continue):
 * @codemirror/lang-markdown's continuation, configured so that an empty item
 * always ends the list (or moves out a level) instead of first turning a
 * tight list loose, and keeping the indentation before an item that has no
 * enclosing item.
 */
export const continueListOnEnter: StateCommand = ({ state, dispatch }) =>
  continueMarkup({ state, dispatch: (tr) => dispatch(withIndentRestored(state, tr)) });
