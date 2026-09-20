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
