/**
 * The local failure log: what an unexpected error leaves behind so a failed
 * save can be diagnosed afterwards. Pure logic (entry shape, allowed messages,
 * capping, formatting) plus two small stateful helpers: a recorder that can
 * never throw, and a decorator that records a backend's failures. Nothing
 * here touches the network, and nothing here knows where the log is kept: a
 * store is handed in, and it lives outside the QuKi folder (never in `.quki/`
 * or the sidecar).
 *
 * An entry never carries QuKi text or a QuKi filename. It is rebuilt from a
 * fixed list of short fields, so nothing else can ride along, and the one
 * free-text field (the error message) is kept only when it is one of a few
 * system-written shapes (see allowedMessage).
 */
import type { StorageBackend } from './storageBackend.js';
import { NotFoundError } from './types.js';

export type FailureKind = 'save' | 'conflict' | 'storage' | 'error' | 'uncaught' | 'unhandled-rejection' | 'crash';

export const FAILURE_KINDS: readonly FailureKind[] = [
  'save',
  'conflict',
  'storage',
  'error',
  'uncaught',
  'unhandled-rejection',
  'crash',
];

export interface FailureContext {
  version: string;
  platform: string;
  backend: string;
  process: 'renderer' | 'main';
}

export interface FailureInput {
  kind: FailureKind;
  /** What was being attempted: `writeTextAtomic`, `rename`, `save`, ... A fixed word chosen in code, never data. */
  op: string;
  error?: unknown;
  /** The save-conflict path (STORAGE_CONTRACT.md rule 17): what the file did underneath the save. */
  conflict?: 'modified' | 'deleted';
  /** True when the save was the user's explicit Overwrite after a conflict. */
  forced?: boolean;
  /** Where an uncaught error came from: bundle file, line and column. */
  where?: string;
}

export interface FailureEntry extends FailureContext {
  t: string;
  kind: FailureKind;
  op: string;
  name?: string;
  code?: string;
  message?: string;
  conflict?: 'modified' | 'deleted';
  forced?: boolean;
  where?: string;
}

export const MAX_LOG_ENTRIES = 200;
export const MAX_LOG_BYTES = 64 * 1024;
const MAX_MESSAGE_LENGTH = 160;

const WORD = /^[A-Za-z0-9_.:-]{1,60}$/;
const CODE = /^[A-Z][A-Z0-9_]{1,39}$/;
const WHERE = /^[A-Za-z0-9_.-]{1,80}:\d{1,7}:\d{1,7}$/;

function errorMessage(error: unknown): string | undefined {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  if (typeof error === 'object' && error !== null && typeof (error as { message?: unknown }).message === 'string') {
    return (error as { message: string }).message;
  }
  return undefined;
}

function errorName(error: unknown): string | undefined {
  const name = typeof error === 'object' && error !== null ? (error as { name?: unknown }).name : undefined;
  if (typeof name === 'string' && WORD.test(name)) return name;
  if (error instanceof Error) return 'Error';
  return undefined;
}

const ERRNO_CODES = new Set([
  'EACCES', 'EPERM', 'ENOENT', 'EEXIST', 'ENOTDIR', 'EISDIR', 'ENOSPC', 'EMFILE', 'ENFILE', 'EROFS', 'EBUSY', 'ENOTEMPTY',
  'EIO', 'EXDEV', 'ENAMETOOLONG', 'ELOOP', 'ETIMEDOUT', 'EINVAL', 'EDQUOT', 'ESTALE', 'ENODEV', 'ENXIO', 'EAGAIN', 'EFBIG',
  'EOVERFLOW', 'ECANCELED', 'ENOMEM',
]);
const ERRNO_PHRASE = /(?:^|[^A-Za-z0-9_])(E[A-Z0-9]{2,12}): ([a-z][a-z ]{0,60}[a-z])(?:, ([a-z]{3,12})(?![A-Za-z0-9_]))?/;
const BROWSER_ERROR_NAMES = new Set([
  'QuotaExceededError',
  'NotAllowedError',
  'SecurityError',
  'InvalidStateError',
  'NoModificationAllowedError',
  'AbortError',
  'DataError',
  'UnknownError',
  'TypeMismatchError',
  'NotReadableError',
  'EncodingError',
]);
const ENGINE_NAMES = new Set(['TypeError', 'ReferenceError', 'RangeError']);
const IDENT = '[A-Za-z_$][A-Za-z0-9_$]{0,30}(?:\\.[A-Za-z_$][A-Za-z0-9_$]{0,30}){0,3}';
const ENGINE_TEMPLATES: Array<[RegExp, (m: RegExpExecArray) => string]> = [
  [/^Cannot (read|set) propert(?:y|ies) of (undefined|null)/, (m) => `Cannot ${m[1]} properties of ${m[2]}`],
  [new RegExp('^(' + IDENT + ') is not (a function|defined|iterable|a constructor|an object)$'), (m) => `${m[1]} is not ${m[2]}`],
  [/^Maximum call stack size exceeded/, () => 'Maximum call stack size exceeded'],
  [/^Invalid array length/, () => 'Invalid array length'],
];
const CRASH_REASON = /^[A-Za-z-]{1,30}(?: [A-Za-z-]{1,30})?$/;

