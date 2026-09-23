export interface QuKiSummary {
  id: string;
  filename: string;
  createdAt: string;
  modifiedAt: string;
}

export interface TrashedQuKiSummary extends QuKiSummary {
  deletedAt: string | null;
}

export interface QuKiDetail {
  id: string;
  filename: string;
  body: string;
  createdAt: string;
  modifiedAt: string;
}

export type SaveResult =
  | { status: 'saved'; id: string; filename: string; createdAt: string; modifiedAt: string }
  | { status: 'skipped-empty'; id: string | null }
  | {
      status: 'conflict';
      id: string;
      reason: 'modified' | 'deleted';
      currentModifiedAt: string | null;
      currentBody: string | null;
    };

export interface SaveParams {
  id: string | null;
  body: string;
  expectedModifiedAt?: string;
  /**
   * Explicit, user-initiated escape hatch from a conflict (STORAGE_CONTRACT.md
   * rule 17): skips the expectedModifiedAt comparison and the deleted-file
   * conflict branch, writing unconditionally. Only ever set by a user
   * clicking "Overwrite" on an already-shown conflict banner - never by the
   * automatic debounce/interval save path, which must stay exactly as
   * strict as before.
   */
  force?: boolean;
}

export interface DeleteOptions {
  deleteOrphanedImages?: boolean;
}

export interface WriteImageResult {
  relativePath: string;
  absolutePath: string;
}

export interface ExportResult {
  /** A gzipped tar archive mirroring the QuKi folder layout (*.md, .meta/, .trash/, media/). */
  bytes: Uint8Array;
  activeCount: number;
  trashCount: number;
  mediaCount: number;
}

export class NotFoundError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NotFoundError';
  }
}
