export type ViewName = "editor" | "list" | "settings" | "trash";

type Side = "left" | "right" | "none";

/**
 * BEHAVIOR_SPEC.md §2: list slides in from the left (it sits on the left
 * control), Settings from the right - matching the side each opening
 * control sits on in the editor's app bar. Trash is a sub-screen of
 * Settings and slides the same direction.
 */
const ENTRY_SIDE: Record<ViewName, Side> = {
  editor: "none",
  list: "left",
  settings: "right",
  trash: "right",
};

/**
 * A minimal push/pop stack over a fixed set of pre-built view elements,
 * standing in for a router. The editor is always at the bottom of the
 * stack and is never itself pushed - "the editor is the permanent root...
 * no second editor is ever pushed" (BEHAVIOR_SPEC.md §2). The QuKi list
 * "sets [the open QuKi id] and pops back", which is the spec's own word
 * for this navigation shape.
 *
 * Per BEHAVIOR_SPEC.md §2, "Settings opened from the QuKi list uses a
 * plain push instead" (no directional slide) - callers pass
 * `plain: true` for that one transition.
 *
 * The animation here is intentionally minimal (a single slide-in on the
 * entering view, no coordinated two-panel exit) - the task's own guidance
 * is that the structural push/pop behavior matters far more than transition
 * polish.
 */
export class Navigator {
  private stack: ViewName[] = ["editor"];

  constructor(private readonly views: Record<ViewName, HTMLElement>) {
    for (const [name, el] of Object.entries(this.views) as [ViewName, HTMLElement][]) {
      el.hidden = name !== "editor";
    }
  }

  get current(): ViewName {
    return this.stack[this.stack.length - 1]!;
  }

  push(target: ViewName, options: { plain?: boolean } = {}): void {
    if (target === "editor" || target === this.current) return;
    const from = this.current;
    this.stack.push(target);
    this.animateIn(target, options.plain ? "none" : ENTRY_SIDE[target]);
    this.views[from].hidden = true;
  }

  pop(): void {
    if (this.stack.length <= 1) return;
    const from = this.stack.pop()!;
    this.reveal(this.current);
    this.views[from].hidden = true;
  }

  /** Returns straight to the editor regardless of how deep the stack is. */
  popToRoot(): void {
    if (this.stack.length === 1) return;
    this.stack = ["editor"];
    for (const [name, el] of Object.entries(this.views) as [ViewName, HTMLElement][]) {
      el.hidden = name !== "editor";
    }
    this.reveal("editor");
  }

  private reveal(target: ViewName): void {
    const el = this.views[target];
    el.hidden = false;
    el.style.transition = "none";
    el.style.transform = "translateX(0)";
  }

  private animateIn(target: ViewName, side: Side): void {
    const el = this.views[target];
    el.hidden = false;
    if (side === "none") {
      el.style.transition = "none";
      el.style.transform = "translateX(0)";
      return;
    }
    el.style.transition = "none";
    el.style.transform = side === "left" ? "translateX(-100%)" : "translateX(100%)";
    // Force a reflow so the next transform change is transitioned rather
    // than coalesced with the one above into a single, invisible jump.
    void el.offsetWidth;
    el.style.transition = "transform 200ms ease";
    el.style.transform = "translateX(0)";
  }
}
