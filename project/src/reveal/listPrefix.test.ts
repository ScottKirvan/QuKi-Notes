import { describe, expect, it } from "vitest";
import { listPrefixLength } from "./listPrefix";

describe("listPrefixLength", () => {
  it.each([
    ["- x", 2],
    ["* x", 2],
    ["+ x", 2],
    ["  - x", 4],
    ["\t- x", 3],
    ["        - blah", 10],
    [" \t \t- x", 6],
    ["1. x", 3],
    ["10. x", 4],
    ["  12. x", 6],
    ["\t\t1. x", 5],
    ["- [ ] x", 6],
    ["- [x] x", 6],
    ["- [X] x", 6],
    ["\t- [ ] x", 7],
    ["- ", 2],
    ["- [ ] ", 6],
    ["-   x", 2],
  ])("%j is a list line whose text starts at %i", (line, length) => {
    expect(listPrefixLength(line)).toBe(length);
  });

  it.each([
    ["- [ ]x", 2],
    ["- [] x", 2],
    ["- [ x", 2],
    ["* [ ] x", 2],
    ["+ [x] x", 2],
    ["1. [ ] x", 3],
  ])("%j keeps a task-box lookalike as content (text starts at %i)", (line, length) => {
    expect(listPrefixLength(line)).toBe(length);
  });

  it.each([
    "",
    "text",
    "-x",
    "-",
    "*",
    "1.",
    "1.x",
    "1) x",
    "a. x",
    "> - x",
    "# - x",
    "x - y",
    ". x",
    " - x",
  ])("%j is not a list line", (line) => {
    expect(listPrefixLength(line)).toBeNull();
  });
});
