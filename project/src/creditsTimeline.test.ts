import { describe, expect, it } from "vitest";

import { CREDITS_END_AT, CREDITS_FADE_MS, CREDITS_ROLL_SPEED, creditsTimeline } from "./creditsTimeline";

describe("creditsTimeline", () => {
  it("starts the list just below the viewport and ends with its last line at the middle", () => {
    const t = creditsTimeline(1000, 340);
    expect(t.fromPx).toBe(340);
    expect(t.toPx).toBe(Math.round(340 * CREDITS_END_AT - 1000));
  });

  it("rolls at a constant speed, so a longer list takes proportionally longer", () => {
    const short = creditsTimeline(800, 340);
    const long = creditsTimeline(1600, 340);
    const rollMs = (t: ReturnType<typeof creditsTimeline>): number => t.totalMs * t.rollFraction;
    expect(rollMs(short)).toBeCloseTo(((340 - short.toPx) / CREDITS_ROLL_SPEED) * 1000, 0);
    expect(rollMs(long) - rollMs(short)).toBeCloseTo((800 / CREDITS_ROLL_SPEED) * 1000, 0);
  });

  it("adds the fade after the roll", () => {
    const t = creditsTimeline(1000, 340);
    expect(t.totalMs - t.totalMs * t.rollFraction).toBeCloseTo(CREDITS_FADE_MS, 5);
  });

  it("rolls for at least 5 seconds however short the list is", () => {
    const t = creditsTimeline(100, 100);
    expect(t.totalMs * t.rollFraction).toBeGreaterThanOrEqual(5000);
    expect(t.totalMs).toBe(5000 + CREDITS_FADE_MS);
  });

  it("treats negative sizes as zero", () => {
    expect(creditsTimeline(-5, -5)).toEqual(creditsTimeline(0, 0));
  });
});
