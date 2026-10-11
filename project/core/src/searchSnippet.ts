export interface SnippetRange {
  start: number;
  end: number;
}

export interface SearchSnippet {
  /** One line of context around the first match, markdown markers stripped, cut with "…". */
  text: string;
  /** Every match visible in `text`, as offsets into `text`. */
  highlights: SnippetRange[];
  /** True when the first match is on the body's first non-blank line, the one the list's preview shows. */
  onFirstLine: boolean;
}

const SNIPPET_MAX_LENGTH = 80;
const CONTEXT_BEFORE_MATCH = 20;
const ELLIPSIS = '…';

/**
 * True when `body` matches `query` under QuKiStore.search's rule: a
 * case-insensitive substring test on the whole body. `query` is expected to
 * be trimmed and non-empty already.
 */
export function bodyMatches(body: string, query: string): boolean {
  return body.toLowerCase().includes(query.toLowerCase());
}

/**
 * The matches of `query` in `body`, as offsets into `body`. Found with the
 * same toLowerCase comparison bodyMatches uses, so a body that matches always
 * yields at least one range.
 */
export function findMatches(body: string, query: string): SnippetRange[] {
  const lowerBody = body.toLowerCase();
  const lowerQuery = query.toLowerCase();
  if (lowerQuery === '') return [];
  const toOriginal = lowerBody.length === body.length ? (i: number) => i : lowercaseOffsetMap(body);

  const ranges: SnippetRange[] = [];
  for (let at = lowerBody.indexOf(lowerQuery); at !== -1; at = lowerBody.indexOf(lowerQuery, at + lowerQuery.length)) {
    const start = toOriginal(at);
    const end = Math.max(start + 1, toOriginal(at + lowerQuery.length));
    ranges.push({ start, end });
  }
  return ranges;
}

// A few characters lowercase to more UTF-16 units than they started with
// ("İ" becomes "i̇"), which shifts every later offset in the lowercased copy.
function lowercaseOffsetMap(body: string): (i: number) => number {
  const map: number[] = [];
  let i = 0;
  for (const ch of body) {
    for (let k = 0; k < ch.toLowerCase().length; k++) map.push(i);
    i += ch.length;
  }
  map.push(body.length);
  return (lowerIndex: number) => map[Math.min(lowerIndex, map.length - 1)];
}

function isSpace(ch: string | undefined): boolean {
  return ch === undefined || /\s/.test(ch);
}

function isPunct(ch: string | undefined): boolean {
  return ch !== undefined && /[\p{P}\p{S}]/u.test(ch);
}

/**
 * Which characters of `line` survive once markdown markers are removed:
 * leading block markers (quote, heading, list bullet, task box), code-span
 * backticks, link/image brackets and targets, and emphasis/strikethrough
 * delimiter runs that sit at a word edge. Nothing inside a code span is
 * stripped.
 */
function visibleMask(line: string): boolean[] {
  const keep = new Array<boolean>(line.length).fill(true);
  const protectedChars = new Array<boolean>(line.length).fill(false);
  const remove = (from: number, to: number): void => {
    for (let i = from; i < to; i++) keep[i] = false;
  };

  let pos = 0;
  const prefix = (re: RegExp): boolean => {
    const m = re.exec(line.slice(pos));
    if (!m) return false;
    remove(pos, pos + m[0].length);
    pos += m[0].length;
    return true;
  };
  prefix(/^\s+/);
  while (prefix(/^>\s?/)) prefix(/^\s+/);
  if (!prefix(/^#{1,6}(?=\s)\s*/) && prefix(/^(?:[-*+]|\d+[.)])\s+/)) prefix(/^\[[ xX]\]\s+/);

  for (let i = pos; i < line.length; ) {
    if (line[i] !== '`') {
      i++;
      continue;
    }
    let runEnd = i;
    while (line[runEnd] === '`') runEnd++;
    const run = line.slice(i, runEnd);
    const close = findClosingBacktickRun(line, runEnd, run.length);
    if (close === -1) {
      i = runEnd;
      continue;
    }
    remove(i, runEnd);
    remove(close, close + run.length);
    for (let k = i; k < close + run.length; k++) protectedChars[k] = true;
    i = close + run.length;
  }

  const link = /!?\[([^\]\n]*)\]\(([^)\n]*)\)/g;
  for (let m = link.exec(line); m; m = link.exec(line)) {
    const start = m.index;
    if (start < pos || protectedChars[start]) continue;
    const openLength = line[start] === '!' ? 2 : 1;
    const textEnd = start + openLength + m[1].length;
    remove(start, start + openLength);
    remove(textEnd, start + m[0].length);
  }

  for (let i = pos; i < line.length; ) {
    const ch = line[i];
    if ((ch !== '*' && ch !== '_' && ch !== '~') || protectedChars[i] || !keep[i]) {
      i++;
      continue;
    }
    let runEnd = i;
    while (line[runEnd] === ch) runEnd++;
    if (ch === '~' && runEnd - i < 2) {
      i = runEnd;
      continue;
    }
    const before = line[i - 1];
    const after = line[runEnd];
    const opens = (isSpace(before) || isPunct(before)) && !isSpace(after);
    const closes = !isSpace(before) && (isSpace(after) || isPunct(after));
    if (opens || closes) remove(i, runEnd);
    i = runEnd;
  }

  return keep;
}

