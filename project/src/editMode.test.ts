import { describe, expect, it } from "vitest";

import {
  resolveModeIconState,
  shouldFocusOnOpen,
  toolbarScrollCorrectionTiming,
  usesKeyboardSignal,
} from "./editMode.js";

describe("usesKeyboardSignal", () => {
  it("is true only for a native Android platform", () => {
    expect(usesKeyboardSignal("android", true)).toBe(true);
  });

  it("is false for Android when not running as a native app (e.g. mobile web)", () => {
    expect(usesKeyboardSignal("android", false)).toBe(false);
  });

  it("is false for every other platform, native or not", () => {
    expect(usesKeyboardSignal("ios", true)).toBe(false);
    expect(usesKeyboardSignal("electron", true)).toBe(false);
    expect(usesKeyboardSignal("web", false)).toBe(false);
  });
});

describe("shouldFocusOnOpen", () => {
  it("is true for a blank QuKi (null id)", () => {
    expect(shouldFocusOnOpen(null)).toBe(true);
  });

  it("is false for an existing QuKi (real id)", () => {
    expect(shouldFocusOnOpen("some-id")).toBe(false);
  });
});

describe("toolbarScrollCorrectionTiming", () => {
  it("is immediate on the keyboard signal (Android) - the selection has already settled by then", () => {
    expect(toolbarScrollCorrectionTiming(true)).toBe("immediate");
  });

  it("is deferred on the focus/blur signal (everywhere else) - it must wait for the tap's own selection-set transaction", () => {
    expect(toolbarScrollCorrectionTiming(false)).toBe("deferred");
  });
});

describe("resolveModeIconState", () => {
  it("is plain-text whenever plain-text mode is on, regardless of edit mode", () => {
    expect(resolveModeIconState(true, true)).toBe("plain-text");
    expect(resolveModeIconState(true, false)).toBe("plain-text");
  });

  it("is edit when rendered and in edit mode", () => {
    expect(resolveModeIconState(false, true)).toBe("edit");
  });

  it("is reading when rendered and not in edit mode", () => {
    expect(resolveModeIconState(false, false)).toBe("reading");
  });
});
