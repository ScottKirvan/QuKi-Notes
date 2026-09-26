export interface FileStat {
  size: number;
  mtimeMs: number;
  birthtimeMs: number;
}

/**
 * Everything the core needs from a filesystem. Paths passed in and out of
 * this interface are always relative to the backend's own root - callers
 * outside a backend never see or construct host absolute paths except via
 * resolvePath, which is also how the "always inside the QuKi folder"
 * guarantee is enforced in one place.
 *
 * Only a Node `fs` implementation exists today (NodeFsBackend). OPFS and
 * Capacitor backends are future work and must be able to implement this
 * same shape without the core changing.
 */
export interface StorageBackend {
  readText(relPath: string): Promise<string>;
  writeTextAtomic(relPath: string, content: string): Promise<void>;
  readBinary(relPath: string): Promise<Uint8Array>;
  writeBinaryAtomic(relPath: string, content: Uint8Array): Promise<void>;
  remove(relPath: string): Promise<void>;
  rename(fromRelPath: string, toRelPath: string): Promise<void>;
  exists(relPath: string): Promise<boolean>;
  stat(relPath: string): Promise<FileStat>;
  listDir(relDir: string): Promise<string[]>;
  mkdirp(relDir: string): Promise<void>;
  /** Resolves a relative path to an absolute host path, guaranteed inside the root. */
  resolvePath(relPath: string): string;
}
