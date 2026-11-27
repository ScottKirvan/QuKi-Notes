import * as fs from 'node:fs';
import * as path from 'node:path';

// See main.ts for why this needs an explicit resolution-mode attribute.
import type { FailureEntry, FailureLogStore } from 'quki-core' with { 'resolution-mode': 'import' };

/** The pure pieces of quki-core's failureLog that this file uses, passed in because quki-core is ESM-only (main.ts imports it dynamically). */
export interface FailureLogCore {
  appendCapped(entries: readonly FailureEntry[], entry: FailureEntry): FailureEntry[];
  parseStoredLog(text: string | null): FailureEntry[];
  serializeLog(entries: readonly FailureEntry[]): string;
  sanitizeEntry(raw: unknown): FailureEntry | null;
}

export const FAILURE_LOG_FILE_NAME = 'failure-log.json';

/**
 * The failure log as one file in the app's own userData folder: private to
 * the app, outside every QuKi folder (so never part of Export everything),
 * and never sent anywhere. Every entry is rebuilt from its allowed fields on
 * the way in, so what the renderer sends over IPC cannot carry anything else.
 */
export function createFileFailureLogStore(filePath: string, core: FailureLogCore): FailureLogStore {
  const readAll = (): FailureEntry[] => {
    try {
      return core.parseStoredLog(fs.readFileSync(filePath, 'utf8'));
    } catch {
      return [];
    }
  };
  return {
    append(raw) {
      const entry = core.sanitizeEntry(raw);
      if (entry === null) return;
      fs.mkdirSync(path.dirname(filePath), { recursive: true });
      const tmp = `${filePath}.tmp`;
      fs.writeFileSync(tmp, core.serializeLog(core.appendCapped(readAll(), entry)));
      fs.renameSync(tmp, filePath);
    },
    async read() {
      return readAll();
    },
    async clear() {
      fs.rmSync(filePath, { force: true });
    },
  };
}
