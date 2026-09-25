import { describe, expect, it } from "vitest";

import { cycleHeading, nextHeadingLevel } from "./heading";
import type { EditorValue } from "./types";

function v(text: string, anchor: number, head = anchor): EditorValue {
  return { text, selection: { anchor, head } };
}

// Direct coverage of the exported transition rule itself, independent of
// cycleHeading's text-splicing - this is what screens/formattingToolbar.ts's
// icon computation now relies on too.
describe("nextHeadingLevel", () => {
  it("normal (0) -> H1 (1)", () => {
    expect(nextHeadingLevel(0)).toBe(1);
  });

  it("H1 (1) -> H2 (2)", () => {
    expect(nextHeadingLevel(1)).toBe(2);
  });

  it("H2 (2) -> H3 (3)", () => {
    expect(nextHeadingLevel(2)).toBe(3);
  });

  it("H3 (3) -> normal (0)", () => {
    expect(nextHeadingLevel(3)).toBe(0);
  });

  it("H4 (4) -> normal (0)", () => {
    expect(nextHeadingLevel(4)).toBe(0);
  });

  it("H5 (5) -> normal (0)", () => {
    expect(nextHeadingLevel(5)).toBe(0);
  });

  it("H6 (6) -> normal (0)", () => {
    expect(nextHeadingLevel(6)).toBe(0);
  });
});

// New behavior — no Dart source or test to port (see the [Proposed —
// unconfirmed] note in heading.ts for the multi-line "topmost line"
// interpretation this pins down).
describe("cycleHeading — single line", () => {
  it("normal -> H1", () => {
    const result = cycleHeading(v("my heading", 5));
    expect(result.text).toBe("# my heading");
  });

  it("H1 -> H2", () => {
    const result = cycleHeading(v("# my heading", 5));
    expect(result.text).toBe("## my heading");
  });

  it("H2 -> H3", () => {
    const result = cycleHeading(v("## my heading", 5));
    expect(result.text).toBe("### my heading");
  });

  it("H3 -> normal", () => {
    const result = cycleHeading(v("### my heading", 5));
    expect(result.text).toBe("my heading");
  });

  it("H4 drops straight to normal", () => {
    const result = cycleHeading(v("#### my heading", 5));
    expect(result.text).toBe("my heading");
  });

  it("H5 drops straight to normal", () => {
    const result = cycleHeading(v("##### my heading", 5));
    expect(result.text).toBe("my heading");
  });

  it("H6 drops straight to normal", () => {
    const result = cycleHeading(v("###### my heading", 5));
    expect(result.text).toBe("my heading");
  });

  it("operates on the correct line in multi-line text (collapsed caret)", () => {
    const result = cycleHeading(v("line one\nline two\nline three", 12));
    expect(result.text).toBe("line one\n# line two\nline three");
  });

  it("caret position shifts by the inserted prefix length", () => {
    const result = cycleHeading(v("my heading", 5));
    expect(result.selection).toEqual({ anchor: 7, head: 7 });
  });

  it("caret collapses to the prefix boundary when it was inside a removed prefix", () => {
    // caret at offset 2 sits inside "###" (H3, prefix length 4); next state
    // is normal, so the whole prefix is removed and the caret lands at 0.
    const result = cycleHeading(v("### heading", 2));
    expect(result.text).toBe("heading");
    expect(result.selection).toEqual({ anchor: 0, head: 0 });
  });
});

describe("cycleHeading — multi-line selection", () => {
  it("both lines normal: topmost (first) line's next state (H1) applies to both", () => {
    const source = "line one\nline two";
    const result = cycleHeading(v(source, 0, source.length));
    expect(result.text).toBe("# line one\n# line two");
  });

  it("mixed levels converge to the topmost line's next state, not each cycling independently", () => {
    const source = "## first\nthird\n### second";
    const result = cycleHeading(v(source, 0, source.length));
    // topmost line "## first" is H2 -> next state H3, applied uniformly.
    expect(result.text).toBe("### first\n### third\n### second");
  });

  it("topmost line at H6 converges the whole selection to normal", () => {
    const source = "###### first\n# second";
    const result = cycleHeading(v(source, 0, source.length));
    expect(result.text).toBe("first\nsecond");
  });

  it(
    "topmost is decided by document position, not by which end is the anchor " +
      "(reversed selection: anchor at the bottom line, head at the top)",
    () => {
      const source = "first\n## second";
      const secondLineStart = source.indexOf("## second");
      // anchor is on the LOWER line (higher offset), head on the upper line.
      const result = cycleHeading(v(source, secondLineStart + 3, 0));
      // Topmost by position is "first" (level 0) -> next state H1, applied
      // to both lines, overriding "## second"'s own level.
      expect(result.text).toBe("# first\n# second");
    },
  );

  it("selection endpoints remap correctly across a multi-line heading cycle", () => {
    const source = "one\ntwo";
    const result = cycleHeading(v(source, 1, 6));
    expect(result.text).toBe("# one\n# two");
    expect(result.selection).toEqual({ anchor: 3, head: 10 });
  });
});
