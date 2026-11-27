import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { createFileFailureLogStore, FAILURE_LOG_FILE_NAME, type FailureLogCore } from '../src/failureLogFile.js';

const SENTINEL_TEXT = 'SENTINEL-BODY-TEXT-55aa';
const SENTINEL_FILE = 'sentinel-private-name';

describe('createFileFailureLogStore', () => {
  let dir: string;
  let file: string;
  let core: FailureLogCore;

  beforeEach(async () => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quki-failurelog-'));
    file = path.join(dir, 'nested', FAILURE_LOG_FILE_NAME);
    core = await import('quki-core');
  });
  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  const entry = (over: Record<string, unknown> = {}) => ({
    t: '2026-11-26T10:00:00.000Z',
    kind: 'storage',
    op: 'writeTextAtomic',
    version: '1.0.0',
    platform: 'linux',
    backend: 'electron-fs',
    process: 'main',
    code: 'EACCES',
    ...over,
  });

  it('appends to a file under the given folder, reads it back, and clears it', async () => {
    const store = createFileFailureLogStore(file, core);
    await store.append(entry() as never);
    await store.append(entry({ op: 'rename' }) as never);
    expect((await store.read()).map((e) => e.op)).toEqual(['writeTextAtomic', 'rename']);
    expect(fs.existsSync(file)).toBe(true);
    await store.clear();
    expect(await store.read()).toEqual([]);
    expect(fs.existsSync(file)).toBe(false);
  });

  it('drops the oldest entries when the log is full', async () => {
    const store = createFileFailureLogStore(file, core);
    for (let i = 0; i < 230; i++) await store.append(entry({ op: `op${i}` }) as never);
    const entries = await store.read();
    expect(entries).toHaveLength(200);
    expect(entries[0]!.op).toBe('op30');
    expect(entries.at(-1)!.op).toBe('op229');
  });

  it('rebuilds what the renderer sends, so text and filenames in extra fields never reach the file', async () => {
    const store = createFileFailureLogStore(file, core);
    await store.append(
      entry({ body: SENTINEL_TEXT, filename: `${SENTINEL_FILE}.md`, message: `open '/x/${SENTINEL_FILE}.md' ${SENTINEL_TEXT}` }) as never,
    );
    await store.append({ nonsense: true } as never);
    const onDisk = fs.readFileSync(file, 'utf8');
    expect(onDisk).not.toContain(SENTINEL_FILE);
    expect(JSON.parse(onDisk)).toHaveLength(1);
  });

  it('treats a corrupt file as empty and carries on', async () => {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, '{not json');
    const store = createFileFailureLogStore(file, core);
    expect(await store.read()).toEqual([]);
    await store.append(entry() as never);
    expect(await store.read()).toHaveLength(1);
  });
});
