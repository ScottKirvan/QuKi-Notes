import type { Extension } from "@codemirror/state";
import { indentService, LanguageDescription, syntaxTree } from "@codemirror/language";
import { languages } from "@codemirror/language-data";
import type { SyntaxNode } from "@lezer/common";

/**
 * The language a fenced code block's info string names, matched by name,
 * alias or file extension (`py`, `md`), case-insensitively. language-data
 * lists `text` as a LaTeX file extension, so the usual plain-text names are
 * caught first.
 */
const PLAIN_TEXT_NAMES = new Set(["text", "txt", "plain", "plaintext"]);

export function findCodeLanguage(info: string): LanguageDescription | null {
  const name = info.trim().toLowerCase();
  if (name === "" || PLAIN_TEXT_NAMES.has(name)) return null;
  return (
    LanguageDescription.matchLanguageName(languages, name, false) ??
    languages.find((language) => language.extensions.some((extension) => extension.toLowerCase() === name)) ??
    null
  );
}

/**
 * A loaded code language would otherwise indent Enter and re-indent typed
 * brackets by its own rules; inside a fenced code block Enter keeps copying
 * the line's own indentation, as it did before blocks were highlighted.
 */
export const fencedCodeKeepsLineIndentation: Extension = indentService.of((context, pos) => {
  for (let node: SyntaxNode | null = syntaxTree(context.state).resolveInner(pos, -1); node; node = node.parent) {
    if (node.name === "FencedCode") return null;
  }
  return undefined;
});
