import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import * as path from 'node:path';

/**
 * Best-effort default --dir: read the desktop app's own preferences.json for
 * its configured storage folder, used only when neither --dir nor QUKI_DIR
 * is given.
 *
 * The packaged Electron app's userData directory name is Electron's default
 * (app.getPath('userData') - electron/src/main.ts never calls
 * app.setName()), which this thin CLI package has no way to ask Electron for
 * directly since it runs standalone with no Electron app booted. Electron
 * derives that default from the app's own package.json "name" at packaging
 * time, which could plausibly end up as either electron/package.json's own
 * "name" or electron-builder.yml's "productName" - this checks both rather
 * than assuming one. NOT verified against a real packaged install (this
 * environment cannot build one); if neither candidate matches on a given
 * machine, the caller falls through to requiring --dir/QUKI_DIR as before.
 */
const CANDIDATE_APP_NAMES = ['QuKi Notes', 'quki-electron'];

export function candidateUserDataDirs(
  platform: NodeJS.Platform,
  env: NodeJS.ProcessEnv,
  home: string,
): string[] {
  if (platform === 'win32') {
    const appData = env.APPDATA ?? path.join(home, 'AppData', 'Roaming');
    return CANDIDATE_APP_NAMES.map((name) => path.join(appData, name));
  }
  if (platform === 'linux') {
    const configHome = env.XDG_CONFIG_HOME ?? path.join(home, '.config');
    return CANDIDATE_APP_NAMES.map((name) => path.join(configHome, name));
  }
  if (platform === 'darwin') {
    return CANDIDATE_APP_NAMES.map((name) => path.join(home, 'Library', 'Application Support', name));
  }
  return [];
}

export function resolveDesktopStorageDir(
  platform: NodeJS.Platform = process.platform,
  env: NodeJS.ProcessEnv = process.env,
  home: string = homedir(),
): string | null {
  for (const dir of candidateUserDataDirs(platform, env, home)) {
    const prefsPath = path.join(dir, 'preferences.json');
    if (!existsSync(prefsPath)) continue;
    try {
      const parsed = JSON.parse(readFileSync(prefsPath, 'utf8')) as { storagePath?: unknown };
      if (typeof parsed.storagePath === 'string' && parsed.storagePath.length > 0) {
        return parsed.storagePath;
      }
    } catch {
      continue;
    }
  }
  return null;
}
