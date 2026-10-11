import { syntaxTree } from "@codemirror/language";
import type { EditorState, Extension, Range } from "@codemirror/state";
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from "@codemirror/view";

// CodeMirror turns all three off by default; these are what an ordinary
// text field gets, so the platform's own spellchecker underlines misspellings
// and an Android keyboard capitalises sentences and autocorrects as the user
// has it set up to.
const editorTextFieldAttributes = EditorView.contentAttributes.of({
  spellcheck: "true",
  autocorrect: "on",
  autocapitalize: "sentences",
});

const noSpellcheck = { attributes: { spellcheck: "false" } };
const noSpellcheckMark = Decoration.mark(noSpellcheck);
const noSpellcheckLine = Decoration.line(noSpellcheck);

export function codeSpellcheckExclusions(state: EditorState): DecorationSet {
  const ranges: Range<Decoration>[] = [];
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name === "InlineCode") {
        ranges.push(noSpellcheckMark.range(node.from, node.to));
        return false;
      }
      if (node.name === "FencedCode") {
        const last = state.doc.lineAt(node.to).number;
        for (let n = state.doc.lineAt(node.from).number; n <= last; n++) {
          ranges.push(noSpellcheckLine.range(state.doc.line(n).from));
        }
        return false;
      }
      return undefined;
    },
  });
  return Decoration.set(ranges, true);
}

const codeSpellcheckPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      this.decorations = codeSpellcheckExclusions(view.state);
    }

    update(update: ViewUpdate): void {
      if (update.docChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) {
        this.decorations = codeSpellcheckExclusions(update.state);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

export function spellcheck(): Extension {
  return [editorTextFieldAttributes, codeSpellcheckPlugin];
}
