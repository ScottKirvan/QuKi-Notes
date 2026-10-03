import { describe, expect, it } from "vitest";
import { computeOrderedNumbers, indentDepth, type NumberingLine } from "./listNumbering";

const ol = (digit: number, depth = 0): NumberingLine => ({ depth, digit });
const other = (depth = 0): NumberingLine => ({ depth, digit: null });

describe("computeOrderedNumbers — block-relative numbering", () => {
  it("given 1. 1. 1., when numbered, then it renders 1, 2, 3", () => {
    expect(computeOrderedNumbers([ol(1), ol(1), ol(1)])).toEqual([1, 2, 3]);
  });

  it("given a run starting at 5., when numbered, then it renders 5, 6, 7", () => {
    expect(computeOrderedNumbers([ol(5), ol(1), ol(1)])).toEqual([5, 6, 7]);
  });

  it("given 1. 3. 5., when numbered, then the later digits are ignored: 1, 2, 3", () => {
    expect(computeOrderedNumbers([ol(1), ol(3), ol(5)])).toEqual([1, 2, 3]);
  });

  it("given a plain line in the middle, when numbered, then the second run keeps its own digit", () => {
    expect(computeOrderedNumbers([ol(1), other(), ol(7)])).toEqual([1, null, 7]);
  });

  it("given two items, a break, then a run, when numbered, then 1, 2 then the new run's own digit", () => {
    expect(computeOrderedNumbers([ol(1), ol(2), other(), ol(7)])).toEqual([1, 2, null, 7]);
  });

  it("given a blank line between items, when numbered, then the run breaks", () => {
    expect(computeOrderedNumbers([ol(1), other(), ol(1)])).toEqual([1, null, 1]);
  });

  it("given a non-ordered line at the same depth, when numbered, then the run restarts", () => {
    expect(computeOrderedNumbers([ol(1), other(0), ol(1)])).toEqual([1, null, 1]);
  });
});

describe("computeOrderedNumbers — nesting", () => {
  it("given a nested run under an item, when numbered, then the nested run counts on its own", () => {
    expect(computeOrderedNumbers([ol(1, 0), ol(1, 1), ol(1, 1)])).toEqual([1, 1, 2]);
  });

  it("given a parent run resumed after a nested run, when numbered, then the parent continues its count", () => {
    expect(computeOrderedNumbers([ol(1, 0), ol(1, 1), ol(1, 0)])).toEqual([1, 1, 2]);
  });

  it("given a parent run resumed after a deeper non-ordered line, when numbered, then the parent continues", () => {
    expect(computeOrderedNumbers([ol(1, 0), other(1), ol(1, 0)])).toEqual([1, null, 2]);
  });

  it("given a multi-level chain, when each level resumes, then each continues its own count", () => {
    const lines = [ol(1, 0), ol(1, 1), ol(1, 2), ol(1, 2), ol(1, 1), ol(1, 0)];
    expect(computeOrderedNumbers(lines)).toEqual([1, 1, 1, 2, 2, 2]);
  });

  it("given a nested run that was interrupted by its parent's next item, when it restarts, then it restarts from its own digit", () => {
    const lines = [ol(1, 0), ol(1, 1), ol(1, 0), ol(4, 1)];
    expect(computeOrderedNumbers(lines)).toEqual([1, 1, 2, 4]);
  });
});

describe("indentDepth", () => {
  it.each([
    ["", 0],
    [" ", 0],
    ["  ", 1],
    ["\t", 1],
    ["   ", 1],
    ["    ", 2],
    ["\t\t", 2],
    [" \t", 1],
  ])("leading whitespace %j has depth %i", (ws, depth) => {
    expect(indentDepth(ws)).toBe(depth);
  });
});
