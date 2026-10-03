import * as fsp from 'node:fs/promises';
import { tmpdir } from 'node:os';
import * as path from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';

import { resolveDesktopStorageDir } from '../src/desktopDir.js';

describe('resolveDesktopStorageDir', () => {
  let home: string;

  afterEach(async () => {
    if (home) await fsp.rm(home, { recursive: true, force: true });
  });

  it('returns null when no candidate preferences.json exists', async () => {
    home = await fsp.mkdtemp(path.join(tmpdir(), 'quki-mcp-desktop-dir-'));
    expect(resolveDesktopStorageDir('linux', {}, home)).toBeNull();
  });

  it('reads storagePath from the productName-named config dir on Linux', async () => {
    home = await fsp.mkdtemp(path.join(tmpdir(), 'quki-mcp-desktop-dir-'));
    const prefsDir = path.join(home, '.config', 'QuKi Notes');
    await fsp.mkdir(prefsDir, { recursive: true });
    await fsp.writeFile(
      path.join(prefsDir, 'preferences.json'),
      JSON.stringify({ storagePath: '/home/someone/qukis', storageChosen: true }),
    );

    expect(resolveDesktopStorageDir('linux', {}, home)).toBe('/home/someone/qukis');
  });

  it('falls back to the package-name config dir on Linux when productName is absent', async () => {
    home = await fsp.mkdtemp(path.join(tmpdir(), 'quki-mcp-desktop-dir-'));
    const prefsDir = path.join(home, '.config', 'quki-electron');
    await fsp.mkdir(prefsDir, { recursive: true });
    await fsp.writeFile(path.join(prefsDir, 'preferences.json'), JSON.stringify({ storagePath: '/home/someone/other' }));

    expect(resolveDesktopStorageDir('linux', {}, home)).toBe('/home/someone/other');
  });

  it('reads storagePath from %APPDATA% on Windows', async () => {
    home = await fsp.mkdtemp(path.join(tmpdir(), 'quki-mcp-desktop-dir-'));
    const appData = path.join(home, 'AppData', 'Roaming');
    const prefsDir = path.join(appData, 'QuKi Notes');
    await fsp.mkdir(prefsDir, { recursive: true });
    await fsp.writeFile(path.join(prefsDir, 'preferences.json'), JSON.stringify({ storagePath: 'C:\\qukis' }));

    expect(resolveDesktopStorageDir('win32', { APPDATA: appData }, home)).toBe('C:\\qukis');
  });

  it('ignores a preferences.json with no storagePath set', async () => {
    home = await fsp.mkdtemp(path.join(tmpdir(), 'quki-mcp-desktop-dir-'));
    const prefsDir = path.join(home, '.config', 'QuKi Notes');
    await fsp.mkdir(prefsDir, { recursive: true });
    await fsp.writeFile(path.join(prefsDir, 'preferences.json'), JSON.stringify({ storagePath: null, storageChosen: false }));

    expect(resolveDesktopStorageDir('linux', {}, home)).toBeNull();
  });

  it('ignores a corrupt preferences.json rather than throwing', async () => {
    home = await fsp.mkdtemp(path.join(tmpdir(), 'quki-mcp-desktop-dir-'));
    const prefsDir = path.join(home, '.config', 'QuKi Notes');
    await fsp.mkdir(prefsDir, { recursive: true });
    await fsp.writeFile(path.join(prefsDir, 'preferences.json'), '{not json');

    expect(resolveDesktopStorageDir('linux', {}, home)).toBeNull();
  });
});
