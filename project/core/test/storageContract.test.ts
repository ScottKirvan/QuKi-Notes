import * as fsp from 'node:fs/promises';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { QuKiStore } from '../src/index.js';
import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

describe('STORAGE_CONTRACT acceptance tests', () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('Test 1: a .md file placed directly in the folder appears in the list with no sidecar, with the correct modified time', async () => {
    const target = path.join(dir, 'placed-by-hand.md');
    await fsp.writeFile(target, '# Hand placed\n\nNever went through the core API.');
    const stat = await fsp.stat(target);

    const list = await store.list();
    const entry = list.find((q) => q.id === 'placed-by-hand');

    expect(entry).toBeDefined();
    expect(entry!.filename).toBe('placed-by-hand.md');
    expect(entry!.modifiedAt).toBe(new Date(stat.mtimeMs).toISOString());

    const detail = await store.read('placed-by-hand');
    expect(detail.body).toBe('# Hand placed\n\nNever went through the core API.');
  });

  it('Test 2: deleting the sidecar directory never hides a QuKi, and intrinsic fields fall back to defaults', async () => {
    const saved = await store.save({ id: null, body: 'Has a sidecar with createdAt' });
    expect(saved.status).toBe('saved');
    if (saved.status !== 'saved') throw new Error('unreachable');

    await fsp.rm(path.join(dir, '.meta'), { recursive: true, force: true });

    const list = await store.list();
    const entry = list.find((q) => q.id === saved.id);
    expect(entry).toBeDefined();
    // createdAt fell back to something derivable (filesystem timestamp) rather than erroring or vanishing.
    expect(entry!.createdAt).toBeTruthy();

    const detail = await store.read(saved.id);
    expect(detail.body).toBe('Has a sidecar with createdAt');
  });
});
