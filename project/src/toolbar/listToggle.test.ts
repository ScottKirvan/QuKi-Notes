import { describe, expect, it } from "vitest";

import { toggleCheckboxList, toggleOrderedList, toggleUnorderedList } from "./listToggle";
import type { EditorValue } from "./types";

function v(text: string, anchor: number, head = anchor): EditorValue {
  return { text, selection: { anchor, head } };
}

// Ported from formatting_toolbar_test.dart's "toggleUnorderedList" and
// "toggleOrderedList" groups, plus the checklist/list toolbar-button cases.
describe("toggleUnorderedList", () => {
  it('adds "- " prefix when line has no list marker', () => {
    const result = toggleUnorderedList(v("plain item", 5));
    expect(result.text).toBe("- plain item");
  });

  it('removes "- " prefix when already present', () => {
    const result = toggleUnorderedList(v("- plain item", 5));
    expect(result.text).toBe("plain item");
  });

  it(
    "converts a task-list marker to a bullet, not a full strip — regression: " +
      'toggleUnorderedList previously treated checkbox as "same family" and ' +
      "stripped it entirely instead of converting",
    () => {
      const result = toggleUnorderedList(v("- [ ] task item", 8));
      expect(result.text).toBe("- task item");
    },
  );

  it('removes "* " prefix when present', () => {
    const result = toggleUnorderedList(v("* asterisk", 3));
    expect(result.text).toBe("asterisk");
  });

  it("preserves depth on an indented line", () => {
    const result = toggleUnorderedList(v("  plain item", 7));
    expect(result.text).toBe("  - plain item");
  });

  it("is a no-op on a heading line", () => {
    const result = toggleUnorderedList(v("# Heading", 4));
    expect(result.text).toBe("# Heading");
  });
});

describe("toggleOrderedList", () => {
  it('adds "1. " prefix when line has no ordered marker', () => {
    const result = toggleOrderedList(v("first item", 5));
    expect(result.text).toBe("1. first item");
  });

  it("removes ordered prefix regardless of number", () => {
    const result = toggleOrderedList(v("3. third item", 5));
    expect(result.text).toBe("third item");
  });

  it("removes multi-digit ordered prefix", () => {
    const result = toggleOrderedList(v("10. tenth item", 5));
    expect(result.text).toBe("tenth item");
  });

  it("converts an unordered marker to ordered", () => {
    const result = toggleOrderedList(v("- an item", 4));
    expect(result.text).toBe("1. an item");
  });

  it("converts a checkbox marker to ordered", () => {
    const result = toggleOrderedList(v("- [ ] an item", 6));
    expect(result.text).toBe("1. an item");
  });
});

describe("toggleCheckboxList", () => {
  it('adds "- [ ] " prefix when absent', () => {
    const result = toggleCheckboxList(v("task item", 0));
    expect(result.text).toBe("- [ ] task item");
  });

  it("removes the checkbox prefix when already present", () => {
    const result = toggleCheckboxList(v("- [ ] task item", 8));
    expect(result.text).toBe("task item");
  });

  it("removes a checked checkbox prefix too", () => {
    const result = toggleCheckboxList(v("- [x] task item", 8));
    expect(result.text).toBe("task item");
  });

  it("converts an ordered marker to a checkbox", () => {
    const result = toggleCheckboxList(v("1. an item", 5));
    expect(result.text).toBe("- [ ] an item");
  });
});

describe("list toggle — multi-line selection", () => {
  it("applies the marker to every eligible line, excluding a heading line entirely", () => {
    const source = "# Heading\nitem one\nitem two";
    const result = toggleUnorderedList(v(source, 0, source.length));
    expect(result.text).toBe("# Heading\n- item one\n- item two");
  });

  it("a selection touching only heading lines is a full no-op (text and selection unchanged)", () => {
    const source = "# Heading\n## Another";
    const value = v(source, 0, source.length);
    const result = toggleUnorderedList(value);
    expect(result.text).toBe(source);
    expect(result.selection).toEqual(value.selection);
  });

  it("removes the marker from every touched line when all of them already carry it", () => {
    const source = "- one\n- two";
    const result = toggleUnorderedList(v(source, 0, source.length));
    expect(result.text).toBe("one\ntwo");
  });

  it("selection endpoints remap correctly across a multi-line toggle", () => {
    const source = "one\ntwo";
    const result = toggleUnorderedList(v(source, 1, 6));
    expect(result.text).toBe("- one\n- two");
    expect(result.selection).toEqual({ anchor: 3, head: 10 });
  });
});
