import { describe, expect, it } from 'vitest';

import { buildSearchSnippet, type SearchSnippet } from '../src/index.js';

function highlighted(snippet: SearchSnippet | null): string[] {
  if (!snippet) return [];
  return snippet.highlights.map((h) => snippet.text.slice(h.start, h.end));
}

describe('buildSearchSnippet', () => {
  it('returns null when the query does not occur in the body', () => {
    expect(buildSearchSnippet('nothing relevant here', 'brown')).toBeNull();
  });

  it('matches case-insensitively, the same as search, and highlights the original casing', () => {
    const snippet = buildSearchSnippet('The quick Brown Fox', 'bROWN');
    expect(snippet?.text).toBe('The quick Brown Fox');
    expect(highlighted(snippet)).toEqual(['Brown']);
  });

  it('a match at the start of a long line is cut only at the end, on a word boundary', () => {
    const line = 'needle ' + 'word '.repeat(40);
    const snippet = buildSearchSnippet(line, 'needle')!;
    expect(snippet.text.startsWith('needle word')).toBe(true);
    expect(snippet.text.endsWith('word…')).toBe(true);
    expect(snippet.text.length).toBeLessThanOrEqual(81);
    expect(snippet.highlights[0]).toEqual({ start: 0, end: 6 });
  });

  it('a match in the middle of a long line is cut on both sides at word boundaries', () => {
    const line = 'alpha '.repeat(30) + 'needle ' + 'omega '.repeat(30);
    const snippet = buildSearchSnippet(line, 'needle')!;
    expect(snippet.text.startsWith('…alpha ')).toBe(true);
    expect(snippet.text.endsWith('omega…')).toBe(true);
    expect(highlighted(snippet)).toEqual(['needle']);
    expect(snippet.text.length).toBeLessThanOrEqual(82);
  });

  it('a match at the end of a long line is cut only at the start, using the whole width', () => {
    const line = 'alpha '.repeat(40) + 'needle';
    const snippet = buildSearchSnippet(line, 'needle')!;
    expect(snippet.text.startsWith('…alpha ')).toBe(true);
    expect(snippet.text.endsWith('alpha needle')).toBe(true);
    expect(snippet.text.length).toBeGreaterThan(60);
    expect(highlighted(snippet)).toEqual(['needle']);
  });

  it('a very long line with no spaces is hard-cut around the match', () => {
    const line = 'x'.repeat(500) + 'needle' + 'y'.repeat(500);
    const snippet = buildSearchSnippet(line, 'needle')!;
    expect(snippet.text.startsWith('…x')).toBe(true);
    expect(snippet.text.endsWith('y…')).toBe(true);
    expect(snippet.text.length).toBeLessThanOrEqual(82);
    expect(highlighted(snippet)).toEqual(['needle']);
  });

  it('shows the line of the first match, not the first line of the body', () => {
    const snippet = buildSearchSnippet('# Title\n\nfirst line\nsecond has the needle\nthird needle', 'needle');
    expect(snippet?.text).toBe('second has the needle');
  });

  it('highlights every occurrence on that line', () => {
    const snippet = buildSearchSnippet('one cat, two cats, three CATS', 'cat');
    expect(highlighted(snippet)).toEqual(['cat', 'cat', 'CAT']);
  });

  it('strips block markers: heading, quote, list bullet, task box', () => {
    expect(buildSearchSnippet('## A heading needle', 'needle')?.text).toBe('A heading needle');
    expect(buildSearchSnippet('> quoted needle', 'needle')?.text).toBe('quoted needle');
    expect(buildSearchSnippet('  - listed needle', 'needle')?.text).toBe('listed needle');
    expect(buildSearchSnippet('1. numbered needle', 'needle')?.text).toBe('numbered needle');
    expect(buildSearchSnippet('- [x] done needle', 'needle')?.text).toBe('done needle');
  });

  it('strips inline markers: bold, italic, strikethrough, code, links', () => {
    const snippet = buildSearchSnippet('a **bold** and *it* and ~~gone~~ and `code` and [link](http://x.y) needle', 'needle');
    expect(snippet?.text).toBe('a bold and it and gone and code and link needle');
    expect(highlighted(snippet)).toEqual(['needle']);
  });

  it('leaves underscores and asterisks inside words and arithmetic alone', () => {
    expect(buildSearchSnippet('snake_case_name needle', 'needle')?.text).toBe('snake_case_name needle');
    expect(buildSearchSnippet('5 * 3 needle', 'needle')?.text).toBe('5 * 3 needle');
  });

  it('does not strip markers inside a code span', () => {
    expect(buildSearchSnippet('run `a **b** c` needle', 'needle')?.text).toBe('run a **b** c needle');
  });

  it('a match spanning a marker highlights the visible text it covers', () => {
    const snippet = buildSearchSnippet('this is **bold** text', '**bold');
    expect(snippet?.text).toBe('this is bold text');
    expect(highlighted(snippet)).toEqual(['bold']);
  });

  it('a match only inside markup that is stripped shows the raw line instead', () => {
    const snippet = buildSearchSnippet('see [the docs](http://example.com/needle) now', 'needle');
    expect(snippet?.text).toBe('see [the docs](http://example.com/needle) now');
    expect(highlighted(snippet)).toEqual(['needle']);
  });

  it('a match spanning a line break highlights to the end of its first line', () => {
    const snippet = buildSearchSnippet('first needle\nsecond', 'needle\nsec');
    expect(snippet?.text).toBe('first needle');
    expect(highlighted(snippet)).toEqual(['needle']);
  });

  it('copes with characters whose lowercase form is longer', () => {
    const snippet = buildSearchSnippet('İstanbul needle', 'needle');
    expect(highlighted(snippet)).toEqual(['needle']);
  });
});
