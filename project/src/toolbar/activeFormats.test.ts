import { describe, expect, it } from "vitest";
import { ensureSyntaxTree } from "@codemirror/language";
import { markdown } from "@codemirror/lang-markdown";
import { EditorState } from "@codemirror/state";
import { GFM } from "@lezer/markdown";

import { IndentedListItems } from "../indentedListItems";
import { activeFormats } from "./activeFormats";

/** `^` marks the caret; `{` and `}` mark a selection (anchor then head). */
function formatsAt(marked: string): string[] {
  let doc = marked;
  let anchor: number;
  let head: number;
  if (doc.includes("{")) {
    anchor = doc.indexOf("{");
    doc = doc.replace("{", "");
    head = doc.indexOf("}");
    doc = doc.replace("}", "");
  } else {
    anchor = head = doc.indexOf("^");
    doc = doc.replace("^", "");
  }
  const state = EditorState.create({
    doc,
    selection: { anchor, head },
    extensions: [markdown({ extensions: [GFM, IndentedListItems], addKeymap: false })],
  });
  ensureSyntaxTree(state, doc.length, 5000);
  return [...activeFormats(state)].sort();
}

describe("inline formats", () => {
  it("given a caret inside bold text, then bold is active", () => {
    expect(formatsAt("a **bo^ld** b")).toEqual(["bold"]);
  });

  it.each(["*", "_"])("given a caret inside %s italic text, then italic is active", (m) => {
    expect(formatsAt(`a ${m}it^alic${m} b`)).toEqual(["italic"]);
  });

  it("given __double underscore__ bold, then bold is active", () => {
    expect(formatsAt("__bo^ld__")).toEqual(["bold"]);
  });

  it("given a caret inside strikethrough, then strikethrough is active", () => {
    expect(formatsAt("~~go^ne~~")).toEqual(["strikethrough"]);
  });

  it("given a caret inside inline code, then code is active", () => {
    expect(formatsAt("`co^de`")).toEqual(["code"]);
  });

  it("given a caret in plain text, then nothing is active", () => {
    expect(formatsAt("pl^ain **bold**")).toEqual([]);
  });

  it("given bold inside italic, then both are active in the inner span and only italic in the outer", () => {
    expect(formatsAt("_a **b^b** c_")).toEqual(["bold", "italic"]);
    expect(formatsAt("_a ^**bb** c_")).toEqual(["italic"]);
  });

  it("given ***both***, then bold and italic are active", () => {
    expect(formatsAt("***bo^th***")).toEqual(["bold", "italic"]);
  });

  it("given code inside bold, then both are active, and bold markers inside code do not count", () => {
    expect(formatsAt("**a `c^` b**")).toEqual(["bold", "code"]);
    expect(formatsAt("`**x^**`")).toEqual(["code"]);
  });

  it("given escaped markers, then no format is active", () => {
    expect(formatsAt("\\*\\*no^t\\*\\*")).toEqual([]);
    expect(formatsAt("\\*no^t\\*")).toEqual([]);
  });

  it("given an unclosed marker, then nothing is active", () => {
    expect(formatsAt("**unclo^sed")).toEqual([]);
  });

  describe("caret at a boundary", () => {
    it("given a caret just before the opening marker or just after the closing one, then the format is not active", () => {
      expect(formatsAt("^**bold**")).toEqual([]);
      expect(formatsAt("**bold**^")).toEqual([]);
    });

    it("given a caret just inside either marker, then the format is active, as typing there continues it", () => {
      expect(formatsAt("**^bold**")).toEqual(["bold"]);
      expect(formatsAt("**bold^**")).toEqual(["bold"]);
    });

    it("given the empty pair a Bold press inserts, then the caret between them is bold", () => {
      expect(formatsAt("**^**")).toEqual(["bold"]);
    });

    it("given a caret between the two characters of a real marker, then no empty pair is read from it", () => {
      expect(formatsAt("a **b*^* c")).toEqual([]);
      expect(formatsAt("a *^*b** c")).toEqual([]);
      expect(formatsAt("_a **b**^_")).toEqual(["italic"]);
    });

    it("given a caret inside a longer run of markers, then no empty pair is read from it", () => {
      expect(formatsAt("***^***")).toEqual([]);
    });

    it("given an empty pair inside inline code or a code fence, then it is not a format", () => {
      expect(formatsAt("`a **^** b`")).toEqual(["code"]);
      expect(formatsAt("```\n**^**\n```")).toEqual([]);
    });

    it.each([["a ~~^~~ b", "strikethrough"], ["_^_", "italic"], ["`^`", "code"], ["a __^__ b", "bold"]])(
      "given the empty pair %s, then %s is active",
      (marked, format) => {
        expect(formatsAt(marked)).toEqual([format]);
      },
    );
  });

  describe("a range selection", () => {
    it("given a selection inside one span, then its format is active", () => {
      expect(formatsAt("**b{ol}d**")).toEqual(["bold"]);
    });

    it("given a selection of the whole content, then the format is active", () => {
      expect(formatsAt("**{bold}**")).toEqual(["bold"]);
    });

    it("given a selection that includes the markers, then the format is not active", () => {
      expect(formatsAt("{**bold**}")).toEqual([]);
    });

    it("given a selection running out of the span, then the format is not active", () => {
      expect(formatsAt("**bo{ld** x}")).toEqual([]);
      expect(formatsAt("x {a **bo}ld**")).toEqual([]);
    });

    it("given a backwards selection inside the span, then the format is active", () => {
      expect(formatsAt("**b}ol{d**")).toEqual(["bold"]);
    });

    it("given a selection across two separate bold spans, then bold is not active", () => {
      expect(formatsAt("**a{a** and **b}b**")).toEqual([]);
    });
  });
});

