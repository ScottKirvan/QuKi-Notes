import { beforeEach, describe, expect, it, vi } from "vitest";
import type { EditorView } from "@codemirror/view";
import type { PopupFocusAction, PopupFocusEvent, WindowSignals } from "./editMode.js";

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
  show: vi.fn(() => Promise.resolve()),
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
    show: keyboardMock.show,
  },
}));

const {
  createEditModeTracker,
  decidePopupFocus,
  initialPopupFocusState,
  modeToggleIcon,
  modeToggleLabel,
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
  const view = { contentDOM, hasFocus: false };
  contentDOM.addEventListener("focus", () => (view.hasFocus = true));
  contentDOM.addEventListener("blur", () => (view.hasFocus = false));
  return { view: view as unknown as EditorView, contentDOM };
}

function createFakeWindowSignals() {
  let now = 0;
  let pageVisible = true;
  const focusListeners = new Set<(hasFocus: boolean) => void>();
  const hiddenListeners = new Set<() => void>();
  const signals: WindowSignals = {
    now: () => now,
    isPageVisible: () => pageVisible,
    onWindowFocusChanged: (callback) => {
      focusListeners.add(callback);
      return () => focusListeners.delete(callback);
    },
    onPageHidden: (callback) => {
      hiddenListeners.add(callback);
      return () => hiddenListeners.delete(callback);
    },
  };
  return {
    signals,
    setNow: (ms: number) => (now = ms),
    windowFocus: (hasFocus: boolean) => {
      for (const listener of [...focusListeners]) listener(hasFocus);
    },
    hidePage: () => {
      pageVisible = false;
      for (const listener of [...hiddenListeners]) listener();
    },
    showPage: () => (pageVisible = true),
    listenerCount: () => focusListeners.size + hiddenListeners.size,
  };
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
  it("is immediate when keyboardDidShow switched edit mode on - the tap's caret landed long before", () => {
    expect(toolbarScrollCorrectionTiming("keyboard")).toBe("immediate");
  });

  it("is deferred when focus switched edit mode on, on every platform - the tap's own caret has not landed yet", () => {
    expect(toolbarScrollCorrectionTiming("focus")).toBe("deferred");
  });
});

describe("modeToggleIcon", () => {
  it("is the code icon in plain-text mode", () => {
    expect(modeToggleIcon(true)).toBe("code");
  });

  it("is the markdown mark when rendered", () => {
    expect(modeToggleIcon(false)).toBe("markdown");
  });
});

describe("modeToggleLabel", () => {
  it("names plain text as what a tap switches to from rendered", () => {
    expect(modeToggleLabel(false)).toBe("Plain text");
  });

  it("names rendered as what a tap switches to from plain text", () => {
    expect(modeToggleLabel(true)).toBe("Rendered mode");
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
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v), createFakeWindowSignals().signals);

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
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v), createFakeWindowSignals().signals);

    contentDOM.dispatch("focus");

    expect(tracker.isEditMode()).toBe(true);
    expect(changes).toEqual([true]);
  });

  it("on Android, keyboardDidHide still turns edit mode off even though focus never cleared - the dismiss-without-blur defect this must keep fixing", () => {
    capacitorMock.platform = "android";
    capacitorMock.isNative = true;
    const { view, contentDOM } = createFakeView();
    const changes: boolean[] = [];
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v), createFakeWindowSignals().signals);

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
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v), createFakeWindowSignals().signals);

    keyboardMock.listeners.get("keyboardDidShow")?.();

    expect(tracker.isEditMode()).toBe(true);
    expect(changes).toEqual([true]);
  });

  it("on Android, reports which signal switched edit mode - a tap's focus, or the keyboard", () => {
    capacitorMock.platform = "android";
    capacitorMock.isNative = true;
    const { view, contentDOM } = createFakeView();
    const signals: string[] = [];
    createEditModeTracker(
      view,
      false,
      (v, signal) => signals.push(`${v}:${signal}`),
      createFakeWindowSignals().signals,
    );

    contentDOM.dispatch("focus");
    keyboardMock.listeners.get("keyboardDidHide")?.();
    keyboardMock.listeners.get("keyboardDidShow")?.();
    contentDOM.dispatch("blur");

    expect(signals).toEqual(["true:focus", "false:keyboard", "true:keyboard", "false:focus"]);
  });

  it("destroy() removes both the focus/blur listeners and the Keyboard plugin listeners on Android", () => {
    capacitorMock.platform = "android";
    capacitorMock.isNative = true;
    const { view, contentDOM } = createFakeView();
    const tracker = createEditModeTracker(view, false, () => {}, createFakeWindowSignals().signals);

    tracker.destroy();
    contentDOM.dispatch("focus");

    expect(tracker.isEditMode()).toBe(false);
  });
});

