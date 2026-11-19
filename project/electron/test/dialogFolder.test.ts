import * as path from 'node:path';

import { describe, expect, it } from 'vitest';

import {
  folderFromOpenResult,
  folderFromSaveResult,
  openDialogDefaultPath,
  saveDialogDefaultPath,
} from '../src/dialogFolder.js';

const existing = new Set([path.resolve('/remembered/folder')]);
const isDirectory = (dir: string): boolean => existing.has(path.resolve(dir));

describe('openDialogDefaultPath', () => {
  it('opens in the remembered folder when it still exists', () => {
    expect(openDialogDefaultPath(path.resolve('/remembered/folder'), isDirectory)).toBe(path.resolve('/remembered/folder'));
  });

  it("falls back to Electron's default (no defaultPath) when nothing is remembered", () => {
    expect(openDialogDefaultPath(null, isDirectory)).toBeUndefined();
  });

  it("falls back to Electron's default when the remembered folder no longer exists", () => {
    expect(openDialogDefaultPath(path.resolve('/gone/folder'), isDirectory)).toBeUndefined();
  });
});

describe('saveDialogDefaultPath', () => {
  it('offers the suggested file name inside the remembered folder', () => {
    expect(saveDialogDefaultPath(path.resolve('/remembered/folder'), 'quki-export.tar.gz', isDirectory)).toBe(
      path.join(path.resolve('/remembered/folder'), 'quki-export.tar.gz'),
    );
  });

  it("offers the bare file name (Electron's default folder) when nothing is remembered", () => {
    expect(saveDialogDefaultPath(null, 'quki-export.tar.gz', isDirectory)).toBe('quki-export.tar.gz');
  });

  it("offers the bare file name (Electron's default folder) when the remembered folder no longer exists", () => {
    expect(saveDialogDefaultPath(path.resolve('/gone/folder'), 'quki-export.tar.gz', isDirectory)).toBe('quki-export.tar.gz');
  });
});

describe('folder to remember after a dialog closes', () => {
  it('remembers the folder picked in an open-folder dialog', () => {
    expect(folderFromOpenResult({ canceled: false, filePaths: ['/picked/folder'] })).toBe('/picked/folder');
  });

  it('remembers nothing when the open dialog was cancelled', () => {
    expect(folderFromOpenResult({ canceled: true, filePaths: [] })).toBeNull();
    expect(folderFromOpenResult({ canceled: false, filePaths: [] })).toBeNull();
  });

  it('remembers the folder the file was saved into', () => {
    const saved = path.join(path.resolve('/saved/here'), 'quki-export.tar.gz');
    expect(folderFromSaveResult({ canceled: false, filePath: saved })).toBe(path.resolve('/saved/here'));
  });

  it('remembers nothing when the save dialog was cancelled', () => {
    expect(folderFromSaveResult({ canceled: true, filePath: '' })).toBeNull();
    expect(folderFromSaveResult({ canceled: false, filePath: '' })).toBeNull();
  });
});
