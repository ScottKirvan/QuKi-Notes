import * as fsp from 'node:fs/promises';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { QuKiStore } from '../src/index.js';
import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

describe('QuKiStore.save', () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('creates a new QuKi when id is null and returns the generated id', async () => {
    const result = await store.save({ id: null, body: '# First QuKi' });
    expect(result.status).toBe('saved');
    if (result.status !== 'saved') throw new Error('unreachable');
    expect(result.id).toMatch(/^[0-9a-f-]{36}$/);

    const detail = await store.read(result.id);
    expect(detail.body).toBe('# First QuKi');
  });

  it('an empty body for a brand new QuKi creates nothing on disk', async () => {
    const result = await store.save({ id: null, body: '' });
    expect(result).toEqual({ status: 'skipped-empty', id: null });
    expect(await store.list()).toHaveLength(0);
  });

  it('clearing all text and saving leaves the previous content on disk (rule 16)', async () => {
    const created = await store.save({ id: null, body: 'keep me' });
    if (created.status !== 'saved') throw new Error('unreachable');

    const result = await store.save({ id: created.id, body: '', expectedModifiedAt: created.modifiedAt });
    expect(result.status).toBe('skipped-empty');

    const detail = await store.read(created.id);
    expect(detail.body).toBe('keep me');
  });

  it('updating without expectedModifiedAt is rejected rather than silently overwriting', async () => {
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');
    await expect(store.save({ id: created.id, body: 'v2' })).rejects.toThrow(TypeError);
  });

  it('detects an external edit and does not overwrite it (rule 17)', async () => {
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');

    const mdPath = path.join(dir, `${created.id}.md`);
    const future = new Date(Date.now() + 5000);
    await fsp.writeFile(mdPath, 'edited outside QuKi Notes');
    await fsp.utimes(mdPath, future, future);

    const result = await store.save({
      id: created.id,
      body: 'v2 from the editor',
      expectedModifiedAt: created.modifiedAt,
    });

    expect(result.status).toBe('conflict');
    if (result.status !== 'conflict') throw new Error('unreachable');
    expect(result.reason).toBe('modified');
    expect(result.currentBody).toBe('edited outside QuKi Notes');

    const onDisk = await fsp.readFile(mdPath, 'utf8');
    expect(onDisk).toBe('edited outside QuKi Notes');
  });

  it('a matching expectedModifiedAt saves cleanly and returns a fresh modifiedAt', async () => {
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');

    const result = await store.save({ id: created.id, body: 'v2', expectedModifiedAt: created.modifiedAt });
    expect(result.status).toBe('saved');
    if (result.status !== 'saved') throw new Error('unreachable');

    const detail = await store.read(created.id);
    expect(detail.body).toBe('v2');
    expect(detail.modifiedAt).toBe(result.modifiedAt);
  });

  it('reports a conflict, not an overwrite, when the QuKi was deleted out from under a queued save', async () => {
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(created.id);
    const result = await store.save({ id: created.id, body: 'v2', expectedModifiedAt: created.modifiedAt });

    expect(result.status).toBe('conflict');
    if (result.status !== 'conflict') throw new Error('unreachable');
    expect(result.reason).toBe('deleted');
  });

  it('a pending save cannot resurrect a QuKi deleted while the save was queued', async () => {
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');

    // Both calls are issued synchronously, back to back, before either is
    // awaited - this exercises the "save queued, then delete happens" race
    // rather than a delete-then-save sequence.
    const savePromise = store.save({ id: created.id, body: 'v2', expectedModifiedAt: created.modifiedAt });
    const deletePromise = store.moveToTrash(created.id);
    await Promise.all([savePromise, deletePromise]);

    const active = await store.list();
    expect(active.find((q) => q.id === created.id)).toBeUndefined();

    const trash = await store.listTrash();
    expect(trash.find((q) => q.id === created.id)).toBeDefined();
  });
});