describe("line formats", () => {
  it.each(["-", "*", "+"])("given a %s item, then unordered is active", (bullet) => {
    expect(formatsAt(`${bullet} ap^ple`)).toEqual(["unordered"]);
  });

  it("given an ordered item, then ordered is active", () => {
    expect(formatsAt("12. ap^ple")).toEqual(["ordered"]);
  });

  it.each(["- [ ] todo", "- [x] done"])("given a task item %s, then task is active and unordered is not", (line) => {
    expect(formatsAt(`${line}^`)).toEqual(["task"]);
  });

  it("given an indented item, then it is active at any depth", () => {
    expect(formatsAt("- a\n    - b^")).toEqual(["unordered"]);
    expect(formatsAt("1. a\n\t1. b^")).toEqual(["ordered"]);
  });

  it("given a heading of any level 1 to 6, then heading is active", () => {
    for (let n = 1; n <= 6; n++) expect(formatsAt(`${"#".repeat(n)} ti^tle`)).toEqual(["heading"]);
  });

  it("given a hash with no space or seven hashes, then heading is not active", () => {
    expect(formatsAt("#no^space")).toEqual([]);
    expect(formatsAt("####### se^ven")).toEqual([]);
  });

  it("given a heading line inside a fenced code block, then heading is not active", () => {
    expect(formatsAt("```\n# not^ a heading\n```")).toEqual([]);
  });

  it("given a plain paragraph line, then no line format is active", () => {
    expect(formatsAt("hello ^world")).toEqual([]);
  });

  it("given a marker with no following space, then it is not a list line", () => {
    expect(formatsAt("-^x")).toEqual([]);
  });

  it("given an empty item that has only its marker and space, then the list is active", () => {
    expect(formatsAt("- ^")).toEqual(["unordered"]);
  });

  it("given a wrapped continuation line of an item, then it is not a list line", () => {
    expect(formatsAt("- first\n  cont^inued")).toEqual([]);
  });

  it("given a list inside a quote, then it is not a list line, as the list buttons do not act on it", () => {
    expect(formatsAt("> - qu^oted")).toEqual([]);
  });

  it("given bold inside a list item or heading, then both the line and the inline format are active", () => {
    expect(formatsAt("- a **b^** c")).toEqual(["bold", "unordered"]);
    expect(formatsAt("## a *i^* c")).toEqual(["heading", "italic"]);
  });

  it("given bold inside a quote or table cell, then bold is active", () => {
    expect(formatsAt("> a **b^**")).toEqual(["bold"]);
    expect(formatsAt("| h |\n| - |\n| **b^** |")).toEqual(["bold"]);
  });

  describe("a range selection", () => {
    it("given a selection over lines that are all the same list type, then it is active", () => {
      expect(formatsAt("- {a\n- b\n- c}")).toEqual(["unordered"]);
    });

    it("given a selection over a list line and a plain line, then nothing is active", () => {
      expect(formatsAt("- {a\nplain}")).toEqual([]);
    });

    it("given a selection over an unordered and an ordered line, then nothing is active", () => {
      expect(formatsAt("- {a\n1. b}")).toEqual([]);
    });

    it("given a selection ending at the very start of the next line, then that line is not counted", () => {
      expect(formatsAt("- {a\n}plain")).toEqual(["unordered"]);
    });

    it("given a selection over several heading lines, then heading is active", () => {
      expect(formatsAt("# {a\n## b}")).toEqual(["heading"]);
    });
  });
});
