import type { StorageBackend } from './storageBackend.js';
import { buildTar, type TarEntry } from './tar.js';
import type { ExportResult } from './types.js';

async function collectEntries(backend: StorageBackend, relDir: string, filter: (name: string) => boolean): Promise<string[]> {
  const names = await backend.listDir(relDir);
  return names.filter(filter).map((name) => (relDir ? `${relDir}/${name}` : name));
}

async function toTarEntry(backend: StorageBackend, relPath: string): Promise<TarEntry> {
  const [content, stat] = await Promise.all([backend.readBinary(relPath), backend.stat(relPath)]);
  return { path: relPath, content, mtimeSeconds: Math.floor(stat.mtimeMs / 1000) };
}

/**
 * Uses the Web Streams CompressionStream global rather than node:zlib's
 * gzipSync so this module stays platform-agnostic - available in both
 * modern browsers and Node 18+, no import required.
 */
async function gzip(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data as unknown as BlobPart]).stream().pipeThrough(new CompressionStream('gzip'));
  const compressed = await new Response(stream).arrayBuffer();
  return new Uint8Array(compressed);
}

/**
 * Produces a gzipped tar mirroring the QuKi folder layout exactly
 * (*.md, .meta/*.json, .trash/, media/) - extracting it recreates a usable
 * QuKi folder with no translation step. This is the "one portable bundle"
 * required by STORAGE_CONTRACT.md; the destination to write it to is left
 * to the caller, since that is a filesystem-location decision outside the
 * QuKi folder the core is scoped to.
 */
export async function exportLibrary(backend: StorageBackend): Promise<ExportResult> {
  const activeMdRel = await collectEntries(backend, '', (n) => n.endsWith('.md'));
  const activeMetaRel = await collectEntries(backend, '.meta', (n) => n.endsWith('.json'));
  const trashMdRel = await collectEntries(backend, '.trash', (n) => n.endsWith('.md'));
  const trashMetaRel = await collectEntries(backend, '.trash/.meta', (n) => n.endsWith('.json'));
  const mediaRel = await collectEntries(backend, 'media', () => true);

  const allRelPaths = [...activeMdRel, ...activeMetaRel, ...trashMdRel, ...trashMetaRel, ...mediaRel];
  const entries = await Promise.all(allRelPaths.map((relPath) => toTarEntry(backend, relPath)));

  const tar = buildTar(entries);
  const bytes = await gzip(tar);

  return {
    bytes,
    activeCount: activeMdRel.length,
    trashCount: trashMdRel.length,
    mediaCount: mediaRel.length,
  };
}
