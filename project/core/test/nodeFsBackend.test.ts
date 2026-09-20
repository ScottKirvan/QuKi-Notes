import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

describe('NodeFsBackend.resolvePath', () => {
  let dir: string;
  let backend: NodeFsBackend;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    backend = new NodeFsBackend(dir);
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('resolves an ordinary relative path to an absolute path inside the root', () => {
    const resolved = backend.resolvePath('media/foo.png');
    expect(resolved).toBe(path.join(dir, 'media', 'foo.png'));
    expect(resolved.startsWith(path.normalize(dir))).toBe(true);
  });

  it('rejects a path that escapes the QuKi folder via ../', () => {
    expect(() => backend.resolvePath('../outside.md')).toThrow(/escapes/);
    expect(() => backend.resolvePath('media/../../outside.md')).toThrow(/escapes/);
  });
});
