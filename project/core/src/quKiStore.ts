import { exportLibrary as buildExport } from './export.js';
import { findImageReferences, writeImage as writeImageFile } from './media.js';
import { readSidecar, writeSidecar, type SidecarData } from './sidecar.js';
import type { FileStat, StorageBackend } from './storageBackend.js';
import {
  NotFoundError,
  type DeleteOptions,
  type ExportResult,
  type QuKiDetail,
  type QuKiSummary,
  type SaveParams,
  type SaveResult,
  type TrashedQuKiSummary,
  type WriteImageResult,
} from './types.js';

const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

function toIso(ms: number): string {
  return new Date(ms).toISOString();
}

export class QuKiStore {
  private readonly queues = new Map<string, Promise<unknown>>();

  constructor(private readonly backend: StorageBackend) {}

  private runExclusive<T>(id: string, fn: () => Promise<T>): Promise<T> {
    const prior = this.queues.get(id) ?? Promise.resolve();
    const run = prior.then(fn, fn);
    this.queues.set(
      id,
      run.then(
        () => undefined,
        () => undefined,
      ),
    );
    return run;
  }

  private resolveCreatedAt(stat: FileStat, sidecar: SidecarData): string {
    if (sidecar.createdAt) return sidecar.createdAt;
    const birthMs = stat.birthtimeMs > 0 ? stat.birthtimeMs : stat.mtimeMs;
    return toIso(birthMs);
  }

  private async listActiveIds(): Promise<string[]> {
    const names = await this.backend.listDir('');
    return names.filter((n) => n.endsWith('.md')).map((n) => n.slice(0, -3));
  }

  private async listTrashIds(): Promise<string[]> {
    const names = await this.backend.listDir('.trash');
    return names.filter((n) => n.endsWith('.md')).map((n) => n.slice(0, -3));
  }

