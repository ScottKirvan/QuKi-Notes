import { describe, expect, it } from "vitest";
import { quotePrefix } from "./quotePrefix";

describe("quotePrefix", () => {
  it.each([
    ["> x", 1, 2],
    [">x", 1, 1],
    [">", 1, 1],
    ["> ", 1, 2],
    [">> x", 2, 3],
    ["> > x", 2, 4],
    [">>> x", 3, 4],
    [">>>x", 3, 3],
    ["> >x", 2, 3],
    [">  x", 1, 2],
    ["> > > deep", 3, 6],
  ])("%j has depth %i and a marker %i characters long", (line, depth, length) => {
    expect(quotePrefix(line)).toEqual({ depth, length });
  });

  it.each(["", "x", " > x", "x > y", "- > x"])("%j is not a quote line", (line) => {
    expect(quotePrefix(line)).toBeNull();
  });
});
