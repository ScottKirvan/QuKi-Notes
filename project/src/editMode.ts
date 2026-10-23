import type { EditorView } from "@codemirror/view";
import { Capacitor } from "@capacitor/core";
import { Keyboard } from "@capacitor/keyboard";

/**
 * BEHAVIOR_SPEC.md §4: "Reading vs. edit mode is derived from editor
 * focus — nothing else." That's sufficient everywhere except Android,
 * where a user can dismiss the on-screen keyboard without clearing focus
 * — the defect that motivated this rewrite — so Android alone also needs
 * a real keyboard-visibility signal in addition to focus (not instead of
 * it: a Bluetooth keyboard or a Chromebook never shows a software
 * keyboard, so focus has to stay live there too, or that user's edit mode
 * would never activate at all). See createEditModeTracker below for how
 * the two signals combine.
 */
export function usesKeyboardSignal(platform: string, isNativePlatform: boolean): boolean {
  return isNativePlatform && platform === "android";
}

export type ToolbarScrollCorrectionTiming = "immediate" | "deferred";

/** What switched edit mode: the editor's focus/blur, or Android's keyboardDidShow/keyboardDidHide. */
export type EditModeSignal = "focus" | "keyboard";

/**
 * When edit mode turns on and the formatting toolbar appears, should the
 * caret's scroll-clear-of-the-toolbar correction (main.ts's
 * pendingToolbarScrollCheck mechanism) run right away, or wait for the
 * next selection change that actually moves the caret?
 *
 * Decided by the signal, not the platform. `focus` fires inside the tap
 * itself, before the tap's caret lands (on a touch tap the browser places
 * it after focus, and CodeMirror reads it later still), so the selection
 * is stale - on a QuKi opened from the list, the start of the text.
 * Scrolling to it there drags the view to the top, and the tap's caret is
 * then placed against the scrolled view. So it waits for the tap's caret.
 *
 * `keyboardDidShow` (Android) arrives after the keyboard has animated in,
 * long after the tap's caret landed; nothing is left to wait for.
 */
export function toolbarScrollCorrectionTiming(signal: EditModeSignal): ToolbarScrollCorrectionTiming {
  return signal === "keyboard" ? "immediate" : "deferred";
}

/**
 * BEHAVIOR_SPEC.md §4: "a new, blank QuKi takes focus (edit mode), an
 * existing QuKi does not (reading mode)." `initial.id` is null only for a
 * blank QuKi (see persistence.ts's InitialQuKi/loadInitialQuKi).
 */
export function shouldFocusOnOpen(initialId: string | null): boolean {
  return initialId === null;
}

export type ModeToggleIcon = "code" | "markdown";

/**
 * BEHAVIOR_SPEC.md §4: the mode toggle's icon shows the current format and
 * nothing else; reading vs. edit mode is not shown on it.
 */
export function modeToggleIcon(isPlainText: boolean): ModeToggleIcon {
  return isPlainText ? "code" : "markdown";
}

/**
 * BEHAVIOR_SPEC.md §4: in edit and reading mode alike, the mode toggle
 * switches between rendered and plain text, so its label names the mode a
 * tap switches to.
 */
export function modeToggleLabel(isPlainText: boolean): string {
  return isPlainText ? "Rendered mode" : "Plain text";
}

/**
 * A popup window of the app's own activity (Android's spelling suggestion
 * popup, the IME picker) takes window focus without blurring the editor,
 * and the Android System WebView hides the keyboard when the window loses
 * focus. keyboardDidHide fires when the keyboard's hide animation ends, so
 * it normally arrives after the window blur; this is how long after a blur
 * a hide still counts as the popup's.
 */
export const POPUP_KEYBOARD_HIDE_WINDOW_MS = 1000;

export interface PopupFocusState {
  windowFocused: boolean;
  lastWindowBlurAt: number | null;
  lastDismissAt: number | null;
  keyboardHiddenByPopup: boolean;
}

