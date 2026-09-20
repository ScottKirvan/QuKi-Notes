import * as fsp from 'node:fs/promises';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { NotFoundError, QuKiStore } from '../src/index.js';
import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

describe('trash', () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('moves a QuKi to trash, stamps deletedAt, and restores it with createdAt intact', async () => {
    const created = await store.save({ id: null, body: 'trash me' });
    if (created.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(created.id);

    expect((await store.list()).find((q) => q.id === created.id)).toBeUndefined();
    const trashEntry = (await store.listTrash()).find((q) => q.id === created.id);
    expect(trashEntry).toBeDefined();
    expect(trashEntry!.deletedAt).toBeTruthy();
    expect(trashEntry!.createdAt).toBe(created.createdAt);

    await store.restore(created.id);

    expect((await store.listTrash()).find((q) => q.id === created.id)).toBeUndefined();
    const restored = await store.read(created.id);
    expect(restored.body).toBe('trash me');
    expect(restored.createdAt).toBe(created.createdAt);
  });

  it('throws NotFoundError for an id that is not in the trash', async () => {
    await expect(store.restore('nope')).rejects.toThrow(NotFoundError);
  });

  it('throws NotFoundError trashing an id that does not exist', async () => {
    await expect(store.moveToTrash('nope')).rejects.toThrow(NotFoundError);
  });

  it('purgeExpiredTrash removes items past the 30-day hold and leaves recent ones', async () => {
    const old = await store.save({ id: null, body: 'old enough to purge' });
    const recent = await store.save({ id: null, body: 'too recent to purge' });
    if (old.status !== 'saved' || recent.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(old.id);
    await store.moveToTrash(recent.id);

    const in31Days = new Date(Date.now() + 31 * 24 * 60 * 60 * 1000);
    const result = await store.purgeExpiredTrash({ now: in31Days });

    expect(result.purgedIds).toContain(old.id);
    expect(result.purgedIds).toContain(recent.id);
  });

  it('does not purge items whose deletedAt is unknown (missing sidecar) - never guess a deletion time', async () => {
    const target = await store.save({ id: null, body: 'sidecar will be removed' });
    if (target.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(target.id);
    await fsp.rm(path.join(dir, '.trash', '.meta', `${target.id}.json`), { force: true });

    const farFuture = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
    const result = await store.purgeExpiredTrash({ now: farFuture });

    expect(result.purgedIds).not.toContain(target.id);
    expect((await store.listTrash()).find((q) => q.id === target.id)).toBeDefined();
  });

  it('emptyTrash clears everything regardless of age', async () => {
    const a = await store.save({ id: null, body: 'a' });
    const b = await store.save({ id: null, body: 'b' });
    if (a.status !== 'saved' || b.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(a.id);
    await store.moveToTrash(b.id);

    const result = await store.emptyTrash();
    expect(result.deletedCount).toBe(2);
    expect(await store.listTrash()).toHaveLength(0);
  });
});
