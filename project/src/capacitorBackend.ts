import { registerPlugin } from "@capacitor/core";
import type { FileStat, StorageBackend } from "quki-core";

/**
 * The native surface of the custom Capacitor "Storage" plugin
 * (project/android/app/src/main/java/com/quki/quki_notes/StoragePlugin.kt).
 * Every file-I/O method here takes an already-resolved absolute Android
 * path - path joining and the "stays inside the QuKi folder" containment
 * check both happen in CapacitorFsBackend.resolvePath below, entirely in
 * TypeScript, not on the native side. That mirrors NodeFsBackend
 * (core/src/nodeFsBackend.ts), which does the same thing with node:path,
 * and keeps the plugin itself a thin, easily-verified file I/O surface.
 *
 * Binary content crosses the Capacitor bridge as base64 text (Capacitor
 * plugin calls are JSON-serialized; there is no raw-bytes channel), unlike
 * ElectronIpcBackend's IPC, which can pass a Uint8Array through untouched.
 */
export interface CapacitorStoragePlugin {
  readText(options: { path: string }): Promise<{ content: string }>;
  writeTextAtomic(options: { path: string; content: string }): Promise<void>;
  readBinary(options: { path: string }): Promise<{ data: string }>;
  writeBinaryAtomic(options: { path: string; data: string }): Promise<void>;
  remove(options: { path: string }): Promise<void>;
  rename(options: { from: string; to: string }): Promise<void>;
  exists(options: { path: string }): Promise<{ exists: boolean }>;
  stat(options: { path: string }): Promise<{ size: number; mtimeMs: number; birthtimeMs: number }>;
  listDir(options: { path: string }): Promise<{ entries: string[] }>;
  mkdirp(options: { path: string }): Promise<void>;
  /** Android 11+ (API 30+) all-files access; always granted below that - ported from the Flutter plugin, not yet wired to any UI (a later chunk's onboarding flow). */
  isExternalStorageManager(): Promise<{ granted: boolean }>;
  /** `<external Documents>/QuKi_Notes` - this chunk's fixed temporary storage root; see main.ts. */
  getExternalDocumentsPath(): Promise<{ path: string }>;
  /** Opens the system all-files-access settings screen; not yet wired to any UI. */
  requestAllFilesAccess(): Promise<void>;
  /**
   * Reads the Flutter app's real shared_preferences ("FlutterSharedPreferences",
   * via Context.getSharedPreferences - see StoragePlugin.kt) and resolves the
   * real path its getApplicationDocumentsDirectory() default maps to on this
   * device, for androidFlutterMigration.ts.
   */
  getFlutterMigrationInfo(): Promise<{ locationChosen: boolean; basePath: string | null; appDocumentsPath: string }>;
  /** Real write-probe validation of a candidate migrated storage root - see storageValidation.ts's isValidWritableDirectory for the desktop equivalent this mirrors. */
  isValidWritableDirectory(options: { path: string }): Promise<{ valid: boolean }>;
  /**
   * `context.filesDir.absolutePath` - bare, unsuffixed. androidSetupApi.ts
   * composes "/QuKi_Notes" (app storage) or "/quki_settings.json" (the
   * storage-choice settings file) on top of this; the plugin itself does no
   * path joining, matching this file's own path-joining-stays-in-TypeScript
   * philosophy.
   */
  getPrivateStoragePath(): Promise<{ path: string }>;
}

/**
 * registerPlugin resolves against whatever native plugin is registered
 * under this name at runtime (MainActivity.registerPlugin(StoragePlugin::class.java)
 * on Android); it is safe to call outside a Capacitor native context; the
 * proxy it returns is only ever actually invoked when main.ts has already
 * confirmed Capacitor.isNativePlatform().
 */
export const CapacitorStorage = registerPlugin<CapacitorStoragePlugin>("Storage");

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]!);
  return btoa(binary);
}

/**
 * Joins an already-known-absolute Android root with a StorageBackend
 * relative path and normalizes `.`/`..` segments, entirely as string
 * manipulation - there is no `node:path` inside a WebView. Mirrors
 * NodeFsBackend.resolvePath's use of path.resolve(root, relPath) precisely
 * enough that the same escape check (does the result still start with the
 * root?) catches the same cases.
 */
function posixResolve(root: string, relPath: string): string {
  const segments = `${root}/${relPath}`.split("/");
  const resolved: string[] = [];
  for (const segment of segments) {
    if (segment === "" || segment === ".") continue;
    if (segment === "..") {
      resolved.pop();
      continue;
    }
    resolved.push(segment);
  }
  return `/${resolved.join("/")}`;
}

function normalizeRoot(rootDir: string): string {
  return rootDir.length > 1 && rootDir.endsWith("/") ? rootDir.slice(0, -1) : rootDir;
}

export class CapacitorFsBackend implements StorageBackend {
  private root: string;

  constructor(
    private readonly plugin: CapacitorStoragePlugin,
    rootDir: string,
  ) {
    this.root = normalizeRoot(rootDir);
  }

  /**
   * Mutates the live root in place rather than requiring callers to
   * construct a new backend/store - Settings -> Change location on Android
   * has no separate main process to hold the "real" root the way Electron
   * does (electron/src/main.ts's setBackendRoot), so this object instance is
   * the only place that state lives. CapacitorFsBackend-only: StorageBackend
   * (quki-core) stays unchanged, since no other platform's backend needs
   * this.
   */
  setRoot(newRoot: string): void {
    this.root = normalizeRoot(newRoot);
  }

  resolvePath(relPath: string): string {
    const resolved = posixResolve(this.root, relPath);
    const rootWithSep = this.root.endsWith("/") ? this.root : `${this.root}/`;
    if (resolved !== this.root && !resolved.startsWith(rootWithSep)) {
      throw new Error(`Path escapes QuKi folder: ${relPath}`);
    }
    return resolved;
  }

  async readText(relPath: string): Promise<string> {
    const { content } = await this.plugin.readText({ path: this.resolvePath(relPath) });
    return content;
  }

  async writeTextAtomic(relPath: string, content: string): Promise<void> {
    await this.plugin.writeTextAtomic({ path: this.resolvePath(relPath), content });
  }

  async readBinary(relPath: string): Promise<Uint8Array> {
    const { data } = await this.plugin.readBinary({ path: this.resolvePath(relPath) });
    return base64ToBytes(data);
  }

  async writeBinaryAtomic(relPath: string, content: Uint8Array): Promise<void> {
    await this.plugin.writeBinaryAtomic({ path: this.resolvePath(relPath), data: bytesToBase64(content) });
  }

  async remove(relPath: string): Promise<void> {
    await this.plugin.remove({ path: this.resolvePath(relPath) });
  }

  async rename(fromRelPath: string, toRelPath: string): Promise<void> {
    await this.plugin.rename({ from: this.resolvePath(fromRelPath), to: this.resolvePath(toRelPath) });
  }

  async exists(relPath: string): Promise<boolean> {
    const { exists } = await this.plugin.exists({ path: this.resolvePath(relPath) });
    return exists;
  }

  async stat(relPath: string): Promise<FileStat> {
    const s = await this.plugin.stat({ path: this.resolvePath(relPath) });
    return { size: s.size, mtimeMs: s.mtimeMs, birthtimeMs: s.birthtimeMs };
  }

  async listDir(relDir: string): Promise<string[]> {
    const { entries } = await this.plugin.listDir({ path: this.resolvePath(relDir) });
    return entries;
  }

  async mkdirp(relDir: string): Promise<void> {
    await this.plugin.mkdirp({ path: this.resolvePath(relDir) });
  }
}
