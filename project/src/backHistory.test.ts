import { describe, expect, it } from "vitest";

import { BackHistory, type BackPlan } from "./backHistory.js";

type Exists = (id: string) => Promise<boolean>;
const all: Exists = async () => true;
const existing =
  (...ids: string[]): Exists =>
  async (id) =>
    ids.includes(id);

async function back(history: BackHistory<number>, exists: Exists = all): Promise<BackPlan<number>> {
  const plan = await history.planBack(exists);
  history.commit(plan);
  return plan;
}

function where(plan: BackPlan<number>): string {
  return plan.target === "quki" ? `quki:${plan.id}` : plan.target;
}

describe("BackHistory", () => {
  it("exits from the blank QuKi the app starts with", async () => {
    expect(where(await back(new BackHistory()))).toBe("exit");
  });

  it("walks back QuKi B -> list -> QuKi A -> exit", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitList();
    history.visitQuKi("b");

    expect(where(await back(history))).toBe("list");
    expect(where(await back(history))).toBe("quki:a");
    expect(where(await back(history))).toBe("exit");
  });

  it("returns from a fresh blank QuKi to the QuKi the user was in before", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi(null);

    expect(where(await back(history))).toBe("quki:a");
  });

  it("follows a new QuKi's id once its first save assigns one", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi(null);
    history.assignId("new-id");
    history.visitList();

    expect(where(await back(history))).toBe("quki:new-id");
  });

  it("assigns the id to the launch QuKi too", async () => {
    const history = new BackHistory<number>();
    history.assignId("typed-at-launch");
    history.visitList();

    expect(where(await back(history))).toBe("quki:typed-at-launch");
  });

  it("never renames a QuKi that already has an id", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.assignId("other");
    history.visitList();

    expect(where(await back(history))).toBe("quki:a");
  });

  it("skips a blank QuKi the user never typed into", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi(null);
    history.visitList();

    expect(where(await back(history))).toBe("quki:a");
  });

  it("skips QuKis that no longer exist at the moment of going back", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("deleted");
    history.visitQuKi("b");

    expect(where(await back(history, existing("a", "b")))).toBe("quki:a");
  });

  it("asks about existence at the moment of going back, not when the QuKi was visited", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");
    const present = new Set(["a", "b"]);
    const exists = async (id: string): Promise<boolean> => present.has(id);

    present.delete("a");
    expect(where(await history.planBack(exists))).toBe("exit");
    present.add("a");
    expect(where(await history.planBack(exists))).toBe("quki:a");
  });

  it("exits when every earlier QuKi is gone", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");

    expect(where(await back(history, existing("b")))).toBe("exit");
  });

  it("does not stop on the same QuKi it is leaving", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");
    history.visitQuKi("gone");
    history.visitQuKi("b");

    expect(where(await back(history, existing("a", "b")))).toBe("quki:a");
  });

  it("does not stop on the list when leaving the list", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitList();
    history.visitQuKi("gone");
    history.visitList();

    expect(where(await back(history, existing("a")))).toBe("quki:a");
  });

  it("does not record the list twice in a row", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitList();
    history.visitList();

    expect(where(await back(history))).toBe("quki:a");
  });

  it("restores the scroll position the QuKi had when the user left it", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.rememberScroll(420);
    history.visitList();
    history.visitQuKi("b");
    history.rememberScroll(10);
    history.visitList();

    const toB = await back(history);
    expect(toB).toMatchObject({ target: "quki", id: "b", scroll: 10 });
    expect(where(await back(history))).toBe("list");
    expect(await back(history)).toMatchObject({ target: "quki", id: "a", scroll: 420 });
  });

  it("a QuKi visited fresh has no remembered scroll", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");

    expect(await back(history)).toMatchObject({ target: "quki", id: "a", scroll: undefined });
  });

  it("remembers scroll on the QuKi Back returned to", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");
    await back(history);
    history.rememberScroll(77);
    history.visitQuKi("c");

    expect(await back(history)).toMatchObject({ target: "quki", id: "a", scroll: 77 });
  });

  it("the list's own back arrow returns to the QuKi still in the editor", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitList();
    history.returnToEditor();

    expect(where(await back(history))).toBe("exit");
  });

  it("after Back lands on the list, its back arrow records the QuKi the editor still holds", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitList();
    history.visitQuKi("b");
    expect(where(await back(history))).toBe("list");

    history.returnToEditor();
    expect(where(await back(history))).toBe("quki:a");
  });

  it("deleting the open QuKi from the list leaves the list where it is, and its back arrow returns to the blank QuKi", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");
    history.visitList();
    history.holdInEditor(null);

    expect(where(await history.planBack(existing("a")))).toBe("quki:a");

    history.returnToEditor();
    history.assignId("typed-after-delete");
    history.visitList();
    expect(where(await back(history, existing("a", "typed-after-delete")))).toBe("quki:typed-after-delete");
  });

  it("does not move when the plan went stale before it was committed", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");
    const plan = await history.planBack(all);
    history.visitQuKi("c");

    expect(history.commit(plan)).toBe(false);
    expect(where(await back(history))).toBe("quki:b");
  });

  it("a plan that is not committed moves nothing", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");
    await history.planBack(all);

    expect(where(await back(history))).toBe("quki:a");
  });

  it("reset forgets everything but a blank QuKi", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitList();
    history.reset();

    expect(where(await back(history))).toBe("exit");
  });

  it("only asks about QuKis it might actually stop on", async () => {
    const history = new BackHistory<number>();
    history.visitQuKi("a");
    history.visitQuKi("b");
    history.visitQuKi("c");
    const asked: string[] = [];

    await history.planBack(async (id) => {
      asked.push(id);
      return true;
    });
    expect(asked).toEqual(["b"]);
  });
});
