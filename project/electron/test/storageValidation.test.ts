import * as fs from 'node:fs';
import { tmpdir } from 'node:os';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { isValidWritableDirectory } from '../src/storageValidation.js';

// A plain vi.spyOn(fs, 'writeFileSync') cannot work here: `fs` is imported as
// an ES module namespace object (both here and in storageValidation.ts), and
// Node's Module Namespace Exotic Object rejects any attempt to redefine one
// of its own bindings - confirmed directly (a throwaway script attempting
// vi.spyOn's underlying Object.defineProperty, and even a plain reassignment,
// both threw "Cannot assign/redefine ... read only property"). vi.mock
// intercepts at module resolution instead of trying to mutate the namespace
// object after the fact, which is what actually lets a single test force
// fs.writeFileSync to fail while every other test keeps using the real
// implementation via the vi.fn(actual.writeFileSync) passthrough below.
vi.mock('node:fs', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:fs')>();
  return {
    ...actual,
    writeFileSync: vi.fn(actual.writeFileSync),
  };
});

function makeTempDir(): string {
  return fs.mkdtempSync(path.join(tmpdir(), 'quki-storage-validation-test-'));
}

function mockedWriteFileSync(): ReturnType<typeof vi.fn> {
  return fs.writeFileSync as unknown as ReturnType<typeof vi.fn>;
}

describe('isValidWritableDirectory', () => {
  let dir: string;

  beforeEach(() => {
    dir = makeTempDir();
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('returns true for a real, existing, writable directory', () => {
    expect(isValidWritableDirectory(dir)).toBe(true);
  });

  it('returns false when the path does not exist', () => {
    expect(isValidWritableDirectory(path.join(dir, 'nope'))).toBe(false);
  });

  it('returns false when the path exists but is a file, not a directory', () => {
    const filePath = path.join(dir, 'not-a-directory.txt');
    fs.writeFileSync(filePath, 'x', 'utf8');

    expect(isValidWritableDirectory(filePath)).toBe(false);
  });

  it('returns false when the directory exists but writing into it fails', () => {
    // A directory's permission bits (chmod) are not a reliable cross-platform
    // way to force a write failure - Windows in particular does not enforce
    // a folder's read-only attribute against file creation inside it, which
    // is exactly the gap this validation exists to avoid trusting. Forcing
    // the one fs.writeFileSync call the probe makes to fail (see the vi.mock
    // above) is what's actually reliable on every platform this runs on.
    mockedWriteFileSync().mockImplementationOnce(() => {
      throw new Error('EACCES: permission denied (simulated)');
    });

    expect(isValidWritableDirectory(dir)).toBe(false);
  });

  it('leaves no marker file behind after a successful check', () => {
    isValidWritableDirectory(dir);

    expect(fs.readdirSync(dir)).toEqual([]);
  });
});