export const initialPopupFocusState: PopupFocusState = {
  windowFocused: true,
  lastWindowBlurAt: null,
  lastDismissAt: null,
  keyboardHiddenByPopup: false,
};

interface PageAndEditor {
  at: number;
  pageVisible: boolean;
  editorFocused: boolean;
}

export type PopupFocusEvent =
  | ({ kind: "windowBlur" } & PageAndEditor)
  | ({ kind: "windowFocus" } & PageAndEditor)
  | ({ kind: "keyboardHide" } & PageAndEditor)
  | { kind: "pageHidden"; at: number };

export type PopupFocusAction = "none" | "enterEditMode" | "leaveEditMode" | "showKeyboard";

const within = (since: number | null, at: number): boolean =>
  since !== null && at - since <= POPUP_KEYBOARD_HIDE_WINDOW_MS;

/**
 * Android only: what a keyboard hide, a window focus change or the page
 * hiding does to edit mode.
 *
 * A keyboard hide while the page is visible is the popup's when the window
 * has lost focus, or lost it within POPUP_KEYBOARD_HIDE_WINDOW_MS: edit mode
 * stays. Any other keyboard hide is the user dismissing the keyboard: edit
 * mode ends. A window blur within that time after such a dismiss means the
 * hide was the popup's after all: edit mode comes back.
 *
 * When the window regains focus after a popup hid the keyboard, the
 * keyboard is shown again if the page is visible and the editor still has
 * focus. If the page hides first (switching apps, locking the screen), edit
 * mode ends there as for any keyboard hide, and nothing is shown on return.
 */
export function decidePopupFocus(
  state: PopupFocusState,
  event: PopupFocusEvent,
): { state: PopupFocusState; action: PopupFocusAction } {
  switch (event.kind) {
    case "windowBlur": {
      const next = { ...state, windowFocused: false, lastWindowBlurAt: event.at, lastDismissAt: null };
      if (event.pageVisible && event.editorFocused && within(state.lastDismissAt, event.at)) {
        return { state: { ...next, keyboardHiddenByPopup: true }, action: "enterEditMode" };
      }
      return { state: next, action: "none" };
    }
    case "windowFocus": {
      const show = state.keyboardHiddenByPopup && event.pageVisible && event.editorFocused;
      return {
        state: { ...state, windowFocused: true, keyboardHiddenByPopup: false },
        action: show ? "showKeyboard" : "none",
      };
    }
    case "keyboardHide": {
      const byPopup = event.pageVisible && (!state.windowFocused || within(state.lastWindowBlurAt, event.at));
      if (!byPopup) return { state: { ...state, lastDismissAt: event.at }, action: "leaveEditMode" };
      const consumed = { ...state, lastWindowBlurAt: null };
      if (!state.windowFocused) return { state: { ...consumed, keyboardHiddenByPopup: true }, action: "none" };
      return { state: consumed, action: event.editorFocused ? "showKeyboard" : "none" };
    }
    case "pageHidden": {
      const next = { ...state, lastWindowBlurAt: null, lastDismissAt: null, keyboardHiddenByPopup: false };
      return { state: next, action: state.keyboardHiddenByPopup ? "leaveEditMode" : "none" };
    }
  }
}

/** The window and page signals the Android tracker reads, injected so tests can drive them. */
export interface WindowSignals {
  now(): number;
  isPageVisible(): boolean;
  /** Returns a function that removes the listener. */
  onWindowFocusChanged(callback: (hasFocus: boolean) => void): () => void;
  /** Returns a function that removes the listener. */
  onPageHidden(callback: () => void): () => void;
}

export interface EditModeTracker {
  isEditMode(): boolean;
  /** Removes whatever native/DOM listeners this tracker installed. */
  destroy(): void;
}