describe("decidePopupFocus", () => {
  const visibleFocused = { pageVisible: true, editorFocused: true };

  function run(events: PopupFocusEvent[]): PopupFocusAction[] {
    let state = initialPopupFocusState;
    const actions: PopupFocusAction[] = [];
    for (const event of events) {
      const result = decidePopupFocus(state, event);
      state = result.state;
      actions.push(result.action);
    }
    return actions;
  }

  it("popup opens: the window loses focus, then the keyboard hides while the page is visible - edit mode stays", () => {
    expect(
      run([
        { kind: "windowBlur", at: 0, ...visibleFocused },
        { kind: "keyboardHide", at: 300, ...visibleFocused },
      ]),
    ).toEqual(["none", "none"]);
  });

  it("popup closes: the window regains focus with the editor still focused - the keyboard comes back", () => {
    expect(
      run([
        { kind: "windowBlur", at: 0, ...visibleFocused },
        { kind: "keyboardHide", at: 300, ...visibleFocused },
        { kind: "windowFocus", at: 5000, ...visibleFocused },
      ]),
    ).toEqual(["none", "none", "showKeyboard"]);
  });

  it("popup closes before the keyboard finished hiding: the late hide brings the keyboard straight back", () => {
    expect(
      run([
        { kind: "windowBlur", at: 0, ...visibleFocused },
        { kind: "windowFocus", at: 200, ...visibleFocused },
        { kind: "keyboardHide", at: 350, ...visibleFocused },
      ]),
    ).toEqual(["none", "none", "showKeyboard"]);
  });

  it("popup closes after the editor lost focus: the keyboard is not shown", () => {
    expect(
      run([
        { kind: "windowBlur", at: 0, ...visibleFocused },
        { kind: "keyboardHide", at: 300, ...visibleFocused },
        { kind: "windowFocus", at: 5000, pageVisible: true, editorFocused: false },
      ]),
    ).toEqual(["none", "none", "none"]);
  });

  it("Back dismisses the keyboard (the window keeps focus): edit mode ends", () => {
    expect(run([{ kind: "keyboardHide", at: 0, ...visibleFocused }])).toEqual(["leaveEditMode"]);
  });

  it("a keyboard hide long after an earlier popup is an ordinary dismiss", () => {
    expect(
      run([
        { kind: "windowBlur", at: 0, ...visibleFocused },
        { kind: "keyboardHide", at: 300, ...visibleFocused },
        { kind: "windowFocus", at: 2000, ...visibleFocused },
        { kind: "keyboardHide", at: 9000, ...visibleFocused },
      ]),
    ).toEqual(["none", "none", "showKeyboard", "leaveEditMode"]);
  });

  it("the keyboard hide arriving just before the window blur: edit mode comes back and the popup is waited out", () => {
    expect(
      run([
        { kind: "keyboardHide", at: 0, ...visibleFocused },
        { kind: "windowBlur", at: 100, ...visibleFocused },
        { kind: "windowFocus", at: 4000, ...visibleFocused },
      ]),
    ).toEqual(["leaveEditMode", "enterEditMode", "showKeyboard"]);
  });

  it("a window blur well after a Back dismiss does not bring edit mode back", () => {
    expect(
      run([
        { kind: "keyboardHide", at: 0, ...visibleFocused },
        { kind: "windowBlur", at: 5000, ...visibleFocused },
        { kind: "windowFocus", at: 8000, ...visibleFocused },
      ]),
    ).toEqual(["leaveEditMode", "none", "none"]);
  });

  it("app switch, keyboard hide after the page is hidden: edit mode ends, and returning does not show the keyboard", () => {
    expect(
      run([
        { kind: "windowBlur", at: 0, ...visibleFocused },
        { kind: "pageHidden", at: 50 },
        { kind: "keyboardHide", at: 300, pageVisible: false, editorFocused: true },
        { kind: "windowFocus", at: 60000, ...visibleFocused },
      ]),
    ).toEqual(["none", "none", "leaveEditMode", "none"]);
  });

  it("app switch, keyboard hide before the page is hidden: edit mode ends when the page hides, and returning does not show the keyboard", () => {
    expect(
      run([
        { kind: "windowBlur", at: 0, ...visibleFocused },
        { kind: "keyboardHide", at: 300, ...visibleFocused },
        { kind: "pageHidden", at: 400 },
        { kind: "windowFocus", at: 60000, ...visibleFocused },
      ]),
    ).toEqual(["none", "none", "leaveEditMode", "none"]);
  });

  it("a keyboard hide right after returning to the app is an ordinary dismiss, not a popup's", () => {
    expect(
      run([
        { kind: "windowBlur", at: 0, ...visibleFocused },
        { kind: "pageHidden", at: 50 },
        { kind: "windowFocus", at: 400, ...visibleFocused },
        { kind: "keyboardHide", at: 600, ...visibleFocused },
      ]),
    ).toEqual(["none", "none", "none", "leaveEditMode"]);
  });
});

