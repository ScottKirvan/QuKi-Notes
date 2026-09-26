import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { QuKiStore } from '../src/index.js';
import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

describe('search', () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('matches anywhere in the body, case-insensitively, trimmed', async () => {
    const matching = await store.save({ id: null, body: 'The quick Brown Fox' });
    const other = await store.save({ id: null, body: 'nothing relevant here' });
    if (matching.status !== 'saved' || other.status !== 'saved') throw new Error('unreachable');

    const results = await store.search('  brown  '.trim());
    const ids = results.map((r) => r.id);
    expect(ids).toContain(matching.id);
    expect(ids).not.toContain(other.id);
  });

  it('an empty query returns the full active list', async () => {
    await store.save({ id: null, body: 'a' });
    await store.save({ id: null, body: 'b' });
    const results = await store.search('   ');
    expect(results).toHaveLength(2);
  });

  it('excludes trash by default, and includes it only when asked', async () => {
    const trashed = await store.save({ id: null, body: 'unique-marker-xyz' });
    if (trashed.status !== 'saved') throw new Error('unreachable');
    await store.moveToTrash(trashed.id);

    const withoutTrash = await store.search('unique-marker-xyz');
    expect(withoutTrash).toHaveLength(0);

    const withTrash = await store.search('unique-marker-xyz', { includeTrash: true });
    expect(withTrash.map((r) => r.id)).toContain(trashed.id);
  });
});
