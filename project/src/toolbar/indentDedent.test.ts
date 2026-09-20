import { describe, expect, it } from "vitest";

import { applyDedent, applyIndent } from "./indentDedent";
import type { EditorValue } from "./types";

function v(text: string, anchor: number, head = anchor): EditorValue {
  return { text, selection: { anchor, head } };
}

// Ported from indent_dedent_test.dart. MdParser-based assertions (depth via
// the markdown parser, ordered-list renumbering) are not ported — this
// chunk is pure text/offset logic with no markdown parser dependency.

describe("applyIndent — collapsed cursor, list items", () => {
  function checkIndentPreservesRelativeCursor(description: string, source: string, contentOffset: number) {
    it(`${description}: cursor at content offset ${contentOffset} shifts by exactly the inserted marker length`, () => {
      const result = applyIndent(v(source, contentOffset));
      expect(result.text).toBe(`\t${source}`);
      expect(result.selection).toEqual({ anchor: contentOffset + 1, head: contentOffset + 1 });
    });
  }

  checkIndentPreservesRelativeCursor("ul, cursor at content start", "- item", 2);
  checkIndentPreservesRelativeCursor("ul, cursor at content middle", "- item", 4);
  checkIndentPreservesRelativeCursor("ul, cursor at content end", "- item", 6);

  checkIndentPreservesRelativeCursor("ol, cursor at content start", "1. item", 3);
  checkIndentPreservesRelativeCursor("ol, cursor at content middle", "1. item", 5);
  checkIndentPreservesRelativeCursor("ol, cursor at content end", "1. item", 7);

  checkIndentPreservesRelativeCursor("checkbox unchecked, cursor at content start", "- [ ] item", 6);
  checkIndentPreservesRelativeCursor("checkbox unchecked, cursor at content middle", "- [ ] item", 8);
  checkIndentPreservesRelativeCursor("checkbox unchecked, cursor at content end", "- [ ] item", 10);

  checkIndentPreservesRelativeCursor("checkbox checked, cursor at content start", "- [x] item", 6);
  checkIndentPreservesRelativeCursor("checkbox checked, cursor at content middle", "- [x] item", 8);
  checkIndentPreservesRelativeCursor("checkbox checked, cursor at content end", "- [x] item", 10);

  it("checkbox unchecked survives indent (state unchanged)", () => {
    const result = applyIndent(v("- [ ] item", 8));
    expect(result.text).toBe("\t- [ ] item");
  });

  it("checkbox checked survives indent (state unchanged)", () => {
    const result = applyIndent(v("- [x] item", 8));
    expect(result.text).toBe("\t- [x] item");
  });

  it("multiple consecutive indents nest a list item arbitrarily deep", () => {
    let value: EditorValue = v("- item", 4);
    for (let i = 0; i < 5; i++) {
      value = applyIndent(value);
    }
    expect(value.text).toBe("\t\t\t\t\t- item");
  });
});

describe("applyDedent — collapsed cursor, list items", () => {
  it("dedenting a depth-1 ul line returns to depth 0", () => {
    const result = applyDedent(v("\t- item", 5));
    expect(result.text).toBe("- item");
  });

  it("dedenting a 2-space-indented ul line returns to depth 0", () => {
    const result = applyDedent(v("  - item", 6));
    expect(result.text).toBe("- item");
  });

  it("dedent at level 0 is a no-op — text and selection are unchanged", () => {
    const value = v("- item", 4);
    const result = applyDedent(value);
    expect(result.text).toBe(value.text);
    expect(result.selection).toEqual(value.selection);
  });

  it("checkbox checked state survives dedent", () => {
    const result = applyDedent(v("\t- [x] item", 9));
    expect(result.text).toBe("- [x] item");
  });

  it("checkbox unchecked state survives dedent", () => {
    const result = applyDedent(v("\t- [ ] item", 9));
    expect(result.text).toBe("- [ ] item");
  });

  it("indent then dedent round-trips back to the original text", () => {
    const original = "- item";
    const indented = applyIndent(v(original, 4));
    const dedented = applyDedent(indented);
    expect(dedented.text).toBe(original);
    expect(dedented.selection).toEqual({ anchor: 4, head: 4 });
  });
});

describe("applyIndent / applyDedent — plain paragraph lines", () => {
  it(
    "Indent on a plain paragraph inserts a literal tab at the line start, not at the " +
      "cursor — deliberate divergence from the previously-shipped at-cursor Tab insert",
    () => {
      const result = applyIndent(v("hello world", 5));
      expect(result.text).toBe("\thello world");
      expect(result.selection).toEqual({ anchor: 6, head: 6 });
    },
  );

  it("Dedent removes a leading literal tab from a paragraph line", () => {
    const result = applyDedent(v("\thello world", 6));
    expect(result.text).toBe("hello world");
    expect(result.selection).toEqual({ anchor: 5, head: 5 });
  });

  it("Dedent on a paragraph with no leading tab is a no-op", () => {
    const value = v("hello world", 5);
    const result = applyDedent(value);
    expect(result.text).toBe(value.text);
    expect(result.selection).toEqual(value.selection);
  });

  it("Indent on a blank line inserts a tab at its start", () => {
    const result = applyIndent(v("", 0));
    expect(result.text).toBe("\t");
    expect(result.selection).toEqual({ anchor: 1, head: 1 });
  });
});

