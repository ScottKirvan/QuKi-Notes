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

export type ModeIconState = "plain-text" | "edit" | "reading";

/**
 * The mode-toggle icon's three states (BEHAVIOR_SPEC.md §4): a code icon
 * in plain-text mode, a markdown mark in edit mode, an open book in
 * reading mode. Plain-text is orthogonal to and takes priority over
 * edit/reading, matching the reference app's own icon precedence.
 */
export function resolveModeIconState(isPlainText: boolean, isEditMode: boolean): ModeIconState {
  if (isPlainText) return "plain-text";
  return isEditMode ? "edit" : "reading";
}

export type ModeToggleAction = "toggle-plain-text" | "start-editing";

/**
 * BEHAVIOR_SPEC.md §4: while editing, the mode toggle switches between
 * rendered and plain text; while reading (on Android, keyboard down) it only
 * brings editing back and leaves the mode as it is.
 */
export function modeToggleAction(isEditMode: boolean): ModeToggleAction {
  return isEditMode ? "toggle-plain-text" : "start-editing";
}

export interface EditModeTracker {
  isEditMode(): boolean;
  /** Removes whatever native/DOM listeners this tracker installed. */
  destroy(): void;
}

/**
 * Wires resolveModeIconState's edit/reading half to a real signal.
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
    const showHandle = Keyboard.addListener("keyboardDidShow", () => setEditMode(true, "keyboard"));
    const hideHandle = Keyboard.addListener("keyboardDidHide", () => setEditMode(false, "keyboard"));
    return {
      isEditMode: () => editMode,
      destroy: () => {
        view.contentDOM.removeEventListener("focus", onFocus);
        view.contentDOM.removeEventListener("blur", onBlur);
        void showHandle.then((handle) => handle.remove());
        void hideHandle.then((handle) => handle.remove());
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
