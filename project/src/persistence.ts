import type { QuKiStore } from "quki-core";

export interface InitialQuKi {
  id: string | null;
  body: string;
  modifiedAt: string | null;
}

/**
 * Fires when a storage operation throws (as opposed to a store.save()
 * conflict, which is a normal result value, not an exception) -
 * STORAGE_CONTRACT.md rule 18 requires this to be surfaced, not just
 * logged, so callers use this to show it, not merely to log it. The raw
 * error is always console.error'd alongside the callback so the failure is
 * debuggable even when a caller's on-screen message stays short.
 */
export type StorageErrorHandler = (error: unknown) => void;

/**
 * There is no QuKi list screen yet (that's a later step), so there is no
 * real "which QuKi is open" selection. This is a temporary stand-in: load
 * whichever active QuKi was modified most recently, or start blank if none
 * exist. QuKiStore.list() already sorts most-recently-modified first.
 *
 * If store.list()/store.read() throws, onLoadError is invoked with the raw
 * error and this falls back to a blank QuKi rather than leaving the caller
 * with an unhandled rejection and a silently blank, uninitialized editor.
 */
export async function loadInitialQuKi(
  store: QuKiStore,
  onLoadError?: StorageErrorHandler,
): Promise<InitialQuKi> {
  try {
    const list = await store.list();
    if (list.length === 0) {
      return { id: null, body: "", modifiedAt: null };
    }
    const mostRecent = list[0]!;
    const detail = await store.read(mostRecent.id);
    return { id: detail.id, body: detail.body, modifiedAt: detail.modifiedAt };
  } catch (error) {
    console.error("QuKi initial load failed unexpectedly:", error);
    onLoadError?.(error);
    return { id: null, body: "", modifiedAt: null };
  }
}

export interface SaveConflictInfo {
  reason: "modified" | "deleted";
  currentBody: string | null;
}

export type ConflictHandler = (info: SaveConflictInfo) => void;

export interface SavedInfo {
  id: string;
  modifiedAt: string;
}

export type SavedHandler = (info: SavedInfo) => void;

export interface AutoSaveOptions {
  debounceMs?: number;
  intervalMs?: number;
  onSaveError?: StorageErrorHandler;
  /**
   * PROPOSAL: fired after a save actually writes ("saved", not
   * "skipped-empty" or "conflict"). Added for chunk-2 UI wiring - the
   * editor's Delete button is disabled until the current QuKi has been
   * saved at least once (BEHAVIOR_SPEC.md §4), and the id transitions from
   * null to real only inside this controller, so the controller is the
   * only place that knows when to flip it.
   */
  onSaved?: SavedHandler;
}

const DEFAULT_DEBOUNCE_MS = 2000;
const DEFAULT_INTERVAL_MS = 30000;

/**
 * Drives BEHAVIOR_SPEC.md section 4 auto-save: 2s debounce after the last
 * change, an unconditional 30s tick, and flush() for lifecycle signals
 * (visibility hidden / pagehide) - the web equivalents of "inactive,
 * paused, or detached". A save is skipped when the body hasn't changed
 * since the last write; QuKiStore.save() itself skips empty bodies.
 *
 * On a conflict, per STORAGE_CONTRACT.md rule 18 ("a failed save is
 * surfaced, not just logged"), onConflict is invoked and the local
 * id/modifiedAt/lastSavedBody baseline is left untouched - the same body
 * change will be retried on the next debounce or tick.
 *
 * If store.save() throws instead of returning a result - quota exceeded,
 * a permissions problem, crypto.randomUUID() unavailable in an insecure
 * context, anything - that is the same "failed save" under rule 18, not a
 * different case: options.onSaveError is invoked with the raw error and
 * the baseline is likewise left untouched, so the same edit is retried
 * next time rather than silently dropped.
 */
export class AutoSaveController {
  private id: string | null;
  private modifiedAt: string | null;
  private lastSavedBody: string;
  private readonly debounceMs: number;
  private readonly intervalMs: number;
  private readonly onSaveError: StorageErrorHandler;
  private readonly onSaved: SavedHandler;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private intervalTimer: ReturnType<typeof setInterval> | null = null;
  private saveInFlight: Promise<void> | null = null;
  private resaveRequested = false;

  constructor(
    private readonly store: QuKiStore,
    private readonly getBody: () => string,
    private readonly onConflict: ConflictHandler,
    initial: InitialQuKi,
    options: AutoSaveOptions = {},
  ) {
    this.id = initial.id;
    this.modifiedAt = initial.modifiedAt;
    this.lastSavedBody = initial.body;
    this.debounceMs = options.debounceMs ?? DEFAULT_DEBOUNCE_MS;
    this.intervalMs = options.intervalMs ?? DEFAULT_INTERVAL_MS;
    this.onSaveError = options.onSaveError ?? (() => {});
    this.onSaved = options.onSaved ?? (() => {});
  }

  get currentId(): string | null {
    return this.id;
  }

  /**
   * PROPOSAL: replaces the id/modifiedAt/lastSavedBody baseline in place,
   * without touching timers other than cancelling a pending debounce.
   * Added for chunk-2 "New QuKi" and "switch to a different QuKi from the
   * list" flows: both load different content into the editor and must
   * re-baseline the controller against it so the next notifyChange() diffs
   * against the *new* QuKi's last-saved body, not the old one's - and so a
   * debounce timer queued against the old body can't fire after the switch
   * and silently resave stale content under the new baseline.
   */
  resetBaseline(initial: InitialQuKi): void {
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    this.id = initial.id;
    this.modifiedAt = initial.modifiedAt;
    this.lastSavedBody = initial.body;
  }

  start(): void {
    this.intervalTimer = setInterval(() => {
      void this.save();
    }, this.intervalMs);
  }

  dispose(): void {
    if (this.debounceTimer !== null) clearTimeout(this.debounceTimer);
    if (this.intervalTimer !== null) clearInterval(this.intervalTimer);
    this.debounceTimer = null;
    this.intervalTimer = null;
  }

  notifyChange(): void {
    if (this.debounceTimer !== null) clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      void this.save();
    }, this.debounceMs);
  }

  /** Forces an immediate save, bypassing the debounce timer. Used on lifecycle signals. */
  async flush(): Promise<void> {
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    await this.save();
  }

  private async save(): Promise<void> {
    if (this.saveInFlight) {
      this.resaveRequested = true;
      return this.saveInFlight;
    }
    this.saveInFlight = this.runSave().finally(() => {
      this.saveInFlight = null;
      if (this.resaveRequested) {
        this.resaveRequested = false;
        void this.save();
      }
    });
    return this.saveInFlight;
  }

  private async runSave(): Promise<void> {
    const body = this.getBody();
    if (body === this.lastSavedBody) return;

    let result;
    try {
      result = await this.store.save({
        id: this.id,
        body,
        expectedModifiedAt: this.id === null ? undefined : (this.modifiedAt ?? undefined),
      });
    } catch (error) {
      console.error("QuKi auto-save failed unexpectedly:", error);
      this.onSaveError(error);
      return;
    }

    if (result.status === "saved") {
      this.id = result.id;
      this.modifiedAt = result.modifiedAt;
      this.lastSavedBody = body;
      this.onSaved({ id: result.id, modifiedAt: result.modifiedAt });
    } else if (result.status === "skipped-empty") {
      // Deliberate no-op (STORAGE_CONTRACT.md rule 16): leave the baseline
      // as-is so a later non-empty edit is still recognised as a change.
    } else {
      this.onConflict({ reason: result.reason, currentBody: result.currentBody });
    }
  }
}
