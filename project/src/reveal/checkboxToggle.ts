export interface CheckboxEdit {
  from: number;
  to: number;
  insert: string;
}

const UNCHECKED = "- [ ] ";
const CHECKED_MARKERS = new Set(["- [x] ", "- [X] "]);

/**
 * BEHAVIOR_SPEC.md section 4, "Checkbox tap": skip any leading indentation
 * of `line`, read six characters, and swap `- [ ] ` with `- [x] `, or
 * `- [x] `/`- [X] ` with `- [ ] `. Anything else returns null. Offsets in
 * the result are relative to the start of `line`.
 */
export function toggleCheckbox(line: string): CheckboxEdit | null {
  let start = 0;
  while (line[start] === " " || line[start] === "\t") start += 1;

  const marker = line.slice(start, start + 6);
  if (marker === UNCHECKED) {
    return { from: start, to: start + 6, insert: "- [x] " };
  }
  if (CHECKED_MARKERS.has(marker)) {
    return { from: start, to: start + 6, insert: UNCHECKED };
  }
  return null;
}
