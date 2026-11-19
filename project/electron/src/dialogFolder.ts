import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * Since Electron 43 a file dialog with no defaultPath opens in Downloads
 * every time, and Windows no longer restores the folder last used. These
 * helpers keep the Electron 33 behaviour: the folder last used in either
 * file dialog (Setup's folder picker, Settings -> Export's Save As) is
 * remembered in preferences.json and passed back as defaultPath.
 */
export type IsDirectory = (dir: string) => boolean;

export function isExistingDirectory(dir: string): boolean {
  try {
    return fs.statSync(dir).isDirectory();
  } catch {
    return false;
  }
}

function usableFolder(lastFolder: string | null, isDirectory: IsDirectory): string | null {
  return lastFolder !== null && isDirectory(lastFolder) ? lastFolder : null;
}

export function openDialogDefaultPath(lastFolder: string | null, isDirectory: IsDirectory): string | undefined {
  return usableFolder(lastFolder, isDirectory) ?? undefined;
}

export function saveDialogDefaultPath(lastFolder: string | null, fileName: string, isDirectory: IsDirectory): string {
  const folder = usableFolder(lastFolder, isDirectory);
  return folder === null ? fileName : path.join(folder, fileName);
}

export function folderFromOpenResult(result: { canceled: boolean; filePaths: string[] }): string | null {
  return result.canceled || result.filePaths.length === 0 ? null : result.filePaths[0]!;
}

export function folderFromSaveResult(result: { canceled: boolean; filePath?: string }): string | null {
  return result.canceled || !result.filePath ? null : path.dirname(result.filePath);
}
