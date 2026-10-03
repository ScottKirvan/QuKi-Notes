import type { StorageBackend } from './storageBackend.js';

export interface SidecarData {
  createdAt?: string;
  deletedAt?: string;
  /**
   * Trash sidecar only: the id/filename the QuKi had in the active folder
   * when it was trashed. The on-disk name under .trash/ can differ from this
   * when that name was already taken by an earlier trashed QuKi - this field
   * is what the Trash screen displays and what restore() restores under.
   */
  originalId?: string;
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
    if (typeof data.originalId === 'string') result.originalId = data.originalId;
    return result;
  } catch {
    return {};
  }
}

export async function writeSidecar(backend: StorageBackend, relPath: string, data: SidecarData): Promise<void> {
  await backend.writeTextAtomic(relPath, JSON.stringify(data));
}
