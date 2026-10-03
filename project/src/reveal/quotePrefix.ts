export interface QuotePrefix {
  depth: number;
  length: number;
}

/**
 * Peels `>` markers off the start of a line, each optionally followed by one
 * space: `> x` is depth 1, `>> x` and `> > x` are depth 2, `>x` is depth 1
 * with a one-character marker. `length` is where the quoted content begins.
 * Returns null when the line does not start with `>`.
 */
export function quotePrefix(line: string): QuotePrefix | null {
  let depth = 0;
  let i = 0;
  while (i < line.length && line[i] === ">") {
    depth += 1;
    i += 1;
    if (line[i] === " ") i += 1;
  }
  return depth === 0 ? null : { depth, length: i };
}
