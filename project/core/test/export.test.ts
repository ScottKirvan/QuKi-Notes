import { gunzipSync } from 'node:zlib';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { QuKiStore } from '../src/index.js';
import { NodeFsBackend } from '../src/node.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

function readCString(buf: Buffer, start: number, length: number): string {
  const slice = buf.subarray(start, start + length);
  const nul = slice.indexOf(0);
  return (nul === -1 ? slice : slice.subarray(0, nul)).toString('utf8');
}

function parseOctal(buf: Buffer, start: number, length: number): number {
  const str = readCString(buf, start, length).trim();
  return str === '' ? 0 : parseInt(str, 8);
}

/** Minimal USTAR reader, written independently of core/src/tar.ts, purely to verify the archive round-trips. */
function parseTar(buf: Buffer): { path: string; content: Buffer }[] {
  const entries: { path: string; content: Buffer }[] = [];
  let offset = 0;
  while (offset + 512 <= buf.length) {
    const header = buf.subarray(offset, offset + 512);
    if (header.every((b) => b === 0)) break;
    const name = readCString(header, 0, 100);
    const prefix = readCString(header, 345, 155);
    const size = parseOctal(header, 124, 12);
    const fullPath = prefix ? `${prefix}/${name}` : name;
    offset += 512;
    entries.push({ path: fullPath, content: Buffer.from(buf.subarray(offset, offset + size)) });
    offset += Math.ceil(size / 512) * 512;
  }
  return entries;
}

describe('exportLibrary', () => {
  let dir: string;
  let store: QuKiStore;

  beforeEach(async () => {
    dir = await makeTempQuKiDir();
    store = new QuKiStore(new NodeFsBackend(dir));
  });

  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('bundles active QuKis, sidecars, trash and media into one archive that mirrors the folder', async () => {
    const image = await store.writeImage(new Uint8Array([5, 6, 7]), 'png');
    const active = await store.save({ id: null, body: `active body ![i](${image.relativePath})` });
    const trashed = await store.save({ id: null, body: 'trashed body' });
    if (active.status !== 'saved' || trashed.status !== 'saved') throw new Error('unreachable');
    await store.moveToTrash(trashed.id);

    const result = await store.exportLibrary();
    expect(result.activeCount).toBe(1);
    expect(result.trashCount).toBe(1);
    expect(result.mediaCount).toBe(1);

    const tar = gunzipSync(result.bytes);
    const entries = parseTar(Buffer.from(tar));
    const byPath = new Map(entries.map((e) => [e.path, e.content]));

    expect(byPath.get(`${active.id}.md`)?.toString('utf8')).toBe(`active body ![i](${image.relativePath})`);
    expect(byPath.get(`.meta/${active.id}.json`)).toBeDefined();
    expect(byPath.get(`.trash/${trashed.id}.md`)?.toString('utf8')).toBe('trashed body');
    expect(byPath.get(`.trash/.meta/${trashed.id}.json`)).toBeDefined();
    expect(byPath.get(image.relativePath)?.equals(Buffer.from([5, 6, 7]))).toBe(true);
  });
});