describe("createEditModeTracker with a popup taking window focus (Android)", () => {
  beforeEach(() => {
    capacitorMock.platform = "android";
    capacitorMock.isNative = true;
    keyboardMock.listeners.clear();
    keyboardMock.show.mockClear();
  });

  it("the spelling popup opening keeps edit mode, and its closing shows the keyboard again", () => {
    const { view, contentDOM } = createFakeView();
    const fake = createFakeWindowSignals();
    const changes: boolean[] = [];
    const tracker = createEditModeTracker(view, false, (v) => changes.push(v), fake.signals);

    contentDOM.dispatch("focus");
    fake.setNow(1000);
    fake.windowFocus(false);
    fake.setNow(1300);
    keyboardMock.listeners.get("keyboardDidHide")?.();

    expect(tracker.isEditMode()).toBe(true);
    expect(keyboardMock.show).not.toHaveBeenCalled();

    fake.setNow(4000);
    fake.windowFocus(true);

    expect(tracker.isEditMode()).toBe(true);
    expect(changes).toEqual([true]);
    expect(keyboardMock.show).toHaveBeenCalledTimes(1);
  });

  it("Back dismissing the keyboard still ends edit mode and shows nothing", () => {
    const { view, contentDOM } = createFakeView();
    const fake = createFakeWindowSignals();
    const tracker = createEditModeTracker(view, false, () => {}, fake.signals);

    contentDOM.dispatch("focus");
    fake.setNow(1000);
    keyboardMock.listeners.get("keyboardDidHide")?.();

    expect(tracker.isEditMode()).toBe(false);
    expect(keyboardMock.show).not.toHaveBeenCalled();
  });

  it("switching apps ends edit mode when the page hides and does not show the keyboard on return", () => {
    const { view, contentDOM } = createFakeView();
    const fake = createFakeWindowSignals();
    const tracker = createEditModeTracker(view, false, () => {}, fake.signals);

    contentDOM.dispatch("focus");
    fake.setNow(1000);
    fake.windowFocus(false);
    fake.setNow(1300);
    keyboardMock.listeners.get("keyboardDidHide")?.();
    fake.hidePage();

    expect(tracker.isEditMode()).toBe(false);

    fake.showPage();
    fake.setNow(60000);
    fake.windowFocus(true);

    expect(tracker.isEditMode()).toBe(false);
    expect(keyboardMock.show).not.toHaveBeenCalled();
  });

  it("destroy() removes the window focus and page visibility listeners", () => {
    const { view, contentDOM } = createFakeView();
    const fake = createFakeWindowSignals();
    const tracker = createEditModeTracker(view, false, () => {}, fake.signals);

    tracker.destroy();
    contentDOM.dispatch("focus");
    fake.windowFocus(false);
    fake.windowFocus(true);

    expect(fake.listenerCount()).toBe(0);
    expect(keyboardMock.show).not.toHaveBeenCalled();
  });
});
