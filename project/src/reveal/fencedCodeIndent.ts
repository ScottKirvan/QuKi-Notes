import type { EditorState, Extension } from "@codemirror/state";
import type { SyntaxNode } from "@lezer/common";
import { indentService, syntaxTree } from "@codemirror/language";

/**
 * The fenced-code feature's own contract is "no inline markdown parsing
 * inside the fence — content is literal" (BEHAVIOR_SPEC.md §12), but
 * CodeMirror's indent machinery doesn't know that on its own. Markdown's
 * Enter handler (`insertNewlineContinueMarkup`, bound ahead of the default
 * keymap) explicitly declines to act inside a FencedCode block and falls
 * through to `@codemirror/commands`' `insertNewlineAndIndent`. Finding no
 * indent rule for FencedCode in the syntax tree (markdown's own
 * `indentNodeProp` only covers `Document`), that command's `getIndentation`
 * call returns null, and its own documented fallback for null is "inherit
 * the indentation of the line above" — copying whatever leading whitespace
 * the *previous* line happened to have onto the new one, on every Enter
 * press. Typed content then lands with extra whitespace prepended each time
 * a broken line follows an indented one, compounding line over line, and in
 * the worst case drifting a closing fence past GFM's 3-space tolerance so it
 * never re-closes and swallows the rest of the document.
 *
 * Registering a zero-indent `indentService` for any position inside a
 * FencedCode node overrides that fallback outright: a line broken there
 * never gets synthetic indentation, so what the user types is exactly what
 * lands — the same "type it, get exactly that back" contract a plain
 * paragraph already has. Deferring (returning `undefined`) everywhere else
 * leaves markdown's own list/blockquote indent behavior untouched.
 */
function isInsideFencedCode(state: EditorState, pos: number): boolean {
  const tree = syntaxTree(state);
  for (const side of [-1, 1] as const) {
    for (let node: SyntaxNode | null = tree.resolveInner(pos, side); node; node = node.parent) {
      if (node.name === "FencedCode") return true;
    }
  }
  return false;
}

export const fencedCodeNoIndent: Extension = indentService.of((context, pos) =>
  isInsideFencedCode(context.state, pos) ? 0 : undefined,
);
