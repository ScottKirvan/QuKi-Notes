import { describe, expect, it } from "vitest";

import { countText, formatCount } from "./wordCount";

describe("countText", () => {
  it("counts nothing in an empty QuKi", () => {
    expect(countText("")).toEqual({ words: 0, characters: 0 });
  });

  it("counts plain words and every character, spaces and line breaks included", () => {
    expect(countText("hello there\nworld")).toEqual({ words: 3, characters: 17 });
  });

  it("does not count a markdown marker standing alone as a word", () => {
    expect(countText("# Title\n- one\n- [ ] two\n> three\n1. four\n\t2) five\n> > - [x] six").words).toBe(7);
  });

  it("counts a number in running text as a word", () => {
    expect(countText("chapter 1. begins").words).toBe(3);
    expect(countText("2024 was long").words).toBe(3);
  });

  it("counts a word wrapped in markers as one word", () => {
    expect(countText("**bold** _it_ ~~gone~~ `code`").words).toBe(4);
  });

  it("counts a link as one word per word of its text", () => {
    expect(countText("see [the docs](https://example.com) now").words).toBe(4);
  });

  it("counts the markers as characters, since Send delivers them", () => {
    expect(countText("**hi**").characters).toBe(6);
  });

  it("counts an emoji or a combined accent as one character", () => {
    expect(countText("👍🏽").characters).toBe(1);
    expect(countText("é").characters).toBe(1);
    expect(countText("👨‍👩‍👧").characters).toBe(1);
  });

  it("counts numbers and words in other scripts", () => {
    expect(countText("42 Привет café").words).toBe(3);
  });

  it("ignores runs of whitespace between words", () => {
    expect(countText("  a \t\t b  \n\n c ").words).toBe(3);
  });
});

describe("formatCount", () => {
  it("uses singular labels for one", () => {
    expect(formatCount({ words: 1, characters: 1 })).toBe("1 word · 1 character");
  });

  it("uses plural labels otherwise", () => {
    expect(formatCount({ words: 0, characters: 0 })).toBe("0 words · 0 characters");
    expect(formatCount({ words: 3, characters: 17 })).toBe("3 words · 17 characters");
  });
});
