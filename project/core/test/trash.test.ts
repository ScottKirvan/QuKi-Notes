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

  // Ids are normally opaque UUIDs (createNew always calls crypto.randomUUID()),
  // but STORAGE_CONTRACT.md rule 1 makes any .md file placed directly in the
  // folder a QuKi too, so two different files can legitimately share the same
  // basename ("todo") over time. These tests write directly through the
  // backend to simulate that user-dropped-file scenario without going through
  // save()'s UUID-generating path.
  describe('name collisions', () => {
    it('trashing a second same-named QuKi does not destroy an earlier trashed copy with the same name', async () => {
      const backend = new NodeFsBackend(dir);

      // An earlier trashed copy already occupies .trash/todo.md.
      await backend.writeTextAtomic('.trash/todo.md', 'old trashed content');
      await backend.mkdirp('.trash/.meta');
      await backend.writeTextAtomic(
        '.trash/.meta/todo.json',
        JSON.stringify({ createdAt: '2020-01-01T00:00:00.000Z', deletedAt: '2020-01-02T00:00:00.000Z' }),
      );

      // A second, unrelated active file also named todo.md.
      await backend.writeTextAtomic('todo.md', 'new active content');

      await store.moveToTrash('todo');

      const trashItems = await store.listTrash();
      expect(trashItems).toHaveLength(2);

      const bodies = await Promise.all(trashItems.map((item) => store.readTrash(item.id)));
      const contents = bodies.map((b) => b.body).sort();
      expect(contents).toEqual(['new active content', 'old trashed content']);

      // Both entries report their real original name for display, even
      // though only one of them still occupies that name on disk.
      for (const item of trashItems) expect(item.originalId).toBe('todo');

      // The two on-disk entries must have distinct storage ids/filenames -
      // the collision must not have been silently overwritten.
      const storageIds = trashItems.map((item) => item.id);
      expect(new Set(storageIds).size).toBe(2);
    });

    it('restoring a QuKi whose original name collides with an active file restores it under a new name instead of overwriting', async () => {
      const backend = new NodeFsBackend(dir);

      await backend.writeTextAtomic('todo.md', 'trash me');
      await store.moveToTrash('todo');

      // A different active file now occupies the original name.
      await backend.writeTextAtomic('todo.md', 'unrelated new content');

      const result = await store.restore('todo');

      expect(result.renamed).toBe(true);
      expect(result.id).not.toBe('todo');

      // The active file that was already there must survive untouched.
      const stillActive = await store.read('todo');
      expect(stillActive.body).toBe('unrelated new content');

      // The restored QuKi must exist, intact, under its new name.
      const restored = await store.read(result.id);
      expect(restored.body).toBe('trash me');
    });

    it('restore reports renamed: false and keeps the original name when there is no collision', async () => {
      const created = await store.save({ id: null, body: 'no collision here' });
      if (created.status !== 'saved') throw new Error('unreachable');

      await store.moveToTrash(created.id);
      const result = await store.restore(created.id);

      expect(result.renamed).toBe(false);
      expect(result.id).toBe(created.id);
    });

    it('falls back to the storage id as the original name when the trash sidecar predates originalId', async () => {
      const backend = new NodeFsBackend(dir);
      await backend.writeTextAtomic('.trash/legacy.md', 'pre-fix trashed content');
      await backend.mkdirp('.trash/.meta');
      await backend.writeTextAtomic(
        '.trash/.meta/legacy.json',
        JSON.stringify({ createdAt: '2020-01-01T00:00:00.000Z', deletedAt: '2020-01-02T00:00:00.000Z' }),
      );

      const trashItems = await store.listTrash();
      expect(trashItems).toHaveLength(1);
      expect(trashItems[0]!.originalId).toBe('legacy');
    });
  });
});
