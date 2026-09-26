import { describe, expect, it } from 'vitest';

import { isOrphanCandidate } from '../src/media.js';

describe('isOrphanCandidate', () => {
  it('accepts a reference that names a real direct child of media/', () => {
    expect(isOrphanCandidate('media/abc123.png', ['abc123.png', 'other.png'])).toBe(true);
  });

  it('rejects a reference to a name not present in the media/ listing', () => {
    expect(isOrphanCandidate('media/missing.png', ['abc123.png'])).toBe(false);
  });

  it('rejects a path-traversal reference even if it resolves to an existing file elsewhere', () => {
    // media/../notes.md would resolve outside media/ entirely - it can never
    // be confirmed against a media/ directory listing, no matter what else exists.
    expect(isOrphanCandidate('media/../notes.md', ['abc123.png'])).toBe(false);
    expect(isOrphanCandidate('media/../notes.md', [])).toBe(false);
  });

  it('rejects a reference into a media/ subdirectory', () => {
    expect(isOrphanCandidate('media/sub/file.png', ['sub'])).toBe(false);
  });

  it('rejects a reference that does not start with media/', () => {
    expect(isOrphanCandidate('notes.md', ['notes.md'])).toBe(false);
  });

  it('rejects an empty name after the media/ prefix', () => {
    expect(isOrphanCandidate('media/', [''])).toBe(false);
  });
});
