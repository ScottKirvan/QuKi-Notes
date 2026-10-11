/**
 * App-level user preferences that are not QuKi content, not an image, and
 * not trash state - STORAGE_CONTRACT.md's rules don't govern where these
 * live: "delete orphaned images" (rule 13: "This behavior is a user-facing
 * setting, defaulting to delete."), the editor's text size and whether the
 * word count shows.
 *
 * [Proposed — unconfirmed] Backed by whatever key/value storage the caller
 * hands in (real usage: window.localStorage) rather than a file under the
 * QuKi folder or a platform-specific settings file, since this preference
 * applies identically across the web build, Electron's renderer and
 * Capacitor's Android WebView - all of which expose localStorage - and
 * isn't something that should travel with the QuKi folder the way
 * .quki/-scoped configuration does. Not a decision Scott has made; flagged
 * here for review rather than written in as settled.
 *
 * Takes the storage dependency through a narrow interface (same pattern as
 * AndroidSettingsStore) so tests don't depend on a real browser global.
 */

import { DEFAULT_FONT_SIZE, parseFontSize, type FontSize } from "./fontSize";

export interface AppSettingsStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

const DELETE_ORPHANED_IMAGES_KEY = "quki.settings.deleteOrphanedImages";
const FONT_SIZE_KEY = "quki.settings.fontSize";
const SHOW_WORD_COUNT_KEY = "quki.settings.showWordCount";

/** STORAGE_CONTRACT.md rule 13: "This behavior is a user-facing setting, defaulting to delete." */
const DELETE_ORPHANED_IMAGES_DEFAULT = true;

export class AppSettingsStore {
  constructor(private readonly storage: AppSettingsStorage) {}

  getDeleteOrphanedImages(): boolean {
    try {
      const raw = this.storage.getItem(DELETE_ORPHANED_IMAGES_KEY);
      if (raw === null) return DELETE_ORPHANED_IMAGES_DEFAULT;
      return raw === "true";
    } catch {
      // A private-browsing quota error or disabled storage shouldn't crash
      // the settings screen or the startup sweep - fall back to the
      // documented default instead.
      return DELETE_ORPHANED_IMAGES_DEFAULT;
    }
  }

  setDeleteOrphanedImages(value: boolean): void {
    try {
      this.storage.setItem(DELETE_ORPHANED_IMAGES_KEY, String(value));
    } catch {
      // Best-effort, same reasoning as the read side above - the toggle
      // just won't persist across reloads in that case.
    }
  }

  getFontSize(): FontSize {
    try {
      return parseFontSize(this.storage.getItem(FONT_SIZE_KEY));
    } catch {
      return DEFAULT_FONT_SIZE;
    }
  }

  setFontSize(value: FontSize): void {
    try {
      this.storage.setItem(FONT_SIZE_KEY, value);
    } catch {
      // Best-effort, as setDeleteOrphanedImages.
    }
  }

  getShowWordCount(): boolean {
    try {
      return this.storage.getItem(SHOW_WORD_COUNT_KEY) === "true";
    } catch {
      return false;
    }
  }

  setShowWordCount(value: boolean): void {
    try {
      this.storage.setItem(SHOW_WORD_COUNT_KEY, String(value));
    } catch {
      // Best-effort, as setDeleteOrphanedImages.
    }
  }
}
