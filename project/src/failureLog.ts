/**
 * The app's side of the local failure log (the pure logic is quki-core's
 * failureLog.ts). Failures are recorded on the device only and never sent
 * anywhere. Where the log is kept depends on the platform, always outside the
 * QuKi folder:
 *  - web and Android: this origin's localStorage (the browser's or the
 *    WebView's own app-private storage);
 *  - Electron: a file in the app's userData folder, written by the main
 *    process over IPC (the renderer's origin changes every launch, so its
 *    localStorage would not survive).
 *
 * Recording does nothing until something fails, and can never throw.
 */
import {
  createFailureRecorder,
  createKeyValueFailureLog,
  formatLog,
  parseStoredLog,
  type FailureEntry,
  type FailureInput,
  type FailureLogStore,
  type FailureRecorder,
} from "quki-core";

export const FAILURE_LOG_KEY = "quki.failureLog";

export interface ElectronFailureLogApi {
  append(entry: FailureEntry): void;
  read(): Promise<unknown[]>;
  clear(): Promise<void>;
}

declare global {
  interface Window {
    /** Present only inside the Electron wrapper (see preload.ts). */
    electronFailureLogAPI?: ElectronFailureLogApi;
  }
}

export interface FailureLogView {
  /** The whole log as text, oldest first. */
  readText(): Promise<string>;
  clear(): Promise<void>;
}

let store: FailureLogStore | null = null;
let recorder: FailureRecorder | null = null;

export function electronFailureLogStore(api: ElectronFailureLogApi): FailureLogStore {
  return {
    append: (entry) => api.append(entry),
    read: async () => {
      return parseStoredLog(JSON.stringify(await api.read()));
    },
    clear: () => api.clear(),
  };
}

export function initFailureLog(options: { version: string; platform: string; backend: string; store: FailureLogStore }): void {
  store = options.store;
  recorder = createFailureRecorder(() => store, {
    version: options.version,
    platform: options.platform,
    backend: options.backend,
    process: "renderer",
  });
}

export function localStorageFailureLog(storage: Storage): FailureLogStore {
  return createKeyValueFailureLog(storage, FAILURE_LOG_KEY);
}

export function recordFailureInput(input: FailureInput): void {
  recorder?.record(input);
}

/** An unexpected error that was caught and handled (a toast, a banner, a skipped item). */
export function recordFailure(op: string, error: unknown): void {
  recordFailureInput({ kind: "error", op, error });
}

/** A storage operation that threw (the backend decorator calls this). */
export function recordStorageFailure(op: string, error: unknown): void {
  recordFailureInput({ kind: "storage", op, error });
}

/** An auto-save or overwrite that threw instead of returning a result. */
export function recordSaveFailure(op: "save" | "overwrite", error: unknown): void {
  recordFailureInput({ kind: "save", op, error, forced: op === "overwrite" ? true : undefined });
}

/** STORAGE_CONTRACT.md rule 17: the file changed or vanished underneath a save. */
export function recordSaveConflict(reason: "modified" | "deleted"): void {
  recordFailureInput({ kind: "conflict", op: "save", conflict: reason });
}

export function getFailureLogView(): FailureLogView | null {
  const current = store;
  if (current === null) return null;
  return {
    readText: async () => formatLog(await current.read()),
    clear: () => current.clear(),
  };
}

const BENIGN_ERROR_MESSAGES = ["ResizeObserver loop"];

/** "assets/index-abc.js:1:2345" -> "index-abc.js:1:2345" (the bundle's own file, never a user path). */
export function whereOf(filename: unknown, line: unknown, column: unknown): string | undefined {
  if (typeof filename !== "string" || typeof line !== "number" || typeof column !== "number") return undefined;
  const base = filename.split(/[\\/]/).pop() ?? "";
  return `${base}:${line}:${column}`;
}

/** Records uncaught exceptions and unhandled promise rejections. Add once, at startup. */
export function installGlobalFailureHandlers(target: Pick<Window, "addEventListener">): void {
  target.addEventListener("error", (event) => {
    const e = event as ErrorEvent;
    if (BENIGN_ERROR_MESSAGES.some((m) => e.message?.includes(m))) return;
    recordFailureInput({
      kind: "uncaught",
      op: "window-error",
      error: e.error ?? e.message,
      where: whereOf(e.filename, e.lineno, e.colno),
    });
  });
  target.addEventListener("unhandledrejection", (event) => {
    recordFailureInput({ kind: "unhandled-rejection", op: "promise", error: (event as PromiseRejectionEvent).reason });
  });
}

export function setFailureLogBackend(backend: string): void {
  recorder?.setContext({ backend });
}
