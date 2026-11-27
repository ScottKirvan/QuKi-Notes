import { describe, expect, it } from "vitest";

import {
  GREETINGS,
  TIPS,
  fadeDurationMs,
  nextWelcomeState,
  pickGreeting,
  pickRecent,
  pickTip,
  timeBucket,
} from "./welcomeContent";

describe("timeBucket", () => {
  it.each([
    [0, "night"],
    [4, "night"],
    [5, "morning"],
    [11, "morning"],
    [12, "afternoon"],
    [16, "afternoon"],
    [17, "evening"],
    [21, "evening"],
    [22, "night"],
    [23, "night"],
  ] as const)("hour %i is %s", (hour, bucket) => {
    expect(timeBucket(hour)).toBe(bucket);
  });
});

describe("picking", () => {
  it("picks a greeting from the hour's bucket", () => {
    expect(GREETINGS.morning).toContain(pickGreeting(8));
    expect(GREETINGS.night).toContain(pickGreeting(2));
  });

  it("uses the random value to choose, including its extremes", () => {
    expect(pickGreeting(8, () => 0)).toBe(GREETINGS.morning[0]);
    expect(pickGreeting(8, () => 0.9999)).toBe(GREETINGS.morning.at(-1));
    expect(pickGreeting(8, () => 1)).toBe(GREETINGS.morning.at(-1));
    expect(pickTip(() => 0)).toBe(TIPS[0]);
    expect(pickTip(() => 0.9999)).toBe(TIPS.at(-1));
  });

  it("has several greetings per bucket and short text", () => {
    for (const list of Object.values(GREETINGS)) {
      expect(list.length).toBeGreaterThanOrEqual(4);
      for (const text of list) expect(text.length).toBeLessThanOrEqual(60);
    }
    expect(TIPS.length).toBeGreaterThanOrEqual(12);
    for (const tip of TIPS) expect(tip.length).toBeLessThanOrEqual(90);
  });
});

describe("pickRecent", () => {
  const items = [
    { id: "a", modifiedAt: "2026-01-01T00:00:00Z" },
    { id: "c", modifiedAt: "2026-03-01T00:00:00Z" },
    { id: "b", modifiedAt: "2026-02-01T00:00:00Z" },
    { id: "d", modifiedAt: "2026-04-01T00:00:00Z" },
  ];

  it("returns the newest few, newest first", () => {
    expect(pickRecent(items).map((i) => i.id)).toEqual(["d", "c", "b"]);
    expect(pickRecent(items, 1).map((i) => i.id)).toEqual(["d"]);
  });

  it("returns nothing when there are no QuKis, and does not reorder its input", () => {
    expect(pickRecent([])).toEqual([]);
    expect(items[0]!.id).toBe("a");
  });
});

describe("nextWelcomeState", () => {
  const hidden = { visible: false };
  const shown = { visible: true };

  it("shows for a blank QuKi", () => {
    expect(nextWelcomeState(hidden, "blank-quki")).toEqual(shown);
  });

  it("goes on dismiss and stays gone until the next blank QuKi", () => {
    const gone = nextWelcomeState(shown, "dismiss");
    expect(gone).toEqual(hidden);
    expect(nextWelcomeState(gone, "dismiss")).toEqual(hidden);
    expect(nextWelcomeState(gone, "blank-quki")).toEqual(shown);
  });

  it("goes when a saved QuKi loads, and a load never shows it", () => {
    expect(nextWelcomeState(shown, "quki-loaded")).toEqual(hidden);
    expect(nextWelcomeState(hidden, "quki-loaded")).toEqual(hidden);
  });
});

describe("fadeDurationMs", () => {
  it("is instant under reduced motion", () => {
    expect(fadeDurationMs(true)).toBe(0);
    expect(fadeDurationMs(false)).toBeGreaterThan(0);
  });
});
