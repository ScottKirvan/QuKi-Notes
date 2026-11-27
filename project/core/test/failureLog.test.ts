import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  appendCapped,
  buildEntry,
  createFailureRecorder,
  createKeyValueFailureLog,
  formatLog,
  parseStoredLog,
  sanitizeEntry,
  withFailureLogging,
  type FailureContext,
  type FailureEntry,
  type KeyValueStorage,
} from '../src/failureLog.js';
import { NodeFsBackend } from '../src/node.js';
import { NotFoundError } from '../src/types.js';
import { cleanupTempDir, makeTempQuKiDir } from './helpers.js';

const SENTINEL_TEXT = 'SENTINEL-BODY-TEXT-7f3a';
const SENTINEL_FILE = 'sentinel-private-name';
const context: FailureContext = { version: '1.2.3', platform: 'web', backend: 'opfs', process: 'renderer' };
const NOW = new Date('2026-11-26T10:00:00.000Z');

function memoryStorage(): KeyValueStorage & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    getItem: (k) => data.get(k) ?? null,
    setItem: (k, v) => void data.set(k, v),
    removeItem: (k) => void data.delete(k),
  };
}

function entryAt(i: number): FailureEntry {
  return buildEntry({ kind: 'error', op: `op${i}`, error: new Error('x') }, context, new Date(NOW.getTime() + i));
}

describe('buildEntry', () => {
  it('records operation, error name and code, time and context', () => {
    const err = Object.assign(new Error("EACCES: permission denied, open '/home/u/qukis/a.md'"), { code: 'EACCES' });
    const entry = buildEntry({ kind: 'storage', op: 'writeTextAtomic', error: err }, context, NOW);
    expect(entry).toMatchObject({
      t: '2026-11-26T10:00:00.000Z',
      kind: 'storage',
      op: 'writeTextAtomic',
      name: 'Error',
      code: 'EACCES',
      version: '1.2.3',
      platform: 'web',
      backend: 'opfs',
      process: 'renderer',
    });
  });

  it('takes a code from the message when the error carries none (errors that crossed IPC)', () => {
    const err = new Error("Error invoking remote method 'quki:rename': Error: ENOSPC: no space left on device, rename 'a' -> 'b'");
    expect(buildEntry({ kind: 'storage', op: 'rename', error: err }, context, NOW).code).toBe('ENOSPC');
  });

  it('keeps a DOMException name such as QuotaExceededError', () => {
    const err = Object.assign(new Error('The quota has been exceeded.'), { name: 'QuotaExceededError' });
    expect(buildEntry({ kind: 'save', op: 'save', error: err }, context, NOW).name).toBe('QuotaExceededError');
  });

  it('marks the conflict path and a forced overwrite', () => {
    const entry = buildEntry({ kind: 'conflict', op: 'save', conflict: 'modified', forced: true }, context, NOW);
    expect(entry.conflict).toBe('modified');
    expect(entry.forced).toBe(true);
  });

  it('replaces an op that is not a plain word', () => {
    expect(buildEntry({ kind: 'error', op: `open ${SENTINEL_FILE}.md`, error: null }, context, NOW).op).toBe('unknown');
  });

  it('never carries QuKi text or a QuKi filename, whatever the error says', () => {
    const hostile = [
      new Error(`EACCES: permission denied, open 'C:\\Users\\me\\qukis\\${SENTINEL_FILE}.md'`),
      new Error(`ENOENT: no such file or directory, rename '/data/${SENTINEL_FILE}.md' -> '/data/.trash/${SENTINEL_FILE}.md'`),
      new Error(`EACCES: permission denied, open /home/me/My Notes/${SENTINEL_FILE} private.md`),
      new Error(`Unexpected token in JSON at "${SENTINEL_TEXT} more text"`),
      new TypeError(`${SENTINEL_TEXT} is not a function`),
      new Error(`EACCES: permission denied, ${SENTINEL_TEXT}`),
      new Error(`failed to write ${SENTINEL_FILE}.md`),
      new Error(`could not read media/${SENTINEL_FILE}.png`),
      new Error(`bad id 3f2504e0-4f89-11d3-9a0c-0305e82c3301`),
      Object.assign(new Error(`write failed: ${SENTINEL_FILE}.md`), { name: `Weird ${SENTINEL_FILE}`, code: `x ${SENTINEL_FILE}` }),
      `string error with 'quoted ${SENTINEL_TEXT}' and "${SENTINEL_FILE}.md"`,
      { message: `file:///tmp/${SENTINEL_FILE}.md` },
    ];
    for (const error of hostile) {
      const text = JSON.stringify(buildEntry({ kind: 'storage', op: 'writeTextAtomic', error }, context, NOW));
      expect(text).not.toContain(SENTINEL_TEXT);
      expect(text).not.toContain(SENTINEL_FILE);
      expect(text).not.toContain('3f2504e0');
      expect(text).not.toMatch(/Users|\/home|\/data|\.md/);
    }
  });
});

