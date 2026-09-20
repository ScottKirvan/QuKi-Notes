import * as fs from 'node:fs';
import { tmpdir } from 'node:os';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  folderHasMarkdownFile,
  readFlutterMigrationChoice,
  resolveFlutterPreferencesPath,
  resolveMigratedStorageRoot,
} from '../src/flutterMigration.js';

// A plain vi.spyOn(fs, 'writeFileSync') cannot work here: `fs` is imported as
// an ES module namespace object (both here and in flutterMigration.ts), and
// Node's Module Namespace Exotic Object rejects any attempt to redefine one
// of its own bindings - confirmed directly (a throwaway script attempting
// vi.spyOn's underlying Object.defineProperty, and even a plain reassignment,
// both threw "Cannot assign/redefine ... read only property"). vi.mock
// intercepts at module resolution instead of trying to mutate the namespace
// object after the fact, which is what actually lets a single test force
// fs.writeFileSync to fail while every other test keeps using the real
// implementation via the vi.fn(actual.writeFileSync) passthrough below.
vi.mock('node:fs', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:fs')>();
  return {
    ...actual,
    writeFileSync: vi.fn(actual.writeFileSync),
  };
});

function makeTempDir(): string {
  return fs.mkdtempSync(path.join(tmpdir(), 'quki-flutter-migration-test-'));
}

function mockedWriteFileSync(): ReturnType<typeof vi.fn> {
  return fs.writeFileSync as unknown as ReturnType<typeof vi.fn>;
}

describe('resolveFlutterPreferencesPath', () => {
  it('honors QUKI_ELECTRON_FLUTTER_PREFS_PATH as a full-path override', () => {
    expect(resolveFlutterPreferencesPath('win32', { QUKI_ELECTRON_FLUTTER_PREFS_PATH: '/fake/shared_preferences.json' })).toBe(
      '/fake/shared_preferences.json',
    );
  });

  it('treats an empty-string override as "no Flutter install"', () => {
    expect(resolveFlutterPreferencesPath('win32', { QUKI_ELECTRON_FLUTTER_PREFS_PATH: '' })).toBeNull();
  });

  it('resolves the real Windows path from %APPDATA% - com.quki\\quki_notes\\shared_preferences.json', () => {
    expect(resolveFlutterPreferencesPath('win32', { APPDATA: 'C:\\Users\\scott\\AppData\\Roaming' })).toBe(
      path.join('C:\\Users\\scott\\AppData\\Roaming', 'com.quki', 'quki_notes', 'shared_preferences.json'),
    );
  });

  it('returns null on win32 when APPDATA is unset', () => {
    expect(resolveFlutterPreferencesPath('win32', {})).toBeNull();
  });

  it('resolves the real Linux path from $XDG_DATA_HOME - com.quki.quki_notes/shared_preferences.json', () => {
    expect(resolveFlutterPreferencesPath('linux', { XDG_DATA_HOME: '/home/scott/.local/share' })).toBe(
      path.join('/home/scott/.local/share', 'com.quki.quki_notes', 'shared_preferences.json'),
    );
  });

  it('falls back to $HOME/.local/share on Linux when XDG_DATA_HOME is unset', () => {
    expect(resolveFlutterPreferencesPath('linux', { HOME: '/home/scott' })).toBe(
      path.join('/home/scott', '.local', 'share', 'com.quki.quki_notes', 'shared_preferences.json'),
    );
  });

  it('returns null on linux when neither XDG_DATA_HOME nor HOME is set', () => {
    expect(resolveFlutterPreferencesPath('linux', {})).toBeNull();
  });

  it('returns null on an unhandled platform with no override', () => {
    expect(resolveFlutterPreferencesPath('darwin', {})).toBeNull();
  });
});

