import * as fsp from 'node:fs/promises';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { QuKiStore } from '../src/index.js';
import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

describe('images', () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('writes image bytes under media/ and resolves an absolute path inside the QuKi folder', async () => {
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const result = await store.writeImage(bytes, 'png');

    expect(result.relativePath).toMatch(/^media\/[0-9a-f-]{36}\.png$/);

    const expectedAbsolute = path.join(dir, 'media', path.basename(result.relativePath));
    expect(path.normalize(result.absolutePath)).toBe(path.normalize(expectedAbsolute));
    expect(result.absolutePath.startsWith(path.normalize(dir))).toBe(true);

    const onDisk = await fsp.readFile(result.absolutePath);
    expect([...onDisk]).toEqual([1, 2, 3, 4]);
  });

  it('orphan cleanup counts references in the trash, so restoring a QuKi brings its images back', async () => {
    const image = await store.writeImage(new Uint8Array([9, 9, 9]), 'png');
    const body = `# Shared image\n\n![alt](${image.relativePath})`;

    const keeper = await store.save({ id: null, body });
    const other = await store.save({ id: null, body });
    if (keeper.status !== 'saved' || other.status !== 'saved') throw new Error('unreachable');

    // The keeper goes to trash but is never purged - it still references the image.
    await store.moveToTrash(keeper.id);

    // The other QuKi referencing the same image is trashed and permanently deleted.
    await store.moveToTrash(other.id);
    await store.permanentlyDelete(other.id);

    // The image must survive: the trashed "keeper" still references it.
    await expect(fsp.access(image.absolutePath)).resolves.toBeUndefined();

    // Restoring the keeper brings its image back intact.
    await store.restore(keeper.id);
    const restored = await store.read(keeper.id);
    expect(restored.body).toContain(image.relativePath);
    await expect(fsp.access(image.absolutePath)).resolves.toBeUndefined();

    // Now nothing references the image - permanently deleting the keeper cleans it up.
    await store.moveToTrash(keeper.id);
    await store.permanentlyDelete(keeper.id);
    await expect(fsp.access(image.absolutePath)).rejects.toThrow();
  });

  it('deleteOrphanedImages: false keeps the image even when nothing references it', async () => {
    const image = await store.writeImage(new Uint8Array([1]), 'png');
    const body = `![alt](${image.relativePath})`;
    const quki = await store.save({ id: null, body });
    if (quki.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(quki.id);
    await store.permanentlyDelete(quki.id, { deleteOrphanedImages: false });

    await expect(fsp.access(image.absolutePath)).resolves.toBeUndefined();
  });

  it('a path-traversal "image" reference never deletes the sibling file it points at', async () => {
    const keeper = await store.save({ id: null, body: '# Keep me\n\nImportant content.' });
    if (keeper.status !== 'saved') throw new Error('unreachable');
    const keeperPath = path.join(dir, `${keeper.id}.md`);

    // A body that names a sibling QuKi file through media/../ as if it were an image.
    const malicious = await store.save({ id: null, body: `![alt](media/../${keeper.id}.md)` });
    if (malicious.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(malicious.id);
    await store.permanentlyDelete(malicious.id);

    // The sibling QuKi must survive - it was never a real orphaned image.
    await expect(fsp.access(keeperPath)).resolves.toBeUndefined();
    const stillThere = await store.read(keeper.id);
    expect(stillThere.body).toBe('# Keep me\n\nImportant content.');
  });

  it('a path-traversal reference in the trash during emptyTrash also spares the sibling file', async () => {
    const keeper = await store.save({ id: null, body: '# Keep me too' });
    if (keeper.status !== 'saved') throw new Error('unreachable');
    const keeperPath = path.join(dir, `${keeper.id}.md`);

    const malicious = await store.save({ id: null, body: `![alt](media/../${keeper.id}.md)` });
    if (malicious.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(malicious.id);
    await store.emptyTrash();

    await expect(fsp.access(keeperPath)).resolves.toBeUndefined();
  });

  it('a genuine orphaned image in media/ is still cleaned up', async () => {
    const image = await store.writeImage(new Uint8Array([7, 7, 7]), 'png');
    const body = `![alt](${image.relativePath})`;
    const quki = await store.save({ id: null, body });
    if (quki.status !== 'saved') throw new Error('unreachable');

    await store.moveToTrash(quki.id);
    await store.permanentlyDelete(quki.id);

    await expect(fsp.access(image.absolutePath)).rejects.toThrow();
  });
});
