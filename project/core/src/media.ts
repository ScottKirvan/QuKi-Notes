import type { StorageBackend } from './storageBackend.js';
import type { WriteImageResult } from './types.js';

const IMAGE_REF_PATTERN = /!\[[^\]]*\]\((media\/[^)\s]+)\)/g;

export function findImageReferences(body: string): string[] {
  const refs = new Set<string>();
  for (const match of body.matchAll(IMAGE_REF_PATTERN)) {
    refs.add(match[1]);
  }
  return [...refs];
}

const MEDIA_PREFIX = 'media/';

/**
 * A markdown image reference is only a genuine orphan candidate if it names
 * a direct child of media/ that actually exists there. This is checked
 * against a real directory listing rather than by normalizing or validating
 * the reference string, so a reference like `media/../notes.md` - which
 * resolves outside media/ to an unrelated QuKi file - can never be confused
 * for an image: no real media/ listing will ever contain an entry literally
 * named `../notes.md`.
 */
export function isOrphanCandidate(ref: string, mediaDirEntries: Iterable<string>): boolean {
  if (!ref.startsWith(MEDIA_PREFIX)) return false;
  const name = ref.slice(MEDIA_PREFIX.length);
  if (name === '' || name.includes('/') || name.includes('\\')) return false;
  const entries = mediaDirEntries instanceof Set ? mediaDirEntries : new Set(mediaDirEntries);
  return entries.has(name);
}

/**
 * StorageBackend has no is-directory flag, and listDir/stat can't tell a
 * folder from a file on every backend (Android's listDir returns [] for a
 * file; Node's stat succeeds on a folder). Reading as a file fails for a
 * folder on all of them - the same test export.ts's collectFilesRecursive
 * uses. Anything that can't be read is treated as not-a-file, so a caller
 * deciding whether to delete only ever deletes what it positively read.
 */
export async function isReadableFile(backend: StorageBackend, relPath: string): Promise<boolean> {
  try {
    await backend.readBinary(relPath);
    return true;
  } catch {
    return false;
  }
}

export async function writeImage(
  backend: StorageBackend,
  bytes: Uint8Array,
  extension: string,
): Promise<WriteImageResult> {
  const ext = extension.startsWith('.') ? extension : `.${extension}`;
  const relativePath = `media/${crypto.randomUUID()}${ext}`;
  await backend.writeBinaryAtomic(relativePath, bytes);
  return { relativePath, absolutePath: backend.resolvePath(relativePath) };
}
