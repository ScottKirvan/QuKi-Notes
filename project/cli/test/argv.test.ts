import { describe, expect, it } from 'vitest';

import { parseArgs, stringFlag, UnknownFlagError, type ArgSpec } from '../src/argv.js';

const SPEC: ArgSpec = {
  booleanFlags: ['trash', 'stdin', 'keep-images'],
  valueFlags: ['dir', 'id', 'file', 'expected-modified-at', 'ext'],
};

describe('parseArgs', () => {
  it('separates positional args from --flag value pairs', () => {
    const { positional, flags } = parseArgs(['list', '--dir', '/tmp/x', '--trash'], SPEC);
    expect(positional).toEqual(['list']);
    expect(flags.dir).toBe('/tmp/x');
    expect(flags.trash).toBe(true);
  });

  it('a declared boolean flag never consumes the next word as its value', () => {
    const { positional, flags } = parseArgs(['search', '--trash', 'hello'], SPEC);
    expect(flags.trash).toBe(true);
    expect(positional).toEqual(['search', 'hello']);
  });

  it('a declared boolean flag leaves a following positional id available to the command', () => {
    const { positional, flags } = parseArgs(['read', '--trash', 'some-id'], SPEC);
    expect(flags.trash).toBe(true);
    expect(positional).toEqual(['read', 'some-id']);
  });

  it('a declared value flag consumes the next word regardless of what it looks like', () => {
    const { flags } = parseArgs(['save', '--id', '--weird-but-a-real-id'], SPEC);
    expect(flags.id).toBe('--weird-but-a-real-id');
  });

  it('two boolean flags back to back both parse as true', () => {
    const { flags } = parseArgs(['--stdin', '--keep-images'], SPEC);
    expect(flags.stdin).toBe(true);
    expect(flags['keep-images']).toBe(true);
  });

  it('a trailing boolean flag with nothing after it is true', () => {
    const { flags } = parseArgs(['--trash'], SPEC);
    expect(flags.trash).toBe(true);
  });

  it('rejects an unrecognized flag rather than silently ignoring it', () => {
    expect(() => parseArgs(['delete', 'some-id', '--keep-image'], SPEC)).toThrow(UnknownFlagError);
    expect(() => parseArgs(['delete', 'some-id', '--keep-image'], SPEC)).toThrow(/keep-image/);
  });

  it('rejects a declared value flag with nothing after it', () => {
    expect(() => parseArgs(['save', '--id'], SPEC)).toThrow(/--id/);
  });
});

describe('stringFlag', () => {
  it('returns the value only when the flag is a string, not a boolean', () => {
    expect(stringFlag({ dir: '/tmp/x', trash: true }, 'dir')).toBe('/tmp/x');
    expect(stringFlag({ dir: '/tmp/x', trash: true }, 'trash')).toBeUndefined();
    expect(stringFlag({}, 'missing')).toBeUndefined();
  });
});