function findClosingBacktickRun(line: string, from: number, length: number): number {
  for (let i = from; i < line.length; ) {
    if (line[i] !== '`') {
      i++;
      continue;
    }
    let runEnd = i;
    while (line[runEnd] === '`') runEnd++;
    if (runEnd - i === length) return i;
    i = runEnd;
  }
  return -1;
}

interface VisibleLine {
  text: string;
  highlights: SnippetRange[];
}

function project(line: string, ranges: SnippetRange[], keep: boolean[]): VisibleLine {
  let text = '';
  const highlights: SnippetRange[] = [];
  let r = 0;
  let highlightedRange = -1;
  for (let i = 0; i < line.length; i++) {
    while (r < ranges.length && ranges[r].end <= i) r++;
    if (!keep[i]) continue;
    if (r < ranges.length && ranges[r].start <= i) {
      if (highlightedRange === r) {
        highlights[highlights.length - 1].end++;
      } else {
        highlights.push({ start: text.length, end: text.length + 1 });
        highlightedRange = r;
      }
    }
    text += line[i];
  }
  return { text, highlights };
}

function trimWhitespace(visible: VisibleLine): VisibleLine {
  const lead = visible.text.length - visible.text.trimStart().length;
  const text = visible.text.trim();
  const highlights = visible.highlights
    .map((h) => ({ start: Math.max(0, h.start - lead), end: Math.min(text.length, h.end - lead) }))
    .filter((h) => h.end > h.start);
  return { text, highlights };
}

function windowAround(visible: VisibleLine): VisibleLine {
  const { text } = visible;
  const n = text.length;
  if (n <= SNIPPET_MAX_LENGTH || visible.highlights.length === 0) return visible;

  const first = visible.highlights[0];
  let start = Math.max(0, Math.min(first.start - CONTEXT_BEFORE_MATCH, n - SNIPPET_MAX_LENGTH));
  if (start > 0 && !isSpace(text[start - 1])) {
    const space = text.slice(start, first.start).search(/\s/);
    if (space !== -1) start += space + 1;
  }

  let end = Math.max(first.end, start + SNIPPET_MAX_LENGTH);
  if (end >= n) {
    end = n;
  } else if (!isSpace(text[end])) {
    const tail = text.slice(first.end, end);
    const lastSpace = tail.search(/\s\S*$/);
    if (lastSpace !== -1) end = first.end + lastSpace;
  }

  const body = text.slice(start, end);
  const lead = body.length - body.trimStart().length;
  const shown = body.trim();
  const prefix = start > 0 ? ELLIPSIS : '';
  const suffix = end < n ? ELLIPSIS : '';
  const offset = prefix.length - start - lead;
  const highlights = visible.highlights
    .map((h) => ({
      start: Math.max(h.start + offset, prefix.length),
      end: Math.min(h.end + offset, prefix.length + shown.length),
    }))
    .filter((h) => h.end > h.start);
  return { text: prefix + shown + suffix, highlights };
}

/**
 * A one-line snippet of `body` around the first match of `query`, with every
 * match on that line marked, or null when `query` does not match. Matching is
 * QuKiStore.search's: case-insensitive substring over the raw body, so a
 * match may include markdown markers; the highlight then covers only the
 * visible text. When stripping would hide the first match completely (a
 * match inside a link target, say) the line is shown unstripped instead.
 */
export function buildSearchSnippet(body: string, query: string): SearchSnippet | null {
  const ranges = findMatches(body, query);
  if (ranges.length === 0) return null;

  const first = ranges[0];
  const lineStart = Math.max(body.lastIndexOf('\n', first.start - 1), body.lastIndexOf('\r', first.start - 1)) + 1;
  const breakAt = body.slice(first.start).search(/[\r\n]/);
  const lineEnd = breakAt === -1 ? body.length : first.start + breakAt;
  const line = body.slice(lineStart, lineEnd);
  const lineRanges = ranges
    .filter((r) => r.start < lineEnd && r.end > lineStart)
    .map((r) => ({ start: Math.max(r.start, lineStart) - lineStart, end: Math.min(r.end, lineEnd) - lineStart }));

  const firstOnLine = lineRanges[0];
  let keep = visibleMask(line);
  if (!keep.slice(firstOnLine.start, firstOnLine.end).some(Boolean)) keep = keep.map(() => true);

  const onFirstLine = body.slice(0, lineStart).trim() === '';
  return { ...windowAround(trimWhitespace(project(line, lineRanges, keep))), onFirstLine };
}
