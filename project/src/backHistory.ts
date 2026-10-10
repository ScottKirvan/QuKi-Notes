interface QuKiStop<S> {
  kind: "quki";
  id: string | null;
  scroll: S | undefined;
}

interface ListStop {
  kind: "list";
}

type Stop<S> = QuKiStop<S> | ListStop;

export type BackPlan<S> =
  | { target: "exit" }
  | { target: "list"; index: number; version: number }
  | { target: "blank"; index: number; version: number }
  | { target: "quki"; id: string; scroll: S | undefined; index: number; version: number };

/**
 * The session's walk through QuKis and the QuKi list, for Android's system
 * Back (BEHAVIOR_SPEC.md §2a). Memory only, never persisted, and never a
 * record of which QuKis exist: planBack asks the caller at that moment.
 * Settings and Trash are not stops, so nothing here mentions them.
 *
 * The top stop is where the user is now. `editorStop` is the QuKi the
 * editor holds, which stays the same while the list is on screen above it.
 * `S` is the caller's scroll snapshot; this module only carries it.
 */
export class BackHistory<S> {
  private stops: Stop<S>[] = [];
  private editorStop!: QuKiStop<S>;
  private version = 0;

  constructor() {
    this.reset();
  }

  /** A fresh session: just the blank QuKi the editor starts with. */
  reset(): void {
    this.editorStop = { kind: "quki", id: null, scroll: undefined };
    this.stops = [this.editorStop];
    this.version++;
  }

  /**
   * The editor now holds this QuKi (opened, started new, shared in); `null`
   * for a blank one with no file yet. A blank one started while the user is
   * already looking at a blank one changes nothing on screen, so it adds no stop.
   */
  visitQuKi(id: string | null): void {
    if (id === null && this.top() === this.editorStop && this.editorStop.id === null) return;
    this.editorStop = { kind: "quki", id, scroll: undefined };
    this.stops.push(this.editorStop);
    this.version++;
  }

  /** The editor's QuKi changed while the list stays on screen (the open QuKi deleted from the list): not a stop until the user returns to it. */
  holdInEditor(id: string | null): void {
    this.editorStop = { kind: "quki", id, scroll: undefined };
    this.version++;
  }

  visitList(): void {
    if (this.top().kind !== "list") this.stops.push({ kind: "list" });
    this.version++;
  }

  /** The list's own back arrow: the user is back in the QuKi the editor still holds. */
  returnToEditor(): void {
    if (this.top().kind === "list") this.stops.pop();
    if (this.top() !== this.editorStop) this.stops.push(this.editorStop);
    this.version++;
  }

  /** A blank QuKi's first save gave it an id. */
  assignId(id: string): void {
    if (this.editorStop.id === null) this.editorStop.id = id;
  }

  /** Called as the user leaves the editor's QuKi, so Back can return them to the same spot. */
  rememberScroll(scroll: S): void {
    this.editorStop.scroll = scroll;
  }

  /**
   * Where Back goes from here, without moving anything yet - the caller may
   * still refuse (a save that won't flush). A blank QuKi is a stop, returned
   * to as a fresh blank one. Skipped: a QuKi `exists` says is gone, and a
   * stop that looks the same as the one being left (the same QuKi, or a
   * blank one when leaving a blank one).
   */
  async planBack(exists: (id: string) => Promise<boolean>): Promise<BackPlan<S>> {
    const version = this.version;
    const leaving = this.top();
    for (let index = this.stops.length - 2; index >= 0; index--) {
      const stop = this.stops[index]!;
      if (stop.kind === "list") {
        if (leaving.kind === "list") continue;
        return { target: "list", index, version };
      }
      if (leaving.kind === "quki" && leaving.id === stop.id) continue;
      if (stop.id === null) return { target: "blank", index, version };
      if (!(await exists(stop.id))) continue;
      return { target: "quki", id: stop.id, scroll: stop.scroll, index, version };
    }
    return { target: "exit" };
  }

  /** Moves to the planned stop. Returns false, changing nothing, if the history changed since the plan was made. */
  commit(plan: BackPlan<S>): boolean {
    if (plan.target === "exit" || plan.version !== this.version) return false;
    this.stops.length = plan.index + 1;
    const stop = this.stops[plan.index]!;
    if (stop.kind === "quki") this.editorStop = stop;
    this.version++;
    return true;
  }

  private top(): Stop<S> {
    return this.stops[this.stops.length - 1]!;
  }
}