describe('readFlutterMigrationChoice', () => {
  let dir: string;

  beforeEach(() => {
    dir = makeTempDir();
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('returns null when the file does not exist', () => {
    expect(readFlutterMigrationChoice(path.join(dir, 'missing.json'))).toBeNull();
  });

  it('returns null when the file is corrupt JSON', () => {
    const file = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(file, '{ not valid json', 'utf8');

    expect(readFlutterMigrationChoice(file)).toBeNull();
  });

  it('returns null when location_chosen is false', () => {
    const file = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(
      file,
      JSON.stringify({ 'flutter.storage.location_chosen': false, 'flutter.storage.base_path': '/some/folder' }),
      'utf8',
    );

    expect(readFlutterMigrationChoice(file)).toBeNull();
  });

  it('returns null when location_chosen is true but base_path is missing', () => {
    const file = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(file, JSON.stringify({ 'flutter.storage.location_chosen': true }), 'utf8');

    expect(readFlutterMigrationChoice(file)).toBeNull();
  });

  it('returns the chosen base path when location_chosen is true', () => {
    const file = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(
      file,
      JSON.stringify({ 'flutter.storage.location_chosen': true, 'flutter.storage.base_path': '/chosen/folder' }),
      'utf8',
    );

    expect(readFlutterMigrationChoice(file)).toEqual({ basePath: '/chosen/folder' });
  });

  it('ignores unrelated keys alongside the two it cares about', () => {
    const file = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(
      file,
      JSON.stringify({
        'flutter.storage.location_chosen': true,
        'flutter.storage.base_path': '/chosen/folder',
        'flutter.some_other_pref': 42,
      }),
      'utf8',
    );

    expect(readFlutterMigrationChoice(file)).toEqual({ basePath: '/chosen/folder' });
  });
});

describe('folderHasMarkdownFile', () => {
  let dir: string;

  beforeEach(() => {
    dir = makeTempDir();
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('returns false when the folder does not exist', () => {
    expect(folderHasMarkdownFile(path.join(dir, 'nope'))).toBe(false);
  });

  it('returns false for an empty folder', () => {
    expect(folderHasMarkdownFile(dir)).toBe(false);
  });

  it('returns false when the folder has files but none are .md', () => {
    fs.writeFileSync(path.join(dir, 'image.png'), 'x');

    expect(folderHasMarkdownFile(dir)).toBe(false);
  });

  it('returns true when the folder has at least one .md file', () => {
    fs.writeFileSync(path.join(dir, 'note.md'), '# hi');

    expect(folderHasMarkdownFile(dir)).toBe(true);
  });

  it('does not recurse into subfolders (STORAGE_CONTRACT.md rule 9: the folder is flat)', () => {
    fs.mkdirSync(path.join(dir, 'sub'));
    fs.writeFileSync(path.join(dir, 'sub', 'note.md'), '# hi');

    expect(folderHasMarkdownFile(dir)).toBe(false);
  });
});

// isValidWritableDirectory's own unit tests now live in
// storageValidation.test.ts, alongside the shared module it moved to - see
// storageValidation.ts's doc comment. It is still exercised indirectly here
// through resolveMigratedStorageRoot below.

describe('resolveMigratedStorageRoot', () => {
  let dir: string;

  beforeEach(() => {
    dir = makeTempDir();
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('adopts the Flutter app-recorded chosen path when present and it validates', () => {
    const chosenFolder = path.join(dir, 'chosen-folder');
    fs.mkdirSync(chosenFolder);
    const prefsPath = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(
      prefsPath,
      JSON.stringify({ 'flutter.storage.location_chosen': true, 'flutter.storage.base_path': chosenFolder }),
      'utf8',
    );
    const appStorageDir = path.join(dir, 'Documents', 'qukis');

    const result = resolveMigratedStorageRoot({
      platform: 'win32',
      env: { QUKI_ELECTRON_FLUTTER_PREFS_PATH: prefsPath },
      appStorageDir,
    });

    expect(result).toBe(chosenFolder);
  });

  it('does not adopt a Flutter-recorded path that no longer exists, and does not fall back to an empty app-storage folder either', () => {
    const staleChosenFolder = path.join(dir, 'moved-or-deleted-folder');
    const prefsPath = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(
      prefsPath,
      JSON.stringify({ 'flutter.storage.location_chosen': true, 'flutter.storage.base_path': staleChosenFolder }),
      'utf8',
    );
    const appStorageDir = path.join(dir, 'Documents', 'qukis');

    const result = resolveMigratedStorageRoot({
      platform: 'win32',
      env: { QUKI_ELECTRON_FLUTTER_PREFS_PATH: prefsPath },
      appStorageDir,
    });

    expect(result).toBeNull();
    expect(fs.existsSync(staleChosenFolder)).toBe(false);
  });

  it('falls through to the app-storage fallback when the Flutter-recorded path fails validation but the fallback folder validates', () => {
    const staleChosenFolder = path.join(dir, 'moved-or-deleted-folder');
    const prefsPath = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(
      prefsPath,
      JSON.stringify({ 'flutter.storage.location_chosen': true, 'flutter.storage.base_path': staleChosenFolder }),
      'utf8',
    );
    const appStorageDir = path.join(dir, 'Documents', 'qukis');
    fs.mkdirSync(appStorageDir, { recursive: true });
    fs.writeFileSync(path.join(appStorageDir, 'existing.md'), '# hi', 'utf8');

    const result = resolveMigratedStorageRoot({
      platform: 'win32',
      env: { QUKI_ELECTRON_FLUTTER_PREFS_PATH: prefsPath },
      appStorageDir,
    });

    expect(result).toBe(appStorageDir);
  });

  it('does not adopt an app-storage fallback folder that has markdown files but fails the writability probe', () => {
    const appStorageDir = path.join(dir, 'Documents', 'qukis');
    fs.mkdirSync(appStorageDir, { recursive: true });
    fs.writeFileSync(path.join(appStorageDir, 'existing.md'), '# hi', 'utf8');

    mockedWriteFileSync().mockImplementationOnce(() => {
      throw new Error('EACCES: permission denied (simulated)');
    });

    const result = resolveMigratedStorageRoot({
      platform: 'win32',
      env: { QUKI_ELECTRON_FLUTTER_PREFS_PATH: '' },
      appStorageDir,
    });

    expect(result).toBeNull();
  });

  it('falls back to the app-storage folder when no Flutter choice was recorded but it already has QuKis', () => {
    const appStorageDir = path.join(dir, 'Documents', 'qukis');
    fs.mkdirSync(appStorageDir, { recursive: true });
    fs.writeFileSync(path.join(appStorageDir, 'existing.md'), '# hi');

    const result = resolveMigratedStorageRoot({
      platform: 'win32',
      env: { QUKI_ELECTRON_FLUTTER_PREFS_PATH: '' },
      appStorageDir,
    });

    expect(result).toBe(appStorageDir);
  });

  it('prefers the Flutter-recorded choice over the app-storage fallback when both are present and both validate', () => {
    const chosenFolder = path.join(dir, 'chosen-folder');
    fs.mkdirSync(chosenFolder);
    const prefsPath = path.join(dir, 'shared_preferences.json');
    fs.writeFileSync(
      prefsPath,
      JSON.stringify({ 'flutter.storage.location_chosen': true, 'flutter.storage.base_path': chosenFolder }),
      'utf8',
    );
    const appStorageDir = path.join(dir, 'Documents', 'qukis');
    fs.mkdirSync(appStorageDir, { recursive: true });
    fs.writeFileSync(path.join(appStorageDir, 'existing.md'), '# hi');

    const result = resolveMigratedStorageRoot({
      platform: 'win32',
      env: { QUKI_ELECTRON_FLUTTER_PREFS_PATH: prefsPath },
      appStorageDir,
    });

    expect(result).toBe(chosenFolder);
  });

  it('returns null when neither a Flutter choice nor an existing app-storage folder is found', () => {
    const appStorageDir = path.join(dir, 'Documents', 'qukis');

    const result = resolveMigratedStorageRoot({
      platform: 'win32',
      env: { QUKI_ELECTRON_FLUTTER_PREFS_PATH: '' },
      appStorageDir,
    });

    expect(result).toBeNull();
  });
});
