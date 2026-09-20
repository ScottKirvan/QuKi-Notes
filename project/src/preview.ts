const PREVIEW_MAX_LENGTH = 80;
const EMPTY_PREVIEW = "(empty)";

/**
 * A heading marker only strips when it is a real heading per
 * BEHAVIOR_SPEC.md §12's block-detection rule ("# " followed by a space) -
 * "#notaheading" is plain text and is left alone, matching how the reveal
 * engine itself decides what counts as a heading.
 */
const HEADING_MARKER = /^#{1,6}(?=\s)\s*/;

function truncate(text: string): string {
  if (text.length <= PREVIEW_MAX_LENGTH) return text;
  return `${text.slice(0, PREVIEW_MAX_LENGTH)}…`;
}

/**
 * BEHAVIOR_SPEC.md §5: "the first non-blank line, with any leading heading
 * markers stripped, truncated to 80 characters with an ellipsis. Empty or
 * unreadable QuKis show (empty)." Passing null/undefined stands in for
 * "unreadable" (a body that could not be read), which the caller is
 * responsible for substituting when a store read fails.
 */
export function extractPreview(body: string | null | undefined): string {
  if (!body) return EMPTY_PREVIEW;

  for (const rawLine of body.split(/\r\n|\r|\n/)) {
    if (rawLine.trim() === "") continue;

    // Trim only the leading edge before matching the heading marker - a
    // trailing-whitespace-only marker line (e.g. "###   ") must still match
    // the marker's own trailing \s*, which a full trim() would have already
    // eaten.
    const leftTrimmed = rawLine.replace(/^\s+/, "");
    const text = leftTrimmed.replace(HEADING_MARKER, "").trim();
    if (text === "") return EMPTY_PREVIEW;
    return truncate(text);
  }

  return EMPTY_PREVIEW;
}
