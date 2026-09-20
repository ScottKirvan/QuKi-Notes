import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { QuKiStore } from '../../src/index.js';
import { OpfsBackend } from '../../src/opfsBackend.js';

async function freshRootName(): Promise<string> {
  return `opfs-test-${crypto.randomUUID()}`;
}

async function removeRoot(rootDirName: string): Promise<void> {
  const opfsRoot = await navigator.storage.getDirectory();
  await opfsRoot.removeEntry(rootDirName, { recursive: true }).catch(() => undefined);
}

describe('OpfsBackend against real OPFS (Chromium via Playwright)', () => {
  let rootDirName: string;

  beforeEach(async () => {
    rootDirName = await freshRootName();
  });

  afterEach(async () => {
    await removeRoot(rootDirName);
  });

  describe('StorageBackend primitives', () => {
    it('writes and reads text atomically', async () => {
      const backend = new OpfsBackend(rootDirName);
      await backend.writeTextAtomic('hello.md', '# Hello OPFS');
      expect(await backend.readText('hello.md')).toBe('# Hello OPFS');
    });

    it('writes and reads binary content', async () => {
      const backend = new OpfsBackend(rootDirName);
      const bytes = new Uint8Array([1, 2, 3, 4, 5]);
      await backend.writeBinaryAtomic('media/x.bin', bytes);
      const read = await backend.readBinary('media/x.bin');
      expect([...read]).toEqual([...bytes]);
    });

    it('creates parent directories implicitly on write, mirroring mkdirp', async () => {
      const backend = new OpfsBackend(rootDirName);
      await backend.writeTextAtomic('.meta/deep/nested.json', '{}');
      expect(await backend.exists('.meta/deep/nested.json')).toBe(true);
    });

    it('exists() is false for a path never written', async () => {
      const backend = new OpfsBackend(rootDirName);
      expect(await backend.exists('nope.md')).toBe(false);
    });

    it('stat() reports size and a modified time derived from the file, with no birthtime available', async () => {
      const backend = new OpfsBackend(rootDirName);
      await backend.writeTextAtomic('a.md', 'abc');
      const stat = await backend.stat('a.md');
      expect(stat.size).toBe(3);
      expect(stat.mtimeMs).toBeGreaterThan(0);
      expect(stat.birthtimeMs).toBe(0);
    });

    it('listDir() lists entries, and returns [] for a directory that does not exist', async () => {
      const backend = new OpfsBackend(rootDirName);
      await backend.writeTextAtomic('one.md', '1');
      await backend.writeTextAtomic('two.md', '2');
      const names = await backend.listDir('');
      expect(names.sort()).toEqual(['one.md', 'two.md']);
      expect(await backend.listDir('does-not-exist')).toEqual([]);
    });

    it('remove() deletes a file and is a silent no-op when the file is already gone', async () => {
      const backend = new OpfsBackend(rootDirName);
      await backend.writeTextAtomic('gone.md', 'x');
      await backend.remove('gone.md');
      expect(await backend.exists('gone.md')).toBe(false);
      await expect(backend.remove('gone.md')).resolves.toBeUndefined();
    });

    it('rename() moves a file between directories, and the old path no longer exists', async () => {
      const backend = new OpfsBackend(rootDirName);
      await backend.writeTextAtomic('a.md', 'body');
      await backend.rename('a.md', '.trash/a.md');
      expect(await backend.exists('a.md')).toBe(false);
      expect(await backend.readText('.trash/a.md')).toBe('body');
    });

    it('a writeTextAtomic that runs to completion is never observed half-written by a subsequent read', async () => {
      const backend = new OpfsBackend(rootDirName);
      const big = 'x'.repeat(200_000);
      await backend.writeTextAtomic('big.md', big);
      const read = await backend.readText('big.md');
      expect(read.length).toBe(big.length);
      expect(read).toBe(big);
    });
  });

  describe('genuine OPFS failures are not silently swallowed as "empty" or "false"', () => {
    it('listDir() throws (rather than returning []) when the target path exists but is a file, not a directory', async () => {
      const backend = new OpfsBackend(rootDirName);
      await backend.writeTextAtomic('not-a-dir.md', 'x');
      await expect(backend.listDir('not-a-dir.md')).rejects.toMatchObject({ name: 'TypeMismatchError' });
    });

    it('listDir() still returns [] for a directory that genuinely does not exist', async () => {
      const backend = new OpfsBackend(rootDirName);
      await expect(backend.listDir('never-created')).resolves.toEqual([]);
    });

    it('exists() still resolves true for a directory path via the file-then-directory fallback', async () => {
      const backend = new OpfsBackend(rootDirName);
      await backend.writeTextAtomic('adir/inner.md', 'x');
      expect(await backend.exists('adir')).toBe(true);
    });

    it('exists() throws (rather than returning false) when the underlying lookup fails for a reason other than not-found or wrong-type', async () => {
      const backend = new OpfsBackend(rootDirName);
      const original = FileSystemDirectoryHandle.prototype.getFileHandle;
      const simulatedFailure = new DOMException('simulated quota failure', 'QuotaExceededError');
      // getFileHandle/getDirectoryHandle can only realistically reject with
      // NotFoundError or TypeMismatchError in current Chromium - there is no
      // legitimate way to force a third kind of failure (a revoked
      // permission, exhausted quota) through the real API. This patches the
      // one underlying platform call exists() makes to simulate that class
      // of failure, while exercising the real OpfsBackend.exists() control
      // flow end to end.
      FileSystemDirectoryHandle.prototype.getFileHandle = async function (
        this: FileSystemDirectoryHandle,
        name: string,
        opts?: FileSystemGetFileOptions,
      ) {
        if (name === 'quota-fails.md') throw simulatedFailure;
        return original.call(this, name, opts);
      };
      try {
        await expect(backend.exists('quota-fails.md')).rejects.toBe(simulatedFailure);
      } finally {
        FileSystemDirectoryHandle.prototype.getFileHandle = original;
      }
    });
  });

  describe('path-escape guard', () => {
    it('rejects a relative path that walks above the root via ../', () => {
      const backend = new OpfsBackend(rootDirName);
      expect(() => backend.resolvePath('../outside.md')).toThrow(/escapes/);
      expect(() => backend.resolvePath('media/../../outside.md')).toThrow(/escapes/);
    });

    it('resolves an ordinary relative path without escaping', () => {
      const backend = new OpfsBackend(rootDirName);
      expect(backend.resolvePath('media/foo.png')).toBe('/media/foo.png');
      expect(backend.resolvePath('a/../b.md')).toBe('/b.md');
    });

    it('never lets a write or read past the root actually happen', async () => {
      const backend = new OpfsBackend(rootDirName);
      await expect(backend.writeTextAtomic('../../escape.md', 'x')).rejects.toThrow(/escapes/);
      await expect(backend.readText('../../escape.md')).rejects.toThrow(/escapes/);
    });
  });

  describe('STORAGE_CONTRACT acceptance tests, adapted to OPFS', () => {
    it('Test 1: a file placed by hand via direct OPFS calls appears in list() with no sidecar', async () => {
      const opfsRoot = await navigator.storage.getDirectory();
      const qukiDir = await opfsRoot.getDirectoryHandle(rootDirName, { create: true });
      const fileHandle = await qukiDir.getFileHandle('placed-by-hand.md', { create: true });
      const writable = await fileHandle.createWritable();
      await writable.write('# Hand placed\n\nNever went through the core API.');
      await writable.close();

      const store = new QuKiStore(new OpfsBackend(rootDirName));
      const list = await store.list();
      const entry = list.find((q) => q.id === 'placed-by-hand');

      expect(entry).toBeDefined();
      expect(entry!.filename).toBe('placed-by-hand.md');

      const detail = await store.read('placed-by-hand');
      expect(detail.body).toBe('# Hand placed\n\nNever went through the core API.');
    });

    it('Test 2: deleting the sidecar directory never hides a QuKi', async () => {
      const backend = new OpfsBackend(rootDirName);
      const store = new QuKiStore(backend);

      const saved = await store.save({ id: null, body: 'Has a sidecar with createdAt' });
      expect(saved.status).toBe('saved');
      if (saved.status !== 'saved') throw new Error('unreachable');

      const opfsRoot = await navigator.storage.getDirectory();
      const qukiDir = await opfsRoot.getDirectoryHandle(rootDirName, { create: true });
      await qukiDir.removeEntry('.meta', { recursive: true }).catch(() => undefined);

      const list = await store.list();
      const entry = list.find((q) => q.id === saved.id);
      expect(entry).toBeDefined();
      expect(entry!.createdAt).toBeTruthy();

      const detail = await store.read(saved.id);
      expect(detail.body).toBe('Has a sidecar with createdAt');
    });
  });

  describe('save-conflict scenario', () => {
    it('a save against a stale expectedModifiedAt returns a conflict rather than overwriting', async () => {
      const backend = new OpfsBackend(rootDirName);
      const store = new QuKiStore(backend);

      const created = await store.save({ id: null, body: 'original' });
      if (created.status !== 'saved') throw new Error('unreachable');

      const detail = await store.read(created.id);

      // File.lastModified has millisecond granularity; give the next write a
      // chance to land in a strictly later millisecond so the conflict check
      // (which compares mtime-derived ISO strings) can actually see a change.
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Someone else writes to the same QuKi first.
      const elsewhereWrite = await store.save({
        id: created.id,
        body: 'changed elsewhere',
        expectedModifiedAt: detail.modifiedAt,
      });
      expect(elsewhereWrite.status).toBe('saved');

      // Our save is still using the stale modifiedAt from before that write.
      const result = await store.save({
        id: created.id,
        body: 'our conflicting change',
        expectedModifiedAt: detail.modifiedAt,
      });

      expect(result.status).toBe('conflict');
      if (result.status !== 'conflict') throw new Error('unreachable');
      expect(result.reason).toBe('modified');
      expect(result.currentBody).toBe('changed elsewhere');

      // The conflicting write must never have landed on disk.
      const final = await store.read(created.id);
      expect(final.body).toBe('changed elsewhere');
    });

    it('a save against a QuKi deleted out from under it reports a deleted conflict', async () => {
      const backend = new OpfsBackend(rootDirName);
      const store = new QuKiStore(backend);

      const created = await store.save({ id: null, body: 'original' });
      if (created.status !== 'saved') throw new Error('unreachable');

      await store.moveToTrash(created.id);

      const result = await store.save({
        id: created.id,
        body: 'edit after delete',
        expectedModifiedAt: created.modifiedAt,
      });

      expect(result.status).toBe('conflict');
      if (result.status !== 'conflict') throw new Error('unreachable');
      expect(result.reason).toBe('deleted');
    });
  });
});