describe("applyIndent / applyDedent — headings and blockquotes (excluded)", () => {
  it("Indent on a heading line inserts a tab AT THE CURSOR, matching pre-existing Tab behaviour", () => {
    const result = applyIndent(v("# my heading", 5));
    expect(result.text).toBe("# my \theading");
    expect(result.selection).toEqual({ anchor: 6, head: 6 });
  });

  it("Dedent on a heading line is a no-op", () => {
    const value = v("# my heading", 5);
    const result = applyDedent(value);
    expect(result.text).toBe(value.text);
    expect(result.selection).toEqual(value.selection);
  });

  it("Indent on a blockquote line inserts a tab AT THE CURSOR", () => {
    const result = applyIndent(v("> quoted text", 4));
    expect(result.text).toBe("> qu\toted text");
    expect(result.selection).toEqual({ anchor: 5, head: 5 });
  });

  it("Dedent on a blockquote line is a no-op", () => {
    const value = v("> quoted text", 4);
    const result = applyDedent(value);
    expect(result.text).toBe(value.text);
    expect(result.selection).toEqual(value.selection);
  });

  it("Indent with an active (non-collapsed) selection inside a heading replaces the selection", () => {
    const result = applyIndent(v("# hello world", 2, 7));
    expect(result.text).toBe("# \t world");
  });
});

describe("applyIndent / applyDedent — block images (excluded)", () => {
  it("Indent on a block-image line inserts a tab AT THE CURSOR", () => {
    const result = applyIndent(v("![alt](path.png)", 5));
    expect(result.text).toBe("![alt\t](path.png)");
    expect(result.selection).toEqual({ anchor: 6, head: 6 });
  });

  it("Dedent on a block-image line is a no-op", () => {
    const value = v("![alt](path.png)", 5);
    const result = applyDedent(value);
    expect(result.text).toBe(value.text);
    expect(result.selection).toEqual(value.selection);
  });
});

describe("applyIndent / applyDedent — horizontal rules (excluded, no-op)", () => {
  it("Indent on an hr line is a no-op", () => {
    const value = v("---", 1);
    const result = applyIndent(value);
    expect(result.text).toBe(value.text);
    expect(result.selection).toEqual(value.selection);
  });

  it("Dedent on an hr line is a no-op", () => {
    const value = v("---", 1);
    const result = applyDedent(value);
    expect(result.text).toBe(value.text);
    expect(result.selection).toEqual(value.selection);
  });
});

describe("applyIndent / applyDedent — multi-line selections", () => {
  it("selection spanning list items at different depths shifts each by one level", () => {
    const source = "- top\n  - sub\n- top2";
    const result = applyIndent(v(source, 0, source.length));
    expect(result.text).toBe("\t- top\n\t  - sub\n\t- top2");
  });

  it(
    "selection spanning a heading, a list item, and a paragraph: heading is left " +
      "alone, list item depth changes, paragraph gets a line-start tab",
    () => {
      const source = "# Heading\n- item\nparagraph";
      const result = applyIndent(v(source, 0, source.length));
      expect(result.text).toBe("# Heading\n\t- item\n\tparagraph");
    },
  );

  it(
    "selection touching zero eligible lines (heading + blockquote only) falls back " +
      "to the pre-existing selection-replace-with-tab behaviour",
    () => {
      const source = "# Heading\n> Quote";
      const result = applyIndent(v(source, 0, source.length));
      expect(result.text).toBe("\t");
      expect(result.selection).toEqual({ anchor: 1, head: 1 });
    },
  );

  it("Dedent on a selection touching zero eligible lines is a no-op", () => {
    const source = "# Heading\n> Quote";
    const value = v(source, 0, source.length);
    const result = applyDedent(value);
    expect(result.text).toBe(value.text);
    expect(result.selection).toEqual(value.selection);
  });

  it(
    "selection touching zero eligible lines (hr + block image only) falls back to " +
      "the tab-replace behaviour — confirms hr/image are ineligible too",
    () => {
      const source = "---\n![alt](path.png)";
      const result = applyIndent(v(source, 0, source.length));
      expect(result.text).toBe("\t");
      expect(result.selection).toEqual({ anchor: 1, head: 1 });
    },
  );

  it("Dedent on a multi-line list selection dedents each eligible line independently, clamping at level 0", () => {
    const source = "- top\n  - sub";
    const result = applyDedent(v(source, 0, source.length));
    expect(result.text).toBe("- top\n- sub");
  });

  it("selection endpoints remap correctly across a multi-line indent", () => {
    const source = "- top\n- bottom";
    const result = applyIndent(v(source, 2, 11));
    expect(result.text).toBe("\t- top\n\t- bottom");
    expect(result.selection).toEqual({ anchor: 3, head: 13 });
  });
});
