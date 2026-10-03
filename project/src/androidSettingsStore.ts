/**
 * Android's counterpart of electron/src/preferences.ts's PreferencesStore -
 * same field names (storagePath, storageChosen) and the same "a missing or
 * corrupt file reads back as not-yet-chosen" behavior, but async throughout
 * (a Capacitor plugin call, unlike node:fs, has no synchronous form) and
 * backed by CapacitorStoragePlugin's already-existing generic file I/O
 * (readText/writeTextAtomic/exists) rather than new native persistence -
 * StoragePlugin.kt's writeTextAtomic is already genuinely atomic
 * (temp-then-rename), so nothing new is needed on the native side for this.
 *
 * Lives at a fixed path under the app's private storage
 * (`${privateStoragePath}/quki_settings.json`, composed by the caller -
 * androidSetupApi.ts) rather than under whatever the *current* QuKi root is,
 * so the choice of where QuKis live doesn't affect where the record of that
 * choice lives.
 */

export interface AndroidSettings {
  storagePath: string | null;
  storageChosen: boolean;
  /** BEHAVIOR_SPEC.md §4: the mode toggle's plain-text/rendered choice "persists across launches". */
  plainTextMode: boolean;
}

const DEFAULT_SETTINGS: AndroidSettings = {
  storagePath: null,
  storageChosen: false,
  plainTextMode: false,
};

export interface AndroidSettingsDeps {
  exists(path: string): Promise<boolean>;
  readText(path: string): Promise<string>;
  writeTextAtomic(path: string, content: string): Promise<void>;
}

export class AndroidSettingsStore {
  constructor(
    private readonly deps: AndroidSettingsDeps,
    private readonly filePath: string,
  ) {}

  async read(): Promise<AndroidSettings> {
    if (!(await this.deps.exists(this.filePath))) return { ...DEFAULT_SETTINGS };

    let raw: string;
    try {
      raw = await this.deps.readText(this.filePath);
    } catch {
      // Same treatment as a missing file - PreferencesStore.read()'s ENOENT
      // handling - rather than throwing and blocking startup on a read race
      // or an unexpected native I/O failure.
      return { ...DEFAULT_SETTINGS };
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return { ...DEFAULT_SETTINGS };
    }

    const candidate = parsed as Partial<AndroidSettings> | null;
    return {
      storagePath: typeof candidate?.storagePath === "string" ? candidate.storagePath : null,
      storageChosen: candidate?.storageChosen === true,
      plainTextMode: candidate?.plainTextMode === true,
    };
  }

  async write(settings: AndroidSettings): Promise<void> {
    await this.deps.writeTextAtomic(this.filePath, JSON.stringify(settings, null, 2));
  }

  /**
   * Merges onto the current file rather than overwriting wholesale - matching
   * PreferencesStore.setStorageLocation (electron/src/preferences.ts), so a
   * storage-location change doesn't discard a previously-set plainTextMode
   * (or vice versa in setPlainTextMode below).
   */
  async setStorageLocation(storagePath: string): Promise<AndroidSettings> {
    const settings: AndroidSettings = { ...(await this.read()), storagePath, storageChosen: true };
    await this.write(settings);
    return settings;
  }

  async setPlainTextMode(plainTextMode: boolean): Promise<AndroidSettings> {
    const settings: AndroidSettings = { ...(await this.read()), plainTextMode };
    await this.write(settings);
    return settings;
  }
}