/**
 * Wires edit vs. reading mode to a real signal.
 *
 * Everywhere but Android, editor focus/blur is that signal directly.
 *
 * On Android, focus/blur alone isn't enough (see usesKeyboardSignal above):
 * dismissing the on-screen keyboard doesn't blur the editor, so the
 * dismiss would never be observed. Capacitor's keyboardDidShow/
 * keyboardDidHide cover that case. But keyboard-visibility events are
 * themselves not enough on their own: a Bluetooth keyboard or a Chromebook
 * never shows a software keyboard at all, so a device with no on-screen
 * keyboard would never fire keyboardDidShow and edit mode would never
 * activate for that user. So Android listens to *both* — focus/blur for
 * the hardware-keyboard/no-OSK case, keyboard-visibility for the
 * dismiss-without-blur case — and either signal can turn edit mode on or
 * off. The two don't fight: a hardware-keyboard session only ever fires
 * focus/blur (no OSK, so no keyboard events at all), and a software-
 * keyboard session's keyboardDidHide firing without a blur is exactly the
 * dismiss-without-blur defect this needs to keep fixing.
 *
 * `initialEditMode` seeds the state (from shouldFocusOnOpen) rather than
 * reading it back off the DOM/plugin, because on Android the caller's own
 * view.focus() call only *requests* the keyboard — the real
 * keyboardDidShow event that confirms it arrives asynchronously. Seeding
 * means the icon is already correct the instant the editor opens, and the
 * first real event (if any) just confirms it — setEditMode below is a
 * no-op when the new value matches, so no redundant re-render happens.
 */
export function createEditModeTracker(
  view: EditorView,
  initialEditMode: boolean,
  onChange: (isEditMode: boolean, signal: EditModeSignal) => void,
  windowSignals: WindowSignals,
): EditModeTracker {
  let editMode = initialEditMode;

  const setEditMode = (next: boolean, signal: EditModeSignal): void => {
    if (next === editMode) return;
    editMode = next;
    onChange(editMode, signal);
  };

  const onFocus = (): void => setEditMode(true, "focus");
  const onBlur = (): void => setEditMode(false, "focus");
  view.contentDOM.addEventListener("focus", onFocus);
  view.contentDOM.addEventListener("blur", onBlur);

  if (usesKeyboardSignal(Capacitor.getPlatform(), Capacitor.isNativePlatform())) {
    let popupState = initialPopupFocusState;
    const apply = (event: PopupFocusEvent): void => {
      const result = decidePopupFocus(popupState, event);
      popupState = result.state;
      if (result.action === "enterEditMode") setEditMode(true, "keyboard");
      else if (result.action === "leaveEditMode") setEditMode(false, "keyboard");
      else if (result.action === "showKeyboard") void Keyboard.show();
    };
    const pageAndEditor = () => ({
      at: windowSignals.now(),
      pageVisible: windowSignals.isPageVisible(),
      editorFocused: view.hasFocus,
    });

    const showHandle = Keyboard.addListener("keyboardDidShow", () => setEditMode(true, "keyboard"));
    const hideHandle = Keyboard.addListener("keyboardDidHide", () => apply({ kind: "keyboardHide", ...pageAndEditor() }));
    const removeWindowFocus = windowSignals.onWindowFocusChanged((hasFocus) =>
      apply({ kind: hasFocus ? "windowFocus" : "windowBlur", ...pageAndEditor() }),
    );
    const removePageHidden = windowSignals.onPageHidden(() => apply({ kind: "pageHidden", at: windowSignals.now() }));
    return {
      isEditMode: () => editMode,
      destroy: () => {
        view.contentDOM.removeEventListener("focus", onFocus);
        view.contentDOM.removeEventListener("blur", onBlur);
        void showHandle.then((handle) => handle.remove());
        void hideHandle.then((handle) => handle.remove());
        removeWindowFocus();
        removePageHidden();
      },
    };
  }

  return {
    isEditMode: () => editMode,
    destroy: () => {
      view.contentDOM.removeEventListener("focus", onFocus);
      view.contentDOM.removeEventListener("blur", onBlur);
    },
  };
}
