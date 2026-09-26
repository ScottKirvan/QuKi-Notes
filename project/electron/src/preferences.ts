import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * BEHAVIOR_SPEC.md §3: "Two preferences record the outcome: the chosen
 * absolute path, and a flag marking that a choice was made. The flag's
 * absence is what defines 'first launch.'" storageChosen is kept as its own
 * field (rather than derived from storagePath !== null) so that shape
 * matches the spec's wording exactly.
 *
 * BEHAVIOR_SPEC.md §10: "Window position and size are stored as four
 * preferences and restored at launch... If any is missing, the OS places
 * the window instead." windowX/Y/Width/Height are four separate optional
 * fields (rather than one nested object) so "any is missing" is a plain
 * null-check per field, matching how storagePath/storageChosen already work
 * in this same shape.
 */
export interface Preferences {
  storagePath: string | null;
  storageChosen: boolean;
  windowX: number | null;
  windowY: number | null;
  windowWidth: number | null;
  windowHeight: number | null;
}

const DEFAULT_PREFERENCES: Preferences = {
  storagePath: null,
  storageChosen: false,
  windowX: null,
  windowY: null,
  windowWidth: null,
  windowHeight: null,
};

const PREFERENCES_FILE_NAME = 'preferences.json';

function readFiniteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

/**
 * A small JSON file under Electron's per-user app data directory
 * (app.getPath('userData') - see main.ts), read/written with plain
 * node:fs. No third-party preferences package: the shape is a handful of
 * flat fields and plain JSON already covers that.
 *
 * Deliberately generic beyond the two storage-location fields the spec
 * requires today - window state and the mode-toggle persistence
 * (BEHAVIOR_SPEC.md §4) are both later chunks likely to want the same file,
 * so read()/write() round-trip whatever shape Preferences ends up being
 * rather than hardcoding just the two current fields through the API.
 */
export class PreferencesStore {
  private readonly filePath: string;

  constructor(userDataDir: string) {
    this.filePath = path.join(userDataDir, PREFERENCES_FILE_NAME);
  }

  read(): Preferences {
    let raw: string;
    try {
      raw = fs.readFileSync(this.filePath, 'utf8');
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return { ...DEFAULT_PREFERENCES };
      throw err;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      // A corrupt preferences file is treated the same as a missing one -
      // first launch again - rather than throwing and blocking startup.
      return { ...DEFAULT_PREFERENCES };
    }
    const candidate = parsed as Partial<Preferences> | null;
    return {
      storagePath: typeof candidate?.storagePath === 'string' ? candidate.storagePath : null,
      storageChosen: candidate?.storageChosen === true,
      windowX: readFiniteNumber(candidate?.windowX),
      windowY: readFiniteNumber(candidate?.windowY),
      windowWidth: readFiniteNumber(candidate?.windowWidth),
      windowHeight: readFiniteNumber(candidate?.windowHeight),
    };
  }

  write(prefs: Preferences): void {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    const tmp = `${this.filePath}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(prefs, null, 2), 'utf8');
    fs.renameSync(tmp, this.filePath);
  }

  setStorageLocation(storagePath: string): Preferences {
    // Merges onto the current file rather than overwriting wholesale - a
    // storage-location choice (setup screen, Change location) must not
    // discard window bounds a previous session already saved, now that this
    // store holds more than the two storage fields.
    const prefs: Preferences = { ...this.read(), storagePath, storageChosen: true };
    this.write(prefs);
    return prefs;
  }

  setWindowBounds(bounds: { x: number; y: number; width: number; height: number }): Preferences {
    const prefs: Preferences = {
      ...this.read(),
      windowX: bounds.x,
      windowY: bounds.y,
      windowWidth: bounds.width,
      windowHeight: bounds.height,
    };
    this.write(prefs);
    return prefs;
  }
}