/**
 * The only message text that ever reaches the log. A message the app or a
 * library wrote could carry anything, including QuKi text or a file name, so
 * it is dropped; what is kept is text a system wrote and whose few variable
 * parts are fixed words: an operating-system error ("EACCES: permission
 * denied, open"), a browser's own storage error (QuotaExceededError), one of
 * the JavaScript engine's stock messages ("x is not a function"), or the
 * reason a process gave for crashing. The name and code still say what went
 * wrong when the message is dropped.
 */
export function allowedMessage(kind: FailureKind, name: string | undefined, message: string | undefined): string | undefined {
  if (message === undefined) return undefined;
  const errno = ERRNO_PHRASE.exec(message);
  if (errno !== null && ERRNO_CODES.has(errno[1]!)) {
    return `${errno[1]}: ${errno[2]}${errno[3] === undefined ? '' : `, ${errno[3]}`}`;
  }
  if (name !== undefined && BROWSER_ERROR_NAMES.has(name) && /^[A-Za-z ,.']{1,120}$/.test(message)) return message;
  if (name !== undefined && ENGINE_NAMES.has(name)) {
    for (const [pattern, render] of ENGINE_TEMPLATES) {
      const m = pattern.exec(message);
      if (m !== null) return render(m);
    }
  }
  if (kind === 'crash' && CRASH_REASON.test(message)) return message;
  return undefined;
}

function errorCode(error: unknown, message: string | undefined): string | undefined {
  const code = typeof error === 'object' && error !== null ? (error as { code?: unknown }).code : undefined;
  if (typeof code === 'string' && CODE.test(code)) return code;
  const found = message === undefined ? null : ERRNO_PHRASE.exec(message);
  return found !== null && ERRNO_CODES.has(found[1]!) ? found[1] : undefined;
}

export function buildEntry(input: FailureInput, context: FailureContext, now: Date): FailureEntry {
  const message = errorMessage(input.error);
  const entry: FailureEntry = {
    t: now.toISOString(),
    kind: input.kind,
    op: WORD.test(input.op) ? input.op : 'unknown',
    ...context,
  };
  const name = errorName(input.error);
  const code = errorCode(input.error, message);
  const kept = allowedMessage(input.kind, name, message);
  if (name !== undefined) entry.name = name;
  if (code !== undefined) entry.code = code;
  if (kept !== undefined && kept !== '') entry.message = kept.slice(0, MAX_MESSAGE_LENGTH);
  if (input.conflict !== undefined) entry.conflict = input.conflict;
  if (input.forced === true) entry.forced = true;
  if (input.where !== undefined && WHERE.test(input.where)) entry.where = input.where;
  return entry;
}

function word(value: unknown, fallback: string): string {
  return typeof value === 'string' && WORD.test(value) ? value : fallback;
}

/**
 * Rebuilds an entry from untrusted data (a stored log, an IPC message) out
 * of the allowed fields only, keeping a message only if it is still allowed. Returns null for
 * anything that is not an entry.
 */
export function sanitizeEntry(raw: unknown): FailureEntry | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.t !== 'string' || Number.isNaN(Date.parse(r.t))) return null;
  if (!FAILURE_KINDS.includes(r.kind as FailureKind)) return null;
  const entry: FailureEntry = {
    t: new Date(r.t).toISOString(),
    kind: r.kind as FailureKind,
    op: word(r.op, 'unknown'),
    version: word(r.version, 'unknown'),
    platform: word(r.platform, 'unknown'),
    backend: word(r.backend, 'unknown'),
    process: r.process === 'main' ? 'main' : 'renderer',
  };
  if (typeof r.name === 'string' && WORD.test(r.name)) entry.name = r.name;
  if (typeof r.code === 'string' && CODE.test(r.code)) entry.code = r.code;
  const message = allowedMessage(entry.kind, entry.name, typeof r.message === 'string' ? r.message : undefined);
  if (message !== undefined && message !== '') entry.message = message.slice(0, MAX_MESSAGE_LENGTH);
  if (r.conflict === 'modified' || r.conflict === 'deleted') entry.conflict = r.conflict;
  if (r.forced === true) entry.forced = true;
  if (typeof r.where === 'string' && WHERE.test(r.where)) entry.where = r.where;
  return entry;
}

/** Adds an entry and drops the oldest until both caps hold. */
export function appendCapped(
  entries: readonly FailureEntry[],
  entry: FailureEntry,
  limits: { maxEntries: number; maxBytes: number } = { maxEntries: MAX_LOG_ENTRIES, maxBytes: MAX_LOG_BYTES },
): FailureEntry[] {
  const out = [...entries, entry];
  while (out.length > 1 && (out.length > limits.maxEntries || JSON.stringify(out).length > limits.maxBytes)) {
    out.shift();
  }
  return out;
}

export function parseStoredLog(text: string | null): FailureEntry[] {
  if (text === null) return [];
  try {
    const raw: unknown = JSON.parse(text);
    if (!Array.isArray(raw)) return [];
    return raw.map(sanitizeEntry).filter((e): e is FailureEntry => e !== null);
  } catch {
    return [];
  }
}