describe('messages of save and storage errors', () => {
  it('keeps only system text, so text in an app-written message cannot ride along', () => {
    const err = new Error(`ENOSPC: no space left on device, write while saving ${SENTINEL_TEXT} to ${SENTINEL_FILE}.md`);
    expect(buildEntry({ kind: 'save', op: 'save', error: err }, context, NOW).message).toBe('ENOSPC: no space left on device, write');
    const appWritten = buildEntry({ kind: 'storage', op: 'readText', error: new Error(`Could not parse ${SENTINEL_TEXT}`) }, context, NOW);
    expect(appWritten.message).toBeUndefined();
    const quota = Object.assign(new Error('The quota has been exceeded.'), { name: 'QuotaExceededError' });
    expect(buildEntry({ kind: 'save', op: 'save', error: quota }, context, NOW).message).toBe('The quota has been exceeded.');
  });

  it('keeps the engine stock messages but not an app-written message with the same error name', () => {
    const msg = (kind: 'uncaught' | 'error', error: unknown) => buildEntry({ kind, op: 'x', error }, context, NOW).message;
    expect(msg('uncaught', new TypeError('foo.bar is not a function'))).toBe('foo.bar is not a function');
    expect(msg('uncaught', new TypeError("Cannot read properties of undefined (reading 'secret text')"))).toBe('Cannot read properties of undefined');
    expect(msg('uncaught', new TypeError(`${SENTINEL_TEXT} is not a function`))).toBeUndefined();
    expect(msg('uncaught', new TypeError(`bad value ${SENTINEL_TEXT}`))).toBeUndefined();
    expect(msg('error', new Error('x is not a function'))).toBeUndefined();
    expect(msg('uncaught', new RangeError('Maximum call stack size exceeded'))).toBe('Maximum call stack size exceeded');
  });

  it('keeps a crash reason and not an errno-looking word out of ordinary text', () => {
    expect(buildEntry({ kind: 'crash', op: 'render-process-gone', error: new Error('oom') }, context, NOW).message).toBe('oom');
    const text = buildEntry({ kind: 'error', op: 'x', error: new Error('EXAMPLE: my private words') }, context, NOW);
    expect(text.message).toBeUndefined();
    expect(text.code).toBeUndefined();
  });
});

describe('sanitizeEntry', () => {
  it('drops unknown fields and redacts a message that was stored raw', () => {
    const raw = { ...entryAt(0), extra: SENTINEL_TEXT, message: `open /tmp/${SENTINEL_FILE}.md ${SENTINEL_TEXT}` };
    const clean = sanitizeEntry(raw)!;
    expect(JSON.stringify(clean)).not.toContain(SENTINEL_TEXT);
    expect(JSON.stringify(clean)).not.toContain(SENTINEL_FILE);
    expect(clean).not.toHaveProperty('extra');
  });

  it('rejects things that are not entries', () => {
    expect(sanitizeEntry(null)).toBeNull();
    expect(sanitizeEntry({ t: 'nope', kind: 'save' })).toBeNull();
    expect(sanitizeEntry({ t: NOW.toISOString(), kind: 'made-up' })).toBeNull();
  });
});

describe('appendCapped', () => {
  it('drops the oldest entries past the entry cap', () => {
    let entries: FailureEntry[] = [];
    for (let i = 0; i < 10; i++) entries = appendCapped(entries, entryAt(i), { maxEntries: 4, maxBytes: 1e9 });
    expect(entries.map((e) => e.op)).toEqual(['op6', 'op7', 'op8', 'op9']);
  });

  it('drops the oldest entries past the size cap and keeps the newest', () => {
    let entries: FailureEntry[] = [];
    for (let i = 0; i < 50; i++) entries = appendCapped(entries, entryAt(i), { maxEntries: 1000, maxBytes: 2000 });
    expect(JSON.stringify(entries).length).toBeLessThanOrEqual(2000);
    expect(entries.at(-1)!.op).toBe('op49');
    expect(entries.length).toBeLessThan(50);
  });
});

describe('createKeyValueFailureLog', () => {
  it('appends, reads and clears', async () => {
    const log = createKeyValueFailureLog(memoryStorage(), 'k');
    await log.append(entryAt(1));
    await log.append(entryAt(2));
    expect((await log.read()).map((e) => e.op)).toEqual(['op1', 'op2']);
    await log.clear();
    expect(await log.read()).toEqual([]);
  });

  it('treats a corrupt stored value as an empty log', () => {
    expect(parseStoredLog('{not json')).toEqual([]);
    expect(parseStoredLog('{"a":1}')).toEqual([]);
    expect(parseStoredLog(null)).toEqual([]);
  });
});

