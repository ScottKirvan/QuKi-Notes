import * as fs from 'node:fs';
import { tmpdir } from 'node:os';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { PreferencesStore } from '../src/preferences.js';

function makeTempDir(): string {
  return fs.mkdtempSync(path.join(tmpdir(), 'quki-electron-prefs-test-'));
}

describe('PreferencesStore', () => {
  let dir: string;
  let store: PreferencesStore;

  beforeEach(() => {
    dir = makeTempDir();
    store = new PreferencesStore(dir);
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  const DEFAULTS = { storagePath: null, storageChosen: false, windowX: null, windowY: null, windowWidth: null, windowHeight: null };

  it('reads defaults (storageChosen false, storagePath null, no window bounds) when no file exists yet - this is what defines first launch', () => {
    expect(store.read()).toEqual(DEFAULTS);
  });

  it('round-trips a written storage location', () => {
    store.write({ ...DEFAULTS, storagePath: '/some/folder', storageChosen: true });

    expect(store.read()).toEqual({ ...DEFAULTS, storagePath: '/some/folder', storageChosen: true });
  });

  it('setStorageLocation marks the choice made and persists the path', () => {
    const result = store.setStorageLocation('/chosen/folder');

    expect(result).toEqual({ ...DEFAULTS, storagePath: '/chosen/folder', storageChosen: true });
    expect(store.read()).toEqual({ ...DEFAULTS, storagePath: '/chosen/folder', storageChosen: true });
  });

  it('a later write replaces the earlier one rather than merging', () => {
    store.setStorageLocation('/first/folder');
    store.setStorageLocation('/second/folder');

    expect(store.read()).toEqual({ ...DEFAULTS, storagePath: '/second/folder', storageChosen: true });
  });

  it('setStorageLocation preserves previously-saved window bounds rather than wiping them', () => {
    store.setWindowBounds({ x: 10, y: 20, width: 800, height: 600 });

    store.setStorageLocation('/chosen/folder');

    expect(store.read()).toEqual({
      storagePath: '/chosen/folder',
      storageChosen: true,
      windowX: 10,
      windowY: 20,
      windowWidth: 800,
      windowHeight: 600,
    });
  });

  it('treats a corrupt preferences file as first launch instead of throwing', () => {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'preferences.json'), '{ not valid json', 'utf8');

    expect(store.read()).toEqual(DEFAULTS);
  });

  it('creates the userData directory if it does not exist yet', () => {
    const nestedDir = path.join(dir, 'nested', 'userData');
    const nestedStore = new PreferencesStore(nestedDir);

    expect(() => nestedStore.setStorageLocation('/x')).not.toThrow();
    expect(nestedStore.read()).toEqual({ ...DEFAULTS, storagePath: '/x', storageChosen: true });
  });

  it('ignores unrelated/malformed fields and falls back to defaults for them', () => {
    fs.writeFileSync(path.join(dir, 'preferences.json'), JSON.stringify({ storagePath: 42, someOtherKey: 'x' }), 'utf8');

    expect(store.read()).toEqual(DEFAULTS);
  });

  it('round-trips window bounds set via setWindowBounds', () => {
    const result = store.setWindowBounds({ x: 12, y: 34, width: 1024, height: 768 });

    expect(result).toEqual({ ...DEFAULTS, windowX: 12, windowY: 34, windowWidth: 1024, windowHeight: 768 });
    expect(store.read()).toEqual({ ...DEFAULTS, windowX: 12, windowY: 34, windowWidth: 1024, windowHeight: 768 });
  });

  it('setWindowBounds preserves a previously-chosen storage location rather than wiping it', () => {
    store.setStorageLocation('/chosen/folder');

    store.setWindowBounds({ x: 0, y: 0, width: 640, height: 480 });

    expect(store.read()).toEqual({
      storagePath: '/chosen/folder',
      storageChosen: true,
      windowX: 0,
      windowY: 0,
      windowWidth: 640,
      windowHeight: 480,
    });
  });

  it('treats a partial (some fields missing) window-bounds entry as absent per field rather than throwing', () => {
    fs.writeFileSync(
      path.join(dir, 'preferences.json'),
      JSON.stringify({ windowX: 5, windowY: 6, windowWidth: 'not-a-number' }),
      'utf8',
    );

    expect(store.read()).toEqual({ ...DEFAULTS, windowX: 5, windowY: 6 });
  });

  it('rejects wrongly-typed window-bounds values (array/boolean) as absent rather than passing them through', () => {
    fs.writeFileSync(
      path.join(dir, 'preferences.json'),
      JSON.stringify({ windowX: 5, windowY: null, windowWidth: [1, 2], windowHeight: true }),
      'utf8',
    );

    expect(store.read()).toEqual({ ...DEFAULTS, windowX: 5, windowHeight: null });
  });
});
