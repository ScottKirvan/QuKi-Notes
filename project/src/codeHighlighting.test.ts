import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { ensureSyntaxTree, getIndentation, IndentContext, indentOnInput } from "@codemirror/language";
import { insertNewlineAndIndent } from "@codemirror/commands";
import { highlightTree } from "@lezer/highlight";
import { codeHighlighter, CODE_TOKEN_CLASS_PREFIX, fencedCodeLines } from "./codeHighlighting";
import { findCodeLanguage } from "./codeLanguages";
import { markdownEditing } from "./markdownEditing";

async function stateWithLanguagesLoaded(doc: string, infos: string[]): Promise<EditorState> {
  for (const info of infos) await findCodeLanguage(info)?.load();
  const state = EditorState.create({ doc, extensions: [markdownEditing()] });
  ensureSyntaxTree(state, state.doc.length, 5000);
  return state;
}

function tokens(state: EditorState): Array<{ text: string; classes: string[] }> {
  const found: Array<{ text: string; classes: string[] }> = [];
  highlightTree(ensureSyntaxTree(state, state.doc.length, 5000)!, codeHighlighter, (from, to, classes) => {
    found.push({ text: state.sliceDoc(from, to), classes: classes.split(" ") });
  });
  return found;
}

function classOf(state: EditorState, text: string): string | undefined {
  return tokens(state)
    .find((token) => token.text === text)
    ?.classes.find((name) => name.startsWith(CODE_TOKEN_CLASS_PREFIX))
    ?.slice(CODE_TOKEN_CLASS_PREFIX.length);
}

describe("findCodeLanguage", () => {
  it.each([
    ["js", "JavaScript"],
    ["javascript", "JavaScript"],
    ["ts", "TypeScript"],
    ["py", "Python"],
    ["python", "Python"],
    ["sh", "Shell"],
    ["bash", "Shell"],
    ["json", "JSON"],
    ["md", "Markdown"],
    ["yml", "YAML"],
    ["html", "HTML"],
    ["css", "CSS"],
    ["dart", "Dart"],
    ["JS", "JavaScript"],
  ])("finds %s as %s", (info, name) => {
    expect(findCodeLanguage(info)?.name).toBe(name);
  });

  it.each(["", "nope", "text", "txt", "plain", "plaintext", "console"])("finds no language for %j", (info) => {
    expect(findCodeLanguage(info)).toBeNull();
  });
});

describe("code highlighting in fenced code blocks", () => {
  it("colours a js block's keyword, string, number and comment", async () => {
    const state = await stateWithLanguagesLoaded('```js\nconst x = "hi" + 1; // note\n```\n', ["js"]);
    expect(classOf(state, "const")).toBe("keyword");
    expect(classOf(state, '"hi"')).toBe("string");
    expect(classOf(state, "1")).toBe("value");
    expect(classOf(state, "// note")).toBe("comment");
  });

  it("colours a python block's keyword and function name", async () => {
    const state = await stateWithLanguagesLoaded("```py\ndef greet():\n    return 'hi'\n```\n", ["py"]);
    expect(classOf(state, "def")).toBe("keyword");
    expect(classOf(state, "greet")).toBe("function");
    expect(classOf(state, "'hi'")).toBe("string");
  });

  it("gives an unknown language's block, or one with no info string, no code colours", async () => {
    const state = await stateWithLanguagesLoaded('```nope\nconst x = "hi";\n```\n\n```\nconst y = 2;\n```\n', []);
    const coloured = tokens(state).filter((token) => token.classes.some((name) => name.startsWith(CODE_TOKEN_CLASS_PREFIX)));
    expect(coloured).toEqual([]);
  });

  it("never colours markdown's own tokens, fence marks and info string included", async () => {
    const state = await stateWithLanguagesLoaded("# Head **bold**\n\n```js\nlet a;\n```\n", ["js"]);
    const colouredText = tokens(state)
      .filter((token) => token.classes.some((name) => name.startsWith(CODE_TOKEN_CLASS_PREFIX)))
      .map((token) => token.text);
    expect(colouredText).toEqual(["let", ";"]);
  });
});

describe("fencedCodeLines", () => {
  function markedLineStarts(doc: string): number[] {
    const state = EditorState.create({ doc, extensions: [markdownEditing()] });
    ensureSyntaxTree(state, doc.length, 5000);
    const starts: number[] = [];
    fencedCodeLines(state).between(0, doc.length, (from) => {
      starts.push(from);
    });
    return starts;
  }

  it("marks every line of each fenced block, fences included, and no other line", () => {
    const doc = "plain\n\n```js\nlet a;\n```\nafter\n\n```\nb\n```";
    expect(markedLineStarts(doc)).toEqual([7, 13, 20, 31, 35, 37]);
  });

  it("marks an unclosed block down to the end of the QuKi", () => {
    expect(markedLineStarts("```js\nlet a;\nlet b;")).toEqual([0, 6, 13]);
  });

  it("marks nothing in a QuKi with no fenced block", () => {
    expect(markedLineStarts("a `code` span\n\n    indented code")).toEqual([]);
  });
});

describe("Enter inside a highlighted code block keeps today's indentation", () => {
  it("has no language indentation inside the block", async () => {
    const doc = "```js\nfunction f() {\n```\n";
    const state = await stateWithLanguagesLoaded(doc, ["js"]);
    const pos = doc.indexOf("{") + 1;
    expect(getIndentation(new IndentContext(state), pos)).toBeNull();
  });

  it("copies the line's own indentation on Enter instead of the language's", async () => {
    const doc = "```js\n  if (x) {\n```\n";
    const state = await stateWithLanguagesLoaded(doc, ["js"]);
    const pos = doc.indexOf("{") + 1;
    let next = state.update({ selection: { anchor: pos } }).state;
    insertNewlineAndIndent({ state: next, dispatch: (tr) => (next = tr.state) });
    expect(next.doc.toString()).toBe("```js\n  if (x) {\n  \n```\n");
  });

  it("does not re-indent the line when a closing bracket is typed", async () => {
    const doc = "```js\nif (x) {\n\t\t\n```\n";
    await findCodeLanguage("js")?.load();
    const at = doc.indexOf("\t\t") + 2;
    const state = EditorState.create({ doc, selection: { anchor: at }, extensions: [markdownEditing(), indentOnInput()] });
    ensureSyntaxTree(state, doc.length, 5000);
    const typed = state.update({ changes: { from: at, insert: "}" }, selection: { anchor: at + 1 }, userEvent: "input.type" }).state;
    expect(typed.doc.toString()).toBe("```js\nif (x) {\n\t\t}\n```\n");
  });
});
