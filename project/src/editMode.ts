import type { EditorView } from "@codemirror/view";
import { Capacitor } from "@capacitor/core";
import { Keyboard } from "@capacitor/keyboard";

/**
 * BEHAVIOR_SPEC.md §4: "Reading vs. edit mode is derived from editor
 * focus — nothing else." That's true everywhere except Android: a
 * physical keyboard has no show/hide event, so focus is still a correct
 * signal on the web and on Electron. Android is the one platform where a
 * user can dismiss the on-screen keyboard without clearing focus — the
 * defect that motivated this rewrite — so Android alone needs a real
 * keyboard-visibility signal instead of focus.
 */
export function usesKeyboardSignal(platform: string, isNativePlatform: boolean): boolean {
  return isNativePlatform && platform === "android";
}

export type ToolbarScrollCorrectionTiming = "immediate" | "deferred";

/**
 * When edit mode turns on and the formatting toolbar appears, should the
 * caret's scroll-clear-of-the-toolbar correction (main.ts's
 * pendingToolbarScrollCheck mechanism) run right away, or wait for the
 * next selection change that actually moves the caret?
 *
 * On the focus/blur signal (everywhere but Android), `focus` can fire
 * before the same click's own selection-set transaction has landed, so the
 * correction has to wait for that transaction and act on its final
 * position - acting immediately would use the stale, pre-click selection.
 *
 * On the keyboard signal (Android), `keyboardDidShow` fires asynchronously,
 * well after the tap that triggered it already landed its selection
 * change - the OS keyboard animates in over real time. There is no future
 * selection change left to catch it on, so the correction has to run
 * immediately, using the selection as it already stands.
 */
export function toolbarScrollCorrectionTiming(usesKeyboardSignal: boolean): ToolbarScrollCorrectionTiming {
  return usesKeyboardSignal ? "immediate" : "deferred";
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

export interface EditModeTracker {
  isEditMode(): boolean;
  /** Removes whatever native/DOM listeners this tracker installed. */
  destroy(): void;
}

/**
 * Wires resolveModeIconState's edit/reading half to a real signal:
 * Capacitor's keyboardDidShow/keyboardDidHide on Android (see
 * usesKeyboardSignal above), editor focus/blur everywhere else.
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
  onChange: (isEditMode: boolean) => void,
): EditModeTracker {
  let editMode = initialEditMode;

  const setEditMode = (next: boolean): void => {
    if (next === editMode) return;
    editMode = next;
    onChange(editMode);
  };

  if (usesKeyboardSignal(Capacitor.getPlatform(), Capacitor.isNativePlatform())) {
    const showHandle = Keyboard.addListener("keyboardDidShow", () => setEditMode(true));
    const hideHandle = Keyboard.addListener("keyboardDidHide", () => setEditMode(false));
    return {
      isEditMode: () => editMode,
      destroy: () => {
        void showHandle.then((handle) => handle.remove());
        void hideHandle.then((handle) => handle.remove());
      },
    };
  }

  const onFocus = (): void => setEditMode(true);
  const onBlur = (): void => setEditMode(false);
  view.contentDOM.addEventListener("focus", onFocus);
  view.contentDOM.addEventListener("blur", onBlur);
  return {
    isEditMode: () => editMode,
    destroy: () => {
      view.contentDOM.removeEventListener("focus", onFocus);
      view.contentDOM.removeEventListener("blur", onBlur);
    },
  };
}