  async list(): Promise<QuKiSummary[]> {
    const ids = await this.listActiveIds();
    const summaries = await Promise.all(ids.map((id) => this.buildActiveSummary(id)));
    summaries.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt));
    return summaries;
  }

  private async buildActiveSummary(id: string): Promise<QuKiSummary> {
    const mdPath = `${id}.md`;
    const stat = await this.backend.stat(mdPath);
    const sidecar = await readSidecar(this.backend, `.meta/${id}.json`);
    return {
      id,
      filename: `${id}.md`,
      createdAt: this.resolveCreatedAt(stat, sidecar),
      modifiedAt: toIso(stat.mtimeMs),
    };
  }

  async listTrash(): Promise<TrashedQuKiSummary[]> {
    const ids = await this.listTrashIds();
    const summaries = await Promise.all(ids.map((id) => this.buildTrashSummary(id)));
    summaries.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt));
    return summaries;
  }

  private async buildTrashSummary(id: string): Promise<TrashedQuKiSummary> {
    const mdPath = `.trash/${id}.md`;
    const stat = await this.backend.stat(mdPath);
    const sidecar = await readSidecar(this.backend, `.trash/.meta/${id}.json`);
    return {
      id,
      filename: `${id}.md`,
      createdAt: this.resolveCreatedAt(stat, sidecar),
      modifiedAt: toIso(stat.mtimeMs),
      deletedAt: sidecar.deletedAt ?? null,
    };
  }

  async read(id: string): Promise<QuKiDetail> {
    const mdPath = `${id}.md`;
    if (!(await this.backend.exists(mdPath))) throw new NotFoundError(`QuKi not found: ${id}`);
    const [body, stat, sidecar] = await Promise.all([
      this.backend.readText(mdPath),
      this.backend.stat(mdPath),
      readSidecar(this.backend, `.meta/${id}.json`),
    ]);
    return {
      id,
      filename: `${id}.md`,
      body,
      createdAt: this.resolveCreatedAt(stat, sidecar),
      modifiedAt: toIso(stat.mtimeMs),
    };
  }

  async readTrash(id: string): Promise<QuKiDetail> {
    const mdPath = `.trash/${id}.md`;
    if (!(await this.backend.exists(mdPath))) throw new NotFoundError(`Trashed QuKi not found: ${id}`);
    const [body, stat, sidecar] = await Promise.all([
      this.backend.readText(mdPath),
      this.backend.stat(mdPath),
      readSidecar(this.backend, `.trash/.meta/${id}.json`),
    ]);
    return {
      id,
      filename: `${id}.md`,
      body,
      createdAt: this.resolveCreatedAt(stat, sidecar),
      modifiedAt: toIso(stat.mtimeMs),
    };
  }

  async save(params: SaveParams): Promise<SaveResult> {
    if (params.id === null) {
      return this.createNew(params.body);
    }
    const id = params.id;
    return this.runExclusive(id, () =>
      this.updateExisting(id, params.body, params.expectedModifiedAt, params.force ?? false),
    );
  }

  private async createNew(body: string): Promise<SaveResult> {
    if (body === '') {
      return { status: 'skipped-empty', id: null };
    }
    const id = crypto.randomUUID();
    const mdPath = `${id}.md`;
    const createdAt = new Date().toISOString();
    await this.backend.writeTextAtomic(mdPath, body);
    await writeSidecar(this.backend, `.meta/${id}.json`, { createdAt });
    const stat = await this.backend.stat(mdPath);
    return {
      status: 'saved',
      id,
      filename: `${id}.md`,
      createdAt,
      modifiedAt: toIso(stat.mtimeMs),
    };
  }

  private async updateExisting(
    id: string,
    body: string,
    expectedModifiedAt: string | undefined,
    force: boolean,
  ): Promise<SaveResult> {
    if (expectedModifiedAt === undefined) {
      throw new TypeError(
        'QuKiStore.save: expectedModifiedAt is required when updating an existing QuKi. Read the QuKi first and pass back its modifiedAt.',
      );
    }
    const mdPath = `${id}.md`;
    const exists = await this.backend.exists(mdPath);

    // force (STORAGE_CONTRACT.md rule 17's explicit, user-initiated
    // escape hatch): skip both conflict branches below and write
    // unconditionally - creating the file if it was deleted, overwriting it
    // if it was modified. Rule 16 (never write an empty body) still applies
    // unconditionally further down, so force can never wipe a QuKi via an
    // accidental empty overwrite.
    let priorStat: FileStat | undefined;
    if (!force) {
      if (!exists) {
        return { status: 'conflict', id, reason: 'deleted', currentModifiedAt: null, currentBody: null };
      }
      priorStat = await this.backend.stat(mdPath);
      const currentModifiedAt = toIso(priorStat.mtimeMs);
      if (currentModifiedAt !== expectedModifiedAt) {
        const currentBody = await this.backend.readText(mdPath);
        return { status: 'conflict', id, reason: 'modified', currentModifiedAt, currentBody };
      }
    } else if (exists) {
      // Preserve the original createdAt (via birthtimeMs fallback in
      // resolveCreatedAt) across a forced overwrite of a file that still
      // exists - forcing a write is about the content, not about resetting
      // the QuKi's creation time.
      priorStat = await this.backend.stat(mdPath);
    }

    if (body === '') {
      return { status: 'skipped-empty', id };
    }

    const sidecar = await readSidecar(this.backend, `.meta/${id}.json`);
    await this.backend.writeTextAtomic(mdPath, body);
    const newStat = await this.backend.stat(mdPath);
    return {
      status: 'saved',
      id,
      filename: `${id}.md`,
      createdAt: this.resolveCreatedAt(priorStat ?? newStat, sidecar),
      modifiedAt: toIso(newStat.mtimeMs),
    };
  }

  async moveToTrash(id: string): Promise<void> {
    await this.runExclusive(id, async () => {
      const mdPath = `${id}.md`;
      const metaPath = `.meta/${id}.json`;
      if (!(await this.backend.exists(mdPath))) throw new NotFoundError(`QuKi not found: ${id}`);

      const stat = await this.backend.stat(mdPath);
      const sidecar = await readSidecar(this.backend, metaPath);
      const createdAt = this.resolveCreatedAt(stat, sidecar);

      await this.backend.rename(mdPath, `.trash/${id}.md`);
      if (await this.backend.exists(metaPath)) await this.backend.remove(metaPath);
      await writeSidecar(this.backend, `.trash/.meta/${id}.json`, {
        createdAt,
        deletedAt: new Date().toISOString(),
      });
    });
  }

  async restore(id: string): Promise<void> {
    await this.runExclusive(id, async () => {
      const trashMdPath = `.trash/${id}.md`;
      const trashMetaPath = `.trash/.meta/${id}.json`;
      if (!(await this.backend.exists(trashMdPath))) throw new NotFoundError(`Trashed QuKi not found: ${id}`);

      const sidecar = await readSidecar(this.backend, trashMetaPath);

      await this.backend.rename(trashMdPath, `${id}.md`);
      if (await this.backend.exists(trashMetaPath)) await this.backend.remove(trashMetaPath);
      if (sidecar.createdAt) {
        await writeSidecar(this.backend, `.meta/${id}.json`, { createdAt: sidecar.createdAt });
      }
    });
  }

  async permanentlyDelete(id: string, options: DeleteOptions = {}): Promise<void> {
    const deleteOrphanedImages = options.deleteOrphanedImages ?? true;
    await this.runExclusive(id, async () => {
      const trashMdPath = `.trash/${id}.md`;
      const trashMetaPath = `.trash/.meta/${id}.json`;

      let body = '';
      if (await this.backend.exists(trashMdPath)) body = await this.backend.readText(trashMdPath);

      await this.backend.remove(trashMdPath);
      await this.backend.remove(trashMetaPath);

      if (deleteOrphanedImages) {
        const refs = findImageReferences(body);
        if (refs.length > 0) await this.removeOrphanedImages(refs);
      }
    });
  }

  async emptyTrash(options: DeleteOptions = {}): Promise<{ deletedCount: number }> {
    const deleteOrphanedImages = options.deleteOrphanedImages ?? true;
    const ids = await this.listTrashIds();

    const candidateRefs = new Set<string>();
    if (deleteOrphanedImages) {
      for (const id of ids) {
        const body = await this.backend.readText(`.trash/${id}.md`);
        for (const ref of findImageReferences(body)) candidateRefs.add(ref);
      }
    }

    for (const id of ids) {
      await this.runExclusive(id, async () => {
        await this.backend.remove(`.trash/${id}.md`);
        await this.backend.remove(`.trash/.meta/${id}.json`);
      });
    }

    if (deleteOrphanedImages && candidateRefs.size > 0) {
      await this.removeOrphanedImages([...candidateRefs]);
    }

    return { deletedCount: ids.length };
  }

  async purgeExpiredTrash(options: DeleteOptions & { now?: Date } = {}): Promise<{ purgedIds: string[] }> {
    const now = options.now ?? new Date();
    const ids = await this.listTrashIds();
    const purged: string[] = [];

    for (const id of ids) {
      const sidecar = await readSidecar(this.backend, `.trash/.meta/${id}.json`);
      if (!sidecar.deletedAt) continue;
      const deletedAtMs = Date.parse(sidecar.deletedAt);
      if (Number.isNaN(deletedAtMs)) continue;
      if (now.getTime() - deletedAtMs >= THIRTY_DAYS_MS) {
        await this.permanentlyDelete(id, { deleteOrphanedImages: options.deleteOrphanedImages });
        purged.push(id);
      }
    }

    return { purgedIds: purged };
  }

  private async removeOrphanedImages(candidates: string[]): Promise<void> {
    const stillReferenced = await this.collectAllImageReferences();
    for (const ref of candidates) {
      if (!stillReferenced.has(ref)) await this.backend.remove(ref);
    }
  }

  /**
   * A full pass over media/, independent of any single QuKi's
   * deletion/trash lifecycle: removes every file under media/ that no
   * active or trashed QuKi's body currently references.
   *
   * This exists because the candidate-based cleanup above only ever
   * considers images that *were* referenced by a QuKi that is now being
   * deleted - an image pasted into a QuKi that is never saved (rule 16: an
   * empty body is never written) never becomes a candidate there, since no
   * .md file ever referenced it in the first place. Callers are expected to
   * run this at points other than deletion - e.g. app startup - so those
   * images still get cleaned up eventually.
   */
  async sweepOrphanedImages(): Promise<{ removedCount: number }> {
    const files = await this.backend.listDir('media');
    if (files.length === 0) return { removedCount: 0 };
    const referenced = await this.collectAllImageReferences();
    let removedCount = 0;
    for (const name of files) {
      const ref = `media/${name}`;
      if (!referenced.has(ref)) {
        await this.backend.remove(ref);
        removedCount++;
      }
    }
    return { removedCount };
  }

  private async collectAllImageReferences(): Promise<Set<string>> {
    const refs = new Set<string>();
    for (const id of await this.listActiveIds()) {
      const body = await this.backend.readText(`${id}.md`);
      for (const ref of findImageReferences(body)) refs.add(ref);
    }
    for (const id of await this.listTrashIds()) {
      const body = await this.backend.readText(`.trash/${id}.md`);
      for (const ref of findImageReferences(body)) refs.add(ref);
    }
    return refs;
  }

  async search(query: string, options: { includeTrash?: boolean } = {}): Promise<QuKiSummary[]> {
    const trimmed = query.trim();
    const active = await this.list();

    if (!options.includeTrash) {
      if (trimmed === '') return active;
      return this.matchBodies(active, trimmed, (s) => `${s.id}.md`);
    }

    const trash = await this.listTrash();
    if (trimmed === '') return [...active, ...trash];

    const activeMatches = await this.matchBodies(active, trimmed, (s) => `${s.id}.md`);
    const trashMatches = await this.matchBodies(trash, trimmed, (s) => `.trash/${s.id}.md`);
    return [...activeMatches, ...trashMatches];
  }

  private async matchBodies<T extends QuKiSummary>(items: T[], query: string, pathFor: (item: T) => string): Promise<T[]> {
    const lower = query.toLowerCase();
    const matches: T[] = [];
    for (const item of items) {
      const body = await this.backend.readText(pathFor(item));
      if (body.toLowerCase().includes(lower)) matches.push(item);
    }
    return matches;
  }

  async writeImage(bytes: Uint8Array, extension: string): Promise<WriteImageResult> {
    return writeImageFile(this.backend, bytes, extension);
  }

  async exportLibrary(): Promise<ExportResult> {
    return buildExport(this.backend);
  }
}
