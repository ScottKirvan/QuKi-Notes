import { describe, expect, it } from "vitest";

import {
  AWAY_CHOICES,
  AwayTracker,
  DEFAULT_AWAY_MINUTES,
  SEND_HIDE_WINDOW_MS,
  parseAwayMinutes,
  serializeAwayMinutes,
  shouldStartNewQuKi,
} from "./awayTimeout";

const MINUTE = 60_000;

describe("shouldStartNewQuKi", () => {
  const base = { hiddenAt: 0, minutes: 2, hiddenBySend: false, sharedIn: false };

  it("starts a new QuKi after two minutes hidden", () => {
    expect(shouldStartNewQuKi({ ...base, shownAt: 2 * MINUTE })).toBe(true);
    expect(shouldStartNewQuKi({ ...base, shownAt: 45 * MINUTE })).toBe(true);
  });

  it("does not before two minutes", () => {
    expect(shouldStartNewQuKi({ ...base, shownAt: 2 * MINUTE - 1 })).toBe(false);
  });

  it("follows the chosen time", () => {
    expect(shouldStartNewQuKi({ ...base, minutes: 15, shownAt: 10 * MINUTE })).toBe(false);
    expect(shouldStartNewQuKi({ ...base, minutes: 15, shownAt: 15 * MINUTE })).toBe(true);
  });

  it("never does when Off", () => {
    expect(shouldStartNewQuKi({ ...base, minutes: null, shownAt: 600 * MINUTE })).toBe(false);
  });

  it("does not when the app was hidden by Send's share sheet", () => {
    expect(shouldStartNewQuKi({ ...base, hiddenBySend: true, shownAt: 10 * MINUTE })).toBe(false);
  });

  it("does not when text was shared in while away", () => {
    expect(shouldStartNewQuKi({ ...base, sharedIn: true, shownAt: 10 * MINUTE })).toBe(false);
  });
});

describe("AwayTracker", () => {
  function tracker(): { t: AwayTracker; at: (ms: number) => void } {
    let now = 1_000_000;
    return {
      t: new AwayTracker(() => now),
      at: (ms) => {
        now = 1_000_000 + ms;
      },
    };
  }

  it("given the app is hidden for two minutes, when it comes back, then a new QuKi starts", () => {
    const { t, at } = tracker();
    t.hidden();
    at(2 * MINUTE);
    expect(t.shown(2)).toBe(true);
  });

  it("given the app stays visible, when time passes, then nothing starts", () => {
    const { t, at } = tracker();
    at(60 * MINUTE);
    expect(t.shown(2)).toBe(false);
  });

  it("given a short trip away, when it comes back, then nothing starts", () => {
    const { t, at } = tracker();
    t.hidden();
    at(MINUTE);
    expect(t.shown(2)).toBe(false);
  });

  it("counts from the first hidden signal and ignores a repeated one", () => {
    const { t, at } = tracker();
    t.hidden();
    at(90_000);
    t.hidden();
    at(2 * MINUTE);
    expect(t.shown(2)).toBe(true);
  });

  it("acts once per return; a repeated shown signal does nothing", () => {
    const { t, at } = tracker();
    t.hidden();
    at(3 * MINUTE);
    expect(t.shown(2)).toBe(true);
    expect(t.shown(2)).toBe(false);
  });

  it("given Send just opened the share sheet, when the app comes back much later, then nothing starts", () => {
    const { t, at } = tracker();
    t.noteSend();
    at(1_000);
    t.hidden();
    at(30 * MINUTE);
    expect(t.shown(2)).toBe(false);
  });

  it("given a Send long before leaving, when the app comes back, then a new QuKi starts as usual", () => {
    const { t, at } = tracker();
    t.noteSend();
    at(SEND_HIDE_WINDOW_MS + 1);
    t.hidden();
    at(SEND_HIDE_WINDOW_MS + 1 + 3 * MINUTE);
    expect(t.shown(2)).toBe(true);
  });

  it("forgets the share sheet once the app is back, so the next trip away counts", () => {
    const { t, at } = tracker();
    t.noteSend();
    t.hidden();
    at(5 * MINUTE);
    expect(t.shown(2)).toBe(false);
    t.hidden();
    at(10 * MINUTE);
    expect(t.shown(2)).toBe(true);
  });

  it("given text shared in while away, when the app comes back, then nothing more starts", () => {
    const { t, at } = tracker();
    t.hidden();
    at(5 * MINUTE);
    t.noteShareIn();
    expect(t.shown(2)).toBe(false);
  });

  it("given a trip away is forgotten (the app sent the user to a system screen), when it comes back, then nothing starts", () => {
    const { t, at } = tracker();
    t.hidden();
    at(5 * MINUTE);
    t.forget();
    expect(t.shown(2)).toBe(false);
  });

  it("a share-in while visible does not affect the next trip away", () => {
    const { t, at } = tracker();
    t.noteShareIn();
    t.hidden();
    at(5 * MINUTE);
    expect(t.shown(2)).toBe(true);
  });
});

describe("away setting values", () => {
  it("offers Off, 2, 5, 15 and 30 minutes, defaulting to 2", () => {
    expect(AWAY_CHOICES.map((c) => c.minutes)).toEqual([null, 2, 5, 15, 30]);
    expect(DEFAULT_AWAY_MINUTES).toBe(2);
  });

  it("round-trips every choice", () => {
    for (const { minutes } of AWAY_CHOICES) expect(parseAwayMinutes(serializeAwayMinutes(minutes))).toBe(minutes);
  });

  it("falls back to 2 minutes for nothing stored or an unknown value", () => {
    expect(parseAwayMinutes(null)).toBe(2);
    expect(parseAwayMinutes("7")).toBe(2);
    expect(parseAwayMinutes("")).toBe(2);
  });
});