export function serializeLog(entries: readonly FailureEntry[]): string {
  return JSON.stringify(entries);
}

export function formatEntry(entry: FailureEntry): string {
  const parts = [entry.t, `[${entry.kind}]`, entry.op];
  if (entry.conflict !== undefined) parts.push(`conflict=${entry.conflict}`);
  if (entry.forced === true) parts.push('forced');
  if (entry.name !== undefined) parts.push(entry.name);
  if (entry.code !== undefined) parts.push(entry.code);
  if (entry.message !== undefined) parts.push(`"${entry.message}"`);
  if (entry.where !== undefined) parts.push(`at ${entry.where}`);
  parts.push(`| v${entry.version} ${entry.platform} ${entry.backend} ${entry.process}`);
  return parts.join(' ');
}

export function formatLog(entries: readonly FailureEntry[]): string {
  if (entries.length === 0) return 'No failures recorded.';
  return entries.map(formatEntry).join('\n');
}

/** Where entries are kept. Every implementation lives outside the QuKi folder. */
export interface FailureLogStore {
  append(entry: FailureEntry): void | Promise<void>;
  read(): Promise<FailureEntry[]>;
  clear(): Promise<void>;
}

export interface KeyValueStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

/** A log kept under one key of a key/value store (the browser's localStorage). */
export function createKeyValueFailureLog(storage: KeyValueStorage, key: string): FailureLogStore {
  return {
    append(entry) {
      storage.setItem(key, serializeLog(appendCapped(parseStoredLog(storage.getItem(key)), entry)));
    },
    async read() {
      return parseStoredLog(storage.getItem(key));
    },
    async clear() {
      storage.removeItem(key);
    },
  };
}

export interface FailureRecorder {
  record(input: FailureInput): void;
  setContext(patch: Partial<FailureContext>): void;
}

export const REPEAT_WINDOW_MS = 60_000;

function repeatKey(e: FailureEntry): string {
  return [e.kind, e.op, e.name, e.code, e.message, e.conflict, e.forced, e.where].join('|');
}

/**
 * Recording never throws and never waits: a store that fails (or rejects) is
 * ignored, because the log must not be able to break or slow the app. A
 * failure that repeats unchanged (a save retried every few seconds against
 * the same broken folder) is written once a minute, not on every retry, so
 * it cannot push everything else out of the capped log.
 */
export function createFailureRecorder(
  getStore: () => FailureLogStore | null,
  context: FailureContext,
  now: () => Date = () => new Date(),
): FailureRecorder {
  const current = { ...context };
  const lastSeen = new Map<string, number>();
  return {
    record(input) {
      try {
        const store = getStore();
        if (store === null) return;
        const at = now();
        const entry = buildEntry(input, current, at);
        const key = repeatKey(entry);
        const before = lastSeen.get(key);
        if (before !== undefined && at.getTime() - before < REPEAT_WINDOW_MS) return;
        lastSeen.set(key, at.getTime());
        if (lastSeen.size > 100) lastSeen.delete(lastSeen.keys().next().value as string);
        const result = store.append(entry);
        if (result instanceof Promise) result.catch(() => {});
      } catch {
        // the log must never break the app
      }
    },
    setContext(patch) {
      Object.assign(current, patch);
    },
  };
}

function isExpectedAbsence(error: unknown): boolean {
  if (error instanceof NotFoundError) return true;
  if (typeof error !== 'object' || error === null) return false;
  const e = error as { name?: unknown; code?: unknown; message?: unknown };
  if (e.name === 'NotFoundError') return true;
  if (e.code === 'ENOENT') return true;
  return typeof e.message === 'string' && /ENOENT|does not exist|no such file/i.test(e.message);
}

const LOGGED_METHODS = [
  'readText',
  'writeTextAtomic',
  'readBinary',
  'writeBinaryAtomic',
  'remove',
  'rename',
  'exists',
  'stat',
  'listDir',
  'mkdirp',
] as const;

/**
 * Wraps a backend so a failed read, write, rename, stat, listing or removal
 * is recorded with the operation's name and the error's name and code. A
 * missing file is not a failure (QuKiStore treats it as an answer), so it is
 * not recorded. The error is always rethrown unchanged, and a call that
 * succeeds does nothing extra.
 */
export function withFailureLogging(backend: StorageBackend, report: (op: string, error: unknown) => void): StorageBackend {
  const wrapped = { resolvePath: (relPath: string) => backend.resolvePath(relPath) } as StorageBackend;
  for (const method of LOGGED_METHODS) {
    (wrapped as unknown as Record<string, unknown>)[method] = async (...args: unknown[]) => {
      try {
        return await (backend[method] as (...a: unknown[]) => Promise<unknown>).apply(backend, args);
      } catch (error) {
        if (!isExpectedAbsence(error)) {
          try {
            report(method, error);
          } catch {
            // never let the log change what the caller sees
          }
        }
        throw error;
      }
    };
  }
  return wrapped;
}
