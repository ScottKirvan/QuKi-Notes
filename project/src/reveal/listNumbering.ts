export interface NumberingLine {
  depth: number;
  digit: number | null;
}

export function indentDepth(leadingWhitespace: string): number {
  let width = 0;
  for (const ch of leadingWhitespace) {
    width += ch === "\t" ? 2 : 1;
  }
  return Math.floor(width / 2);
}

/**
 * Block-relative ordered-list numbering (BEHAVIOR_SPEC.md section 12,
 * "Block detection"): the first item of a run keeps its own source digit and
 * every later item in the run counts up by one, whatever digit it was
 * written with. Any line that is not an ordered item ends the run at its own
 * depth and every deeper depth, but never at a shallower one — a nested
 * interruption does not end the parent's run.
 *
 * `lines` is every line of the document in order; `digit` is the source digit
 * for an ordered-item line and null for any other line. The result is
 * parallel to `lines`: the number to render for an ordered-item line, null
 * elsewhere.
 */
export function computeOrderedNumbers(lines: NumberingLine[]): (number | null)[] {
  const runs = new Map<number, { firstDigit: number; count: number }>();
  const invalidateFrom = (depth: number): void => {
    for (const d of [...runs.keys()]) {
      if (d >= depth) runs.delete(d);
    }
  };

  return lines.map(({ depth, digit }) => {
    if (digit === null) {
      invalidateFrom(depth);
      return null;
    }
    for (const d of [...runs.keys()]) {
      if (d > depth) runs.delete(d);
    }
    const run = runs.get(depth);
    if (run) {
      run.count += 1;
      return run.firstDigit + run.count - 1;
    }
    runs.set(depth, { firstDigit: digit, count: 1 });
    return digit;
  });
}
