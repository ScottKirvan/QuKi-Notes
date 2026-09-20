import * as fsp from 'node:fs/promises';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { QuKiStore } from '../src/index.js';
import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

describe('QuKiStore.list reflects the folder, not a cache', () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('matches the directory exactly after external adds and removes, with no add/update/remove API involved', async () => {
    await store.save({ id: null, body: 'from the API' });

    await fsp.writeFile(path.join(dir, 'alpha.md'), 'alpha');
    await fsp.writeFile(path.join(dir, 'beta.md'), 'beta');

    let ids = (await store.list()).map((q) => q.id).sort();
    let onDisk = (await fsp.readdir(dir))
      .filter((f) => f.endsWith('.md'))
      .map((f) => f.slice(0, -3))
      .sort();
    expect(ids).toEqual(onDisk);
    expect(ids).toContain('alpha');
    expect(ids).toContain('beta');

    await fsp.unlink(path.join(dir, 'alpha.md'));

    ids = (await store.list()).map((q) => q.id).sort();
    onDisk = (await fsp.readdir(dir))
      .filter((f) => f.endsWith('.md'))
      .map((f) => f.slice(0, -3))
      .sort();
    expect(ids).toEqual(onDisk);
    expect(ids).not.toContain('alpha');
    expect(ids).toContain('beta');
  });

  it('does not scan subfolders for content (media/, .meta/, .trash/ are structural)', async () => {
    await store.save({ id: null, body: 'active one' });
    await fsp.mkdir(path.join(dir, 'media'), { recursive: true });
    await fsp.writeFile(path.join(dir, 'media', 'not-a-quki.md'), 'should never appear as a QuKi');

    const ids = (await store.list()).map((q) => q.id);
    expect(ids).not.toContain('not-a-quki');
    expect(ids).toHaveLength(1);
  });
});
