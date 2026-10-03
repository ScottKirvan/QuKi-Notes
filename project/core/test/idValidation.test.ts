import * as fsp from 'node:fs/promises';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { InvalidIdError, QuKiStore } from '../src/index.js';
import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

describe('QuKiStore rejects ids that are not a plain root-level filename', () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  const badIds = ['.trash/a', 'sub/x', '..', '../escape', 'a/b/c', '.hidden', '.meta/x', 'a\\b'];

  describe('read', () => {
    for (const id of badIds) {
      it(`rejects "${id}"`, async () => {
        await expect(store.read(id)).rejects.toThrow(InvalidIdError);
      });
    }

    it('a crafted id never actually reads a trashed file as if it were active', async () => {
      const created = await store.save({ id: null, body: 'trashed content' });
      if (created.status !== 'saved') throw new Error('unreachable');
      await store.moveToTrash(created.id);

      await expect(store.read(`.trash/${created.id}`)).rejects.toThrow(InvalidIdError);
    });
  });

  describe('readTrash', () => {
    for (const id of badIds) {
      it(`rejects "${id}"`, async () => {
        await expect(store.readTrash(id)).rejects.toThrow(InvalidIdError);
      });
    }
  });

  describe('save (update path)', () => {
    for (const id of badIds) {
      it(`rejects "${id}"`, async () => {
        await expect(store.save({ id, body: 'x', expectedModifiedAt: new Date().toISOString() })).rejects.toThrow(
          InvalidIdError,
        );
      });
    }

    it('a crafted id never writes outside the flat folder structure', async () => {
      await expect(
        store.save({ id: 'sub/x', body: 'escape attempt', expectedModifiedAt: new Date().toISOString() }),
      ).rejects.toThrow(InvalidIdError);
      expect(await fsp.readdir(dir).then((names) => names.includes('sub'))).toBe(false);
    });
  });

  describe('moveToTrash', () => {
    for (const id of badIds) {
      it(`rejects "${id}"`, async () => {
        await expect(store.moveToTrash(id)).rejects.toThrow(InvalidIdError);
      });
    }
  });

  describe('restore', () => {
    for (const id of badIds) {
      it(`rejects "${id}"`, async () => {
        await expect(store.restore(id)).rejects.toThrow(InvalidIdError);
      });
    }
  });

  describe('permanentlyDelete', () => {
    for (const id of badIds) {
      it(`rejects "${id}"`, async () => {
        await expect(store.permanentlyDelete(id)).rejects.toThrow(InvalidIdError);
      });
    }
  });

  it('an ordinary generated id is accepted', async () => {
    const created = await store.save({ id: null, body: 'fine' });
    if (created.status !== 'saved') throw new Error('unreachable');
    await expect(store.read(created.id)).resolves.toBeDefined();
  });

  it('an ordinary hand-placed filename id (no dots, no separators) is accepted', async () => {
    await fsp.writeFile(path.join(dir, 'my-notes.md'), 'hello');
    await expect(store.read('my-notes')).resolves.toBeDefined();
  });
});
