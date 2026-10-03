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
 * Walks relDir depth-first and returns a TarEntry for every file underneath
 * it, at any depth. StorageBackend has no isDirectory/stat.isDirectory - the
 * only way to tell a subfolder from a file with what the interface actually
 * exposes is to try reading it as a file and see whether that fails the way
 * a directory read fails (Node's EISDIR, OPFS's TypeMismatchError, Android's
 * "(Is a directory)" FileNotFoundException - all three confirmed by reading
 * each backend's readBinary). A name that fails that read is recursed into
 * via listDir instead of being treated as a file; a name whose read fails
 * for any other reason (permissions, corruption) surfaces that error
 * unchanged, since listDir-ing an actual file throws too (ENOTDIR on Node,
 * TypeMismatchError on OPFS) rather than silently returning no entries.
 * Used for `media/` and `.quki/`, the two directories STORAGE_CONTRACT.md
 * allows arbitrary nested content under; `.md`/`.meta` collection stays flat
 * via collectEntries above since that layout is never nested.
 */
async function collectFilesRecursive(backend: StorageBackend, relDir: string): Promise<TarEntry[]> {
  const names = await backend.listDir(relDir);
  const entries: TarEntry[] = [];
  for (const name of names) {
    const relPath = relDir ? `${relDir}/${name}` : name;
    try {
      entries.push(await toTarEntry(backend, relPath));
    } catch {
      entries.push(...(await collectFilesRecursive(backend, relPath)));
    }
  }
  return entries;
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
 * (*.md, .meta/*.json, .trash/, media/, .quki/) - extracting it recreates a
 * usable QuKi folder with no translation step. This is the "one portable
 * bundle" required by STORAGE_CONTRACT.md; the destination to write it to is
 * left to the caller, since that is a filesystem-location decision outside
 * the QuKi folder the core is scoped to. `.quki/` is walked and included
 * whole (rule 20: "included as a whole, not item by item, so export never
 * has to be updated as `.quki/` grows"), not enumerated by known filename
 * patterns the way `.md`/`.meta` are.
 */
export async function exportLibrary(backend: StorageBackend): Promise<ExportResult> {
  const activeMdRel = await collectEntries(backend, '', (n) => n.endsWith('.md'));
  const activeMetaRel = await collectEntries(backend, '.meta', (n) => n.endsWith('.json'));
  const trashMdRel = await collectEntries(backend, '.trash', (n) => n.endsWith('.md'));
  const trashMetaRel = await collectEntries(backend, '.trash/.meta', (n) => n.endsWith('.json'));

  const [activeMdEntries, activeMetaEntries, trashMdEntries, trashMetaEntries, mediaEntries, quKiConfigEntries] = await Promise.all([
    Promise.all(activeMdRel.map((relPath) => toTarEntry(backend, relPath))),
    Promise.all(activeMetaRel.map((relPath) => toTarEntry(backend, relPath))),
    Promise.all(trashMdRel.map((relPath) => toTarEntry(backend, relPath))),
    Promise.all(trashMetaRel.map((relPath) => toTarEntry(backend, relPath))),
    collectFilesRecursive(backend, 'media'),
    collectFilesRecursive(backend, '.quki'),
  ]);

  const entries = [...activeMdEntries, ...activeMetaEntries, ...trashMdEntries, ...trashMetaEntries, ...mediaEntries, ...quKiConfigEntries];

  const tar = buildTar(entries);
  const bytes = await gzip(tar);

  return {
    bytes,
    activeCount: activeMdRel.length,
    trashCount: trashMdRel.length,
    mediaCount: mediaEntries.length,
  };
}