describe('createFailureRecorder', () => {
  it('swallows a store that throws, and one that rejects', async () => {
    const throwing = createFailureRecorder(
      () => ({ append: () => { throw new Error('quota'); }, read: async () => [], clear: async () => {} }),
      context,
    );
    const rejecting = createFailureRecorder(
      () => ({ append: () => Promise.reject(new Error('nope')), read: async () => [], clear: async () => {} }),
      context,
    );
    expect(() => throwing.record({ kind: 'error', op: 'x' })).not.toThrow();
    expect(() => rejecting.record({ kind: 'error', op: 'x' })).not.toThrow();
    await new Promise((r) => setTimeout(r, 0));
  });

  it('does nothing without a store, and uses context updates', async () => {
    expect(() => createFailureRecorder(() => null, context).record({ kind: 'error', op: 'x' })).not.toThrow();
    const log = createKeyValueFailureLog(memoryStorage(), 'k');
    const recorder = createFailureRecorder(() => log, context, () => NOW);
    recorder.setContext({ backend: 'capacitor-fs' });
    recorder.record({ kind: 'error', op: 'x' });
    expect((await log.read())[0]!.backend).toBe('capacitor-fs');
  });
});

describe('repeated failures', () => {
  it('writes an unchanged repeat once a minute, and a different failure at once', async () => {
    const log = createKeyValueFailureLog(memoryStorage(), 'k');
    let clock = NOW.getTime();
    const recorder = createFailureRecorder(() => log, context, () => new Date(clock));
    const fail = { kind: 'save' as const, op: 'save', error: new Error('EACCES: denied') };
    recorder.record(fail);
    clock += 2_000;
    recorder.record(fail);
    clock += 2_000;
    recorder.record({ kind: 'conflict', op: 'save', conflict: 'modified' });
    clock += 61_000;
    recorder.record({ kind: 'conflict', op: 'save', conflict: 'modified' });
    expect((await log.read()).map((e) => e.kind)).toEqual(['save', 'conflict', 'conflict']);
  });
});

describe('formatLog', () => {
  it('says so when empty and prints one line per entry otherwise', () => {
    expect(formatLog([])).toBe('No failures recorded.');
    const text = formatLog([buildEntry({ kind: 'conflict', op: 'save', conflict: 'deleted' }, context, NOW)]);
    expect(text).toBe('2026-11-26T10:00:00.000Z [conflict] save conflict=deleted | v1.2.3 web opfs renderer');
  });
});

describe('withFailureLogging', () => {
  let dir: string;
  beforeEach(async () => {
    dir = await makeTempQuKiDir();
  });
  afterEach(async () => {
    await cleanupTempDir(dir);
  });

  it('records a failing operation by name and rethrows the same error', async () => {
    const seen: Array<[string, unknown]> = [];
    const backend = withFailureLogging(new NodeFsBackend(dir), (op, e) => seen.push([op, e]));
    await backend.writeTextAtomic('.meta', 'a file where a folder should be');
    await expect(backend.writeTextAtomic('.meta/x.json', '{}')).rejects.toThrow();
    expect(seen).toHaveLength(1);
    expect(seen[0]![0]).toBe('writeTextAtomic');
    const entry = buildEntry({ kind: 'storage', op: seen[0]![0], error: seen[0]![1] }, context, NOW);
    expect(entry.code).toMatch(/^E[A-Z]+$/);
  });

  it('does not record a missing file, and does nothing on success', async () => {
    const seen: string[] = [];
    const backend = withFailureLogging(new NodeFsBackend(dir), (op) => seen.push(op));
    await backend.writeTextAtomic('a.md', 'hi');
    expect(await backend.readText('a.md')).toBe('hi');
    await expect(backend.stat('missing.md')).rejects.toThrow();
    expect(seen).toEqual([]);
  });

  it('does not record NotFoundError', async () => {
    const seen: string[] = [];
    const inner = new NodeFsBackend(dir);
    inner.readText = async () => {
      throw new NotFoundError('x');
    };
    await expect(withFailureLogging(inner, (op) => seen.push(op)).readText('x.md')).rejects.toThrow(NotFoundError);
    expect(seen).toEqual([]);
  });

  it('keeps resolvePath synchronous', () => {
    const backend = withFailureLogging(new NodeFsBackend(dir), () => {});
    expect(typeof backend.resolvePath('media/a.png')).toBe('string');
  });
});
