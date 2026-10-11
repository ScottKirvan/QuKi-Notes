import { type EditorState, type Extension, RangeSetBuilder, StateField } from "@codemirror/state";
import { Decoration, type DecorationSet, EditorView } from "@codemirror/view";
import { languageDataProp, syntaxHighlighting, syntaxTree } from "@codemirror/language";
import { markdownLanguage } from "@codemirror/lang-markdown";
import { tagHighlighter, tags } from "@lezer/highlight";

export const CODE_TOKEN_CLASS_PREFIX = "cm-quki-tok-";
export const FENCED_LINE_CLASS = "cm-quki-fenced-line";

const token = (kind: string): string => `${CODE_TOKEN_CLASS_PREFIX}${kind}`;

/**
 * Token classes for code inside fenced code blocks, one per Obsidian code
 * colour variable (--code-keyword, --code-string, ...). Markdown's own tokens
 * never get one, fence marks included. style.css colours them only on a
 * FENCED_LINE_CLASS line: inline HTML in a paragraph is parsed by a nested
 * language too and gets these classes, but stays literal text.
 */
export const codeHighlighter = tagHighlighter(
  [
    { tag: [tags.keyword, tags.self], class: token("keyword") },
    { tag: [tags.operator, tags.definitionOperator], class: token("operator") },
    {
      tag: [tags.string, tags.special(tags.string), tags.regexp, tags.escape, tags.character, tags.attributeValue, tags.url],
      class: token("string"),
    },
    { tag: [tags.number, tags.bool, tags.null, tags.atom, tags.unit, tags.color, tags.literal], class: token("value") },
    { tag: tags.comment, class: token("comment") },
    {
      tag: [
        tags.function(tags.variableName),
        tags.function(tags.propertyName),
        tags.typeName,
        tags.className,
        tags.namespace,
        tags.macroName,
      ],
      class: token("function"),
    },
    { tag: [tags.propertyName, tags.attributeName, tags.labelName], class: token("property") },
    { tag: [tags.punctuation, tags.angleBracket, tags.contentSeparator], class: token("punctuation") },
    { tag: tags.tagName, class: token("tag") },
    { tag: [tags.modifier, tags.annotation, tags.meta, tags.processingInstruction], class: token("important") },
  ],
  { scope: (top) => top.prop(languageDataProp) !== markdownLanguage.data },
);

const fencedLine = Decoration.line({ class: FENCED_LINE_CLASS });

/**
 * Every line of every fenced code block, fences included, in both modes:
 * style.css colours code on these lines, and uncolours it in plain-text mode.
 */
export function fencedCodeLines(state: EditorState): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name !== "FencedCode") return true;
      const last = state.doc.lineAt(node.to).number;
      for (let n = state.doc.lineAt(node.from).number; n <= last; n++) {
        const from = state.doc.line(n).from;
        builder.add(from, from, fencedLine);
      }
      return false;
    },
  });
  return builder.finish();
}

const fencedCodeLinesField = StateField.define<DecorationSet>({
  create: fencedCodeLines,
  update(lines, tr) {
    return tr.docChanged || syntaxTree(tr.startState) !== syntaxTree(tr.state) ? fencedCodeLines(tr.state) : lines;
  },
  provide: (field) => EditorView.decorations.from(field),
});

export function codeHighlighting(): Extension {
  return [syntaxHighlighting(codeHighlighter), fencedCodeLinesField];
}
