export interface TextCount {
  words: number;
  characters: number;
}

const WORD = /[\p{L}\p{N}]/u;
const LINE_MARKERS = /^[ \t]*(?:>[ \t]*)*(?:#{1,6}[ \t]+|[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d+[.)][ \t]+)?/u;

/**
 * Counts a QuKi's text as Send would deliver it, markdown and all.
 *
 * Characters are what a reader perceives as one character (an emoji or an
 * accented letter is one), with spaces and line breaks included - the way
 * character-limited destinations count them.
 *
 * A word is a run of non-space text containing at least one letter or digit,
 * so a line's markdown markers (`#`, `-`, `1.`, `>`, `- [ ]`) are not words,
 * and `**bold**` or `[a link](https://example.com)` is one.
 */
export function countText(text: string): TextCount {
  let words = 0;
  for (const line of text.split("\n")) {
    for (const token of line.replace(LINE_MARKERS, "").split(/\s+/u)) {
      if (WORD.test(token)) words++;
    }
  }
  return { words, characters: countCharacters(text) };
}

function countCharacters(text: string): number {
  if (typeof Intl !== "undefined" && "Segmenter" in Intl) {
    let count = 0;
    for (const _ of new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)) count++;
    return count;
  }
  return Array.from(text).length;
}

export function formatCount({ words, characters }: TextCount): string {
  const wordLabel = words === 1 ? "word" : "words";
  const characterLabel = characters === 1 ? "character" : "characters";
  return `${words.toLocaleString()} ${wordLabel} · ${characters.toLocaleString()} ${characterLabel}`;
}
