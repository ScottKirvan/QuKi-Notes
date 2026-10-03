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

  it('cleans up the orphaned .md file when the sidecar write fails, so a retry does not create a duplicate', async () => {
    // Pre-creating .meta as a plain file (not a directory) makes the
    // sidecar's own mkdir fail with EEXIST, simulating any sidecar-write
    // failure after the .md file has already landed on disk.
    await fsp.writeFile(path.join(dir, '.meta'), 'blocks .meta/ from being created as a directory');

    await expect(store.save({ id: null, body: 'should not survive the failed sidecar write' })).rejects.toThrow();

    const entries = await fsp.readdir(dir);
    expect(entries.filter((f) => f.endsWith('.md'))).toHaveLength(0);
  });

  it('an empty body for a brand new QuKi creates nothing on disk', async () => {
    const result = await store.save({ id: null, body: '' });
    expect(result).toEqual({ status: 'skipped-empty', id: null });
    expect(await store.list()).toHaveLength(0);
  });

  it('clearing all text of an existing QuKi and saving writes the empty file', async () => {
    const created = await store.save({ id: null, body: 'about to be cleared' });
    if (created.status !== 'saved') throw new Error('unreachable');

    const result = await store.save({ id: created.id, body: '', expectedModifiedAt: created.modifiedAt });
    expect(result.status).toBe('saved');

    const detail = await store.read(created.id);
    expect(detail.body).toBe('');
    expect(await fsp.readFile(path.join(dir, `${created.id}.md`), 'utf8')).toBe('');
    expect((await store.list()).map((q) => q.id)).toEqual([created.id]);
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

  it('a genuine external edit is still a conflict even when expectedBody is supplied', async () => {
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
      expectedBody: 'v1', // what the editor still believes is on disk
    });

    expect(result.status).toBe('conflict');
    if (result.status !== 'conflict') throw new Error('unreachable');
    expect(result.currentBody).toBe('edited outside QuKi Notes');

    const onDisk = await fsp.readFile(mdPath, 'utf8');
    expect(onDisk).toBe('edited outside QuKi Notes');
  });

  it('a timestamp-only mismatch with byte-identical content is not a conflict', async () => {
    // Reproduces the false-positive reported on Android's scoped-storage
    // (FUSE) backend: the app sits backgrounded for a while and the file's
    // reported mtime drifts with nothing having actually written to it. No
    // other writer could coincidentally reproduce byte-identical content, so
    // this must save cleanly rather than block on a conflict banner.
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');

    const mdPath = path.join(dir, `${created.id}.md`);
    const future = new Date(Date.now() + 5000);
    await fsp.utimes(mdPath, future, future); // mtime moves; content does not

    const result = await store.save({
      id: created.id,
      body: 'v2 from the editor',
      expectedModifiedAt: created.modifiedAt,
      expectedBody: 'v1', // matches what's still actually on disk
    });

    expect(result.status).toBe('saved');
    if (result.status !== 'saved') throw new Error('unreachable');

    const detail = await store.read(created.id);
    expect(detail.body).toBe('v2 from the editor');
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

  it('force: true writes through a real "modified" conflict instead of reporting it', async () => {
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');

    const mdPath = path.join(dir, `${created.id}.md`);
    const future = new Date(Date.now() + 5000);
    await fsp.writeFile(mdPath, 'edited outside QuKi Notes');
    await fsp.utimes(mdPath, future, future);

    const result = await store.save({
      id: created.id,
      body: 'forced overwrite content',
      expectedModifiedAt: created.modifiedAt,
      force: true,
    });

    expect(result.status).toBe('saved');
    if (result.status !== 'saved') throw new Error('unreachable');

    const detail = await store.read(created.id);
    expect(detail.body).toBe('forced overwrite content');
    expect(detail.modifiedAt).toBe(result.modifiedAt);
  });

  it('force: true recreates the file after a real "deleted" conflict instead of reporting it', async () => {
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(created.id);

    const result = await store.save({
      id: created.id,
      body: 'recreated after deletion',
      expectedModifiedAt: created.modifiedAt,
      force: true,
    });

    expect(result.status).toBe('saved');
    if (result.status !== 'saved') throw new Error('unreachable');

    const detail = await store.read(created.id);
    expect(detail.body).toBe('recreated after deletion');
  });

  it('force: true with an empty body overwrites the file with the empty body', async () => {
    const created = await store.save({ id: null, body: 'about to be cleared' });
    if (created.status !== 'saved') throw new Error('unreachable');

    const mdPath = path.join(dir, `${created.id}.md`);
    const future = new Date(Date.now() + 5000);
    await fsp.writeFile(mdPath, 'edited outside QuKi Notes');
    await fsp.utimes(mdPath, future, future);

    const result = await store.save({
      id: created.id,
      body: '',
      expectedModifiedAt: created.modifiedAt,
      force: true,
    });

    expect(result.status).toBe('saved');

    const onDisk = await fsp.readFile(mdPath, 'utf8');
    expect(onDisk).toBe('');
  });

  it('a forced save still goes through the same per-id runExclusive queue as a normal save', async () => {
    const created = await store.save({ id: null, body: 'v1' });
    if (created.status !== 'saved') throw new Error('unreachable');

    // Issued back to back, unawaited, so both are queued on the same id at
    // once: this exercises queue ordering, not real concurrency.
    const normalPromise = store.save({ id: created.id, body: 'from normal save', expectedModifiedAt: created.modifiedAt });
    const forcedPromise = store.save({
      id: created.id,
      body: 'from forced save',
      expectedModifiedAt: created.modifiedAt,
      force: true,
    });

    const [normalResult, forcedResult] = await Promise.all([normalPromise, forcedPromise]);

    // Whichever ran second in the queue determines what's on disk; both
    // must be clean, sequential results, never an interleaved/torn write.
    expect(['saved', 'conflict']).toContain(normalResult.status);
    expect(forcedResult.status).toBe('saved');

    const detail = await store.read(created.id);
    expect(['from normal save', 'from forced save']).toContain(detail.body);
  });
});
