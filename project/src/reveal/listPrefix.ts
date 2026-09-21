const LIST_PREFIX = /^[ \t]*(?:-(?: \[[ xX]\])? |[*+] |\d+\. )/;

/**
 * Where the text of a list-style line begins: after its leading whitespace,
 * its marker (`-`, `*`, `+`, or digits and a dot) and the single space that
 * follows — and after a `[ ]`/`[x]` box too when the marker is `-`, the only
 * marker the reveal engine reads as a task. Decided from the line alone,
 * whether or not the parser made it a list item. Null when it isn't one.
 */
export function listPrefixLength(line: string): number | null {
  const match = LIST_PREFIX.exec(line);
  return match ? match[0].length : null;
}
