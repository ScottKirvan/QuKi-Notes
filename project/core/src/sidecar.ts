import type { StorageBackend } from './storageBackend.js';

export interface SidecarData {
  createdAt?: string;
  deletedAt?: string;
}

/**
 * A missing, unreadable or malformed sidecar is never an error here - it is
 * just an absence of intrinsic data (STORAGE_CONTRACT.md rule 7). Callers
 * fall back to defaults for whatever field is missing.
 */
export async function readSidecar(backend: StorageBackend, relPath: string): Promise<SidecarData> {
  if (!(await backend.exists(relPath))) return {};
  try {
    const raw = await backend.readText(relPath);
    const parsed = JSON.parse(raw) as unknown;
    if (parsed === null || typeof parsed !== 'object') return {};
    const data = parsed as Record<string, unknown>;
    const result: SidecarData = {};
    if (typeof data.createdAt === 'string') result.createdAt = data.createdAt;
    if (typeof data.deletedAt === 'string') result.deletedAt = data.deletedAt;
    return result;
  } catch {
    return {};
  }
}

export async function writeSidecar(backend: StorageBackend, relPath: string, data: SidecarData): Promise<void> {
  await backend.writeTextAtomic(relPath, JSON.stringify(data));
}
