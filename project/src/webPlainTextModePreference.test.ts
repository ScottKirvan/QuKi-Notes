import { describe, expect, it } from "vitest";

import { readPlainTextModePreference, writePlainTextModePreference, type KeyValueStorage } from "./webPlainTextModePreference.js";

function fakeStorage(initial: Record<string, string> = {}): KeyValueStorage & { data: Record<string, string> } {
  const data = initial;
  return {
    data,
    getItem: (key) => (key in data ? data[key]! : null),
    setItem: (key, value) => {
      data[key] = value;
    },
  };
}

// BEHAVIOR_SPEC.md §4: the mode toggle's plain-text/rendered choice
// "persists across launches" - this is the plain browser/PWA build's
// counterpart of electron/src/preferences.ts's PreferencesStore and
// androidSettingsStore.ts's AndroidSettingsStore, which the web build has no
// equivalent of otherwise (STORAGE_CONTRACT.md: "the web app has no
// storage-location onboarding step"). window.localStorage is the natural
// per-origin analogue of those platforms' own small preferences file.
describe("readPlainTextModePreference", () => {
  it("defaults to false when nothing has been stored yet", () => {
    expect(readPlainTextModePreference(fakeStorage())).toBe(false);
  });

  it("returns true when a previous session stored true", () => {
    expect(readPlainTextModePreference(fakeStorage({ "quki.plainTextMode": "true" }))).toBe(true);
  });

  it("returns false when a previous session stored false", () => {
    expect(readPlainTextModePreference(fakeStorage({ "quki.plainTextMode": "false" }))).toBe(false);
  });

  it("treats an unrecognized stored value as false rather than throwing", () => {
    expect(readPlainTextModePreference(fakeStorage({ "quki.plainTextMode": "garbage" }))).toBe(false);
  });

  it("defaults to false rather than throwing if getItem itself throws (storage disabled/blocked)", () => {
    const storage: KeyValueStorage = {
      getItem: () => {
        throw new Error("storage disabled");
      },
      setItem: () => undefined,
    };
    expect(readPlainTextModePreference(storage)).toBe(false);
  });
});

describe("writePlainTextModePreference", () => {
  it("round-trips true", () => {
    const storage = fakeStorage();
    writePlainTextModePreference(storage, true);
    expect(readPlainTextModePreference(storage)).toBe(true);
  });

  it("round-trips false", () => {
    const storage = fakeStorage({ "quki.plainTextMode": "true" });
    writePlainTextModePreference(storage, false);
    expect(readPlainTextModePreference(storage)).toBe(false);
  });

  it("does not throw if setItem itself throws (storage disabled/full)", () => {
    const storage: KeyValueStorage = {
      getItem: () => null,
      setItem: () => {
        throw new Error("quota exceeded");
      },
    };
    expect(() => writePlainTextModePreference(storage, true)).not.toThrow();
  });
});
