/**
 * BEHAVIOR_SPEC.md §4: the mode toggle's plain-text/rendered choice
 * "persists across launches". Electron has PreferencesStore
 * (electron/src/preferences.ts) and Android has AndroidSettingsStore
 * (androidSettingsStore.ts), each backed by a small JSON file. The plain
 * browser/PWA build (main.ts's `setupApi` is undefined there - see
 * STORAGE_CONTRACT.md: "the web app has no storage-location onboarding
 * step") has no file of its own to hold this, so it uses window.localStorage
 * instead, the browser's own per-origin equivalent of a small preferences
 * file - injected as `storage` rather than read directly so this stays
 * unit-testable without a DOM.
 */

export interface KeyValueStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

const STORAGE_KEY = "quki.plainTextMode";

export function readPlainTextModePreference(storage: KeyValueStorage): boolean {
  try {
    return storage.getItem(STORAGE_KEY) === "true";
  } catch {
    // Storage disabled/blocked (private browsing, permissions) - defaults to
    // rendered mode rather than throwing during startup.
    return false;
  }
}

export function writePlainTextModePreference(storage: KeyValueStorage, value: boolean): void {
  try {
    storage.setItem(STORAGE_KEY, value ? "true" : "false");
  } catch {
    // Storage disabled/full - the preference silently won't persist this
    // time, matching readPlainTextModePreference's fail-open default.
  }
}
