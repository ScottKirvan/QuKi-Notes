import { beforeEach, describe, expect, it, vi } from "vitest";
import type { EditorView } from "@codemirror/view";

const capacitorMock = vi.hoisted(() => ({
  platform: "web",
  isNative: false,
}));

const keyboardMock = vi.hoisted(() => ({
  listeners: new Map<string, () => void>(),
  addListener: vi.fn((eventName: string, callback: () => void) => {
    keyboardMock.listeners.set(eventName, callback);
    return Promise.resolve({ remove: () => Promise.resolve() });
  }),
}));

vi.mock("@capacitor/core", () => ({
  Capacitor: {
    getPlatform: () => capacitorMock.platform,
    isNativePlatform: () => capacitorMock.isNative,
  },
}));

vi.mock("@capacitor/keyboard", () => ({
  Keyboard: {
    addListener: keyboardMock.addListener,
  },
}));

const {
  createEditModeTracker,
  resolveModeIconState,
  shouldFocusOnOpen,
  toolbarScrollCorrectionTiming,
  usesKeyboardSignal,
} = await import("./editMode.js");

/**
 * A minimal stand-in for EditorView.contentDOM: just enough of the
 * EventTarget surface createEditModeTracker actually calls
 * (addEventListener/removeEventListener), plus a way for a test to fire an
 * event without a real DOM (this project's unit tests run under Node, not
 * jsdom).
 */
function createFakeContentDOM() {
  const handlers: Record<string, Array<() => void>> = {};
  return {
    addEventListener: (type: string, handler: () => void) => {
      (handlers[type] ??= []).push(handler);
    },
    removeEventListener: (type: string, handler: () => void) => {
      handlers[type] = (handlers[type] ?? []).filter((h) => h !== handler);
    },
    dispatch: (type: string) => {
      for (const handler of handlers[type] ?? []) handler();
    },
  };
}

function createFakeView() {
  const contentDOM = createFakeContentDOM();
  return { view: { contentDOM } as unknown as EditorView, contentDOM };
}

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

describe("createEditModeTracker", () => {
  beforeEach(() => {
    capacitorMock.platform = "web";
    capacitorMock.isNative = false;
    keyboardMock.listeners.clear();
    keyboardMock.addListener.mockClear();
  });

  it("on a non-Android platform, tracks focus/blur only and never touches the Keyboard plugin", () => {
    const { view, contentDOM } = createFakeView();
    const changes: boolean[] = [];
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v));

    contentDOM.dispatch("focus");
    expect(tracker.isEditMode()).toBe(true);

    contentDOM.dispatch("blur");
    expect(tracker.isEditMode()).toBe(false);

    expect(changes).toEqual([true, false]);
    expect(keyboardMock.addListener).not.toHaveBeenCalled();
  });

  it("on Android, a focus event alone activates edit mode - the hardware-keyboard/Chromebook case where no software keyboard ever shows and keyboardDidShow never fires", () => {
    capacitorMock.platform = "android";
    capacitorMock.isNative = true;
    const { view, contentDOM } = createFakeView();
    const changes: boolean[] = [];
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v));

    contentDOM.dispatch("focus");

    expect(tracker.isEditMode()).toBe(true);
    expect(changes).toEqual([true]);
  });

  it("on Android, keyboardDidHide still turns edit mode off even though focus never cleared - the dismiss-without-blur defect this must keep fixing", () => {
    capacitorMock.platform = "android";
    capacitorMock.isNative = true;
    const { view, contentDOM } = createFakeView();
    const changes: boolean[] = [];
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v));

    contentDOM.dispatch("focus");
    expect(tracker.isEditMode()).toBe(true);

    keyboardMock.listeners.get("keyboardDidHide")?.();

    expect(tracker.isEditMode()).toBe(false);
    expect(changes).toEqual([true, false]);
  });

  it("on Android, keyboardDidShow alone (no focus event observed) still activates edit mode", () => {
    capacitorMock.platform = "android";
    capacitorMock.isNative = true;
    const { view } = createFakeView();
    const changes: boolean[] = [];
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v));

    keyboardMock.listeners.get("keyboardDidShow")?.();

    expect(tracker.isEditMode()).toBe(true);
    expect(changes).toEqual([true]);
  });

  it("destroy() removes both the focus/blur listeners and the Keyboard plugin listeners on Android", () => {
    capacitorMock.platform = "android";
    capacitorMock.isNative = true;
    const { view, contentDOM } = createFakeView();
    const tracker = createEditModeTracker(view, false, () => {});

    tracker.destroy();
    contentDOM.dispatch("focus");

    expect(tracker.isEditMode()).toBe(false);
  });
});
