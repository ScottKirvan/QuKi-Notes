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
 * BEHAVIOR_SPEC.md §4: "A blank canvas on launch." Every app start, and
 * Settings -> Change location, opens a fresh, empty, unsaved QuKi - there
 * is no "reopen whatever was last edited" behavior. (An earlier version of
 * this function loaded whichever QuKi was most recently modified; that was
 * never a real design decision - just a stand-in written before the QuKi
 * list existed and never revisited - and has been removed.) Since nothing
 * here touches storage, there is no failure mode to report through a
 * StorageErrorHandler.
 */
export function blankInitialQuKi(): InitialQuKi {
  return { id: null, body: "", modifiedAt: null };
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

/**
 * What a save attempt (flush(), or the debounce/interval timers internally)
 * actually did - returned by flush() so a caller can tell a real write apart
 * from one that never landed, instead of the old `Promise<void>` that looked
 * identical whether the save succeeded, conflicted, or threw. See rule 18's
 * "a failed save is surfaced, not just logged": a caller that's about to
 * replace the editor's content or reset the baseline must be able to check
 * this before doing so, not find out only via a side-channel banner.
 *
 * "stale" means this particular save's own result was discarded because
 * resetBaseline() moved the controller on to a different QuKi before the
 * write finished - nothing was lost (the save either wrote harmlessly to the
 * QuKi it started against, or is indistinguishable from that to the
 * caller), so callers should treat it exactly like "saved" for the purpose
 * of deciding whether it's safe to proceed.
 */
export type SaveOutcome =
  | { status: "saved"; id: string; modifiedAt: string }
  | { status: "skipped-empty" }
  | { status: "skipped-unchanged" }
  | { status: "conflict"; reason: "modified" | "deleted"; currentBody: string | null }
  | { status: "error"; error: unknown }
  | { status: "stale" };

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
  private saveInFlight: Promise<SaveOutcome> | null = null;
  private resaveRequested = false;
  /**
   * Bumped on every resetBaseline() call. A save's own generation is
   * captured at the moment it starts (in save()/overwrite()) and compared
   * again once its I/O resolves (in runSave()/runOverwrite()) - if the two
   * don't match, resetBaseline() moved the controller on to a different
   * QuKi while this save was in flight, and applying its result now would
   * silently re-point id/modifiedAt/lastSavedBody back at the abandoned
   * QuKi. See the fix for the auto-save generation race: a save started
   * against QuKi A must never retroactively re-point the controller at A
   * after resetBaseline() has already moved it to B.
   */
  private generation = 0;

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
    this.generation++;
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

  /**
   * Forces an immediate save, bypassing the debounce timer. Used on
   * lifecycle signals, and by callers about to switch/discard the current
   * QuKi (see SaveOutcome) - it waits out the *entire* save chain, including
   * a resave queued behind an already-in-flight save, not just whichever
   * save happened to be in flight when flush() was called. Returning early
   * from the first save while a queued resave was still running underneath
   * it was the root cause of the generation race this fixes: a caller could
   * resetBaseline() onto a new QuKi while that resave was still targeting
   * the old one.
   */
  async flush(): Promise<SaveOutcome> {
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    return this.save();
  }

  /**
   * User-initiated escape hatch from the conflict banner (STORAGE_CONTRACT.md
   * rule 17's explicit-overwrite carve-out - see the note on that rule).
   * This is the ONLY path that ever sets SaveParams.force; the debounce and
   * interval paths above never do, so an automatic save still refuses to
   * overwrite exactly as before. Only reachable for an existing id (a
   * conflict can only happen after at least one successful save), so a null
   * id is a no-op rather than an error.
   *
   * Waits out any save already in flight before writing, so a normal save
   * and a forced overwrite can never race each other - reusing the same
   * saveInFlight/resaveRequested single-flight machinery runSave() uses, so
   * a save that arrives *during* the overwrite queues behind it instead of
   * interleaving. getBody() is read fresh only once the overwrite actually
   * starts, so it captures whatever the user has typed up to that moment,
   * not whatever was live when the conflict first fired.
   */
  async overwrite(): Promise<void> {
    if (this.id === null) return;

    while (this.saveInFlight) {
      await this.saveInFlight.catch(() => {});
    }

    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }

    const generation = this.generation;
    this.saveInFlight = this.runOverwrite(generation).finally(() => {
      this.saveInFlight = null;
      if (this.resaveRequested) {
        this.resaveRequested = false;
        void this.save();
      }
    });
    await this.saveInFlight;
  }

  private async runOverwrite(generation: number): Promise<SaveOutcome> {
    const body = this.getBody();

    let result;
    try {
      result = await this.store.save({
        id: this.id,
        body,
        expectedModifiedAt: this.modifiedAt ?? undefined,
        force: true,
      });
    } catch (error) {
      console.error("QuKi overwrite save failed unexpectedly:", error);
      if (generation === this.generation) this.onSaveError(error);
      return { status: "error", error };
    }

    if (generation !== this.generation) {
      // resetBaseline() moved the controller on to a different QuKi while
      // this overwrite was in flight - see the `generation` field comment.
      return { status: "stale" };
    }

    if (result.status === "saved") {
      this.id = result.id;
      this.modifiedAt = result.modifiedAt;
      this.lastSavedBody = body;
      this.onSaved({ id: result.id, modifiedAt: result.modifiedAt });
      return { status: "saved", id: result.id, modifiedAt: result.modifiedAt };
    }
    // "skipped-empty": rule 16 still applies under force - leave the
    // baseline untouched, same as a normal save's skipped-empty branch.
    // "conflict" is unreachable here since force skips both conflict
    // branches in QuKiStore.updateExisting.
    return { status: "skipped-empty" };
  }

  /**
   * Single-flight save, chained through resaveRequested: a caller that
   * arrives while a save is already running never starts a second,
   * overlapping I/O call - it just flags resaveRequested and shares the
   * in-flight promise. The critical piece (previously missing) is that the
   * *queued* resave, once it actually runs, is chained back into that same
   * shared promise by returning it from the `.then()` below rather than
   * firing it with `void` - so a caller awaiting this call (flush(), most
   * importantly) genuinely waits for the whole chain, not just whichever
   * save happened to be first.
   */
  private save(): Promise<SaveOutcome> {
    if (this.saveInFlight) {
      this.resaveRequested = true;
      return this.saveInFlight;
    }
    const generation = this.generation;
    this.saveInFlight = this.runSave(generation).then((outcome) => {
      this.saveInFlight = null;
      if (this.resaveRequested) {
        this.resaveRequested = false;
        return this.save();
      }
      return outcome;
    });
    return this.saveInFlight;
  }

  private async runSave(generation: number): Promise<SaveOutcome> {
    const body = this.getBody();
    if (body === this.lastSavedBody) return { status: "skipped-unchanged" };

    let result;
    try {
      result = await this.store.save({
        id: this.id,
        body,
        expectedModifiedAt: this.id === null ? undefined : (this.modifiedAt ?? undefined),
      });
    } catch (error) {
      console.error("QuKi auto-save failed unexpectedly:", error);
      if (generation === this.generation) this.onSaveError(error);
      return { status: "error", error };
    }

    if (generation !== this.generation) {
      // resetBaseline() moved the controller on to a different QuKi while
      // this save was in flight - see the `generation` field comment. Do
      // not apply this result: it would silently re-point id/modifiedAt/
      // lastSavedBody back at the QuKi this controller just left.
      return { status: "stale" };
    }

    if (result.status === "saved") {
      this.id = result.id;
      this.modifiedAt = result.modifiedAt;
      this.lastSavedBody = body;
      this.onSaved({ id: result.id, modifiedAt: result.modifiedAt });
      return { status: "saved", id: result.id, modifiedAt: result.modifiedAt };
    } else if (result.status === "skipped-empty") {
      // Deliberate no-op (STORAGE_CONTRACT.md rule 16): leave the baseline
      // as-is so a later non-empty edit is still recognised as a change.
      return { status: "skipped-empty" };
    } else {
      this.onConflict({ reason: result.reason, currentBody: result.currentBody });
      return { status: "conflict", reason: result.reason, currentBody: result.currentBody };
    }
  }
}
