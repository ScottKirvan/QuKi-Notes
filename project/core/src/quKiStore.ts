import { exportLibrary as buildExport } from './export.js';
import { findImageReferences, writeImage as writeImageFile } from './media.js';
import { readSidecar, writeSidecar, type SidecarData } from './sidecar.js';
import type { FileStat, StorageBackend } from './storageBackend.js';
import {
  InvalidIdError,
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

function describeError(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

/**
 * Every public QuKiStore method that takes a plain id turns it directly into
 * a relative path (`${id}.md`, `.meta/${id}.json`, ...). Rejecting `/`, `\`
 * and a leading `.` here is what keeps STORAGE_CONTRACT.md rule 9 (the
 * folder is flat) true against a caller-supplied id - the CLI and MCP both
 * pass user/model-supplied ids straight through with no validation of their
 * own.
 */
function assertValidId(id: string): void {
  if (id === '' || id.includes('/') || id.includes('\\') || id.startsWith('.')) {
    throw new InvalidIdError(`Invalid QuKi id: ${JSON.stringify(id)}`);
  }
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
    const settled = await Promise.allSettled(ids.map((id) => this.buildActiveSummary(id)));
    const summaries = this.collectSettled(ids, settled, 'list');
    summaries.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt));
    return summaries;
  }

  /**
   * A single bad entry (a directory literally named `x.md`, a broken
   * symlink, a permissions error) must never take down the whole list -
   * STORAGE_CONTRACT.md's "folder is the index" model means one unreadable
   * neighbour is not grounds to hide every other QuKi. Skips are reported to
   * stderr rather than swallowed silently.
   */
  private collectSettled<T>(ids: string[], settled: PromiseSettledResult<T>[], context: string): T[] {
    const out: T[] = [];
    settled.forEach((result, i) => {
      if (result.status === 'fulfilled') {
        out.push(result.value);
      } else {
        console.error(`QuKiStore.${context}: skipping "${ids[i]}" - ${describeError(result.reason)}`);
      }
    });
    return out;
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
    const settled = await Promise.allSettled(ids.map((id) => this.buildTrashSummary(id)));
    const summaries = this.collectSettled(ids, settled, 'listTrash');
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
    assertValidId(id);
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
    assertValidId(id);
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
    assertValidId(id);
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
    try {
      await writeSidecar(this.backend, `.meta/${id}.json`, { createdAt });
    } catch (err) {
      // The .md file above already landed - a failed sidecar write must not
      // leave it behind as an orphan with a fresh random id, since id is a
      // new crypto.randomUUID() every call and a naive caller retry would
      // otherwise create a second, duplicate QuKi rather than completing
      // this one.
      await this.backend.remove(mdPath);
      throw err;
    }
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
    assertValidId(id);
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
    assertValidId(id);
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
    assertValidId(id);
    const deleteOrphanedImages = options.deleteOrphanedImages ?? true;
    await this.runExclusive(id, async () => {
      const trashMdPath = `.trash/${id}.md`;
      const trashMetaPath = `.trash/.meta/${id}.json`;

      if (!(await this.backend.exists(trashMdPath))) throw new NotFoundError(`Trashed QuKi not found: ${id}`);
      const body = await this.backend.readText(trashMdPath);

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
        try {
          const body = await this.backend.readText(`.trash/${id}.md`);
          for (const ref of findImageReferences(body)) candidateRefs.add(ref);
        } catch (err) {
          console.error(`QuKiStore.emptyTrash: skipping ".trash/${id}" while collecting image refs - ${describeError(err)}`);
        }
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
      const metaPath = `.trash/.meta/${id}.json`;
      const sidecar = await readSidecar(this.backend, metaPath);
      let deletedAt = sidecar.deletedAt;
      if (!deletedAt) {
        // STORAGE_CONTRACT.md's migration section: trash predating this
        // rewrite has no deletedAt sidecar field at all. Rather than skip it
        // forever, stamp it "now" the first time the purge sweep sees it, so
        // the 30-day clock starts here instead of never starting - matching
        // "stamped at first launch of the new version" without needing a
        // separate one-time migration flag (already-stamped items simply
        // never hit this branch again).
        deletedAt = now.toISOString();
        await writeSidecar(this.backend, metaPath, { ...sidecar, deletedAt });
      }
      const deletedAtMs = Date.parse(deletedAt);
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

  private async collectAllImageReferences(): Promise<Set<string>> {
    const refs = new Set<string>();
    for (const id of await this.listActiveIds()) {
      try {
        const body = await this.backend.readText(`${id}.md`);
        for (const ref of findImageReferences(body)) refs.add(ref);
      } catch (err) {
        console.error(`QuKiStore.collectAllImageReferences: skipping "${id}.md" - ${describeError(err)}`);
      }
    }
    for (const id of await this.listTrashIds()) {
      try {
        const body = await this.backend.readText(`.trash/${id}.md`);
        for (const ref of findImageReferences(body)) refs.add(ref);
      } catch (err) {
        console.error(`QuKiStore.collectAllImageReferences: skipping ".trash/${id}.md" - ${describeError(err)}`);
      }
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
      let body: string;
      try {
        body = await this.backend.readText(pathFor(item));
      } catch (err) {
        console.error(`QuKiStore.search: skipping "${pathFor(item)}" - ${describeError(err)}`);
        continue;
      }
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
