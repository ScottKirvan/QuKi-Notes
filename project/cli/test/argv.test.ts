import { describe, expect, it } from 'vitest';

import { parseArgs, stringFlag } from '../src/argv.js';

describe('parseArgs', () => {
  it('separates positional args from --flag value pairs', () => {
    const { positional, flags } = parseArgs(['list', '--dir', '/tmp/x', '--trash']);
    expect(positional).toEqual(['list']);
    expect(flags.dir).toBe('/tmp/x');
    expect(flags.trash).toBe(true);
  });

  it('treats a flag followed by another flag as a boolean, not a value', () => {
    const { flags } = parseArgs(['--stdin', '--keep-images']);
    expect(flags.stdin).toBe(true);
    expect(flags['keep-images']).toBe(true);
  });

  it('a trailing flag with nothing after it is boolean true', () => {
    const { flags } = parseArgs(['--trash']);
    expect(flags.trash).toBe(true);
  });
});

describe('stringFlag', () => {
  it('returns the value only when the flag is a string, not a boolean', () => {
    expect(stringFlag({ dir: '/tmp/x', trash: true }, 'dir')).toBe('/tmp/x');
    expect(stringFlag({ dir: '/tmp/x', trash: true }, 'trash')).toBeUndefined();
    expect(stringFlag({}, 'missing')).toBeUndefined();
  });
});
