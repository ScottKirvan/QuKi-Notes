import { randomUUID } from 'node:crypto';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';

import type { FileStat, StorageBackend } from './storageBackend.js';

export class NodeFsBackend implements StorageBackend {
  private readonly root: string;

  constructor(rootDir: string) {
    this.root = path.resolve(rootDir);
  }

  resolvePath(relPath: string): string {
    const resolved = path.resolve(this.root, relPath);
    const rootWithSep = this.root.endsWith(path.sep) ? this.root : this.root + path.sep;
    if (resolved !== this.root && !resolved.startsWith(rootWithSep)) {
      throw new Error(`Path escapes QuKi folder: ${relPath}`);
    }
    return resolved;
  }

  async readText(relPath: string): Promise<string> {
    return fs.readFile(this.resolvePath(relPath), 'utf8');
  }

  async writeTextAtomic(relPath: string, content: string): Promise<void> {
    const dest = this.resolvePath(relPath);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    const tmp = `${dest}.${randomUUID()}.tmp`;
    await fs.writeFile(tmp, content, 'utf8');
    await fs.rename(tmp, dest);
  }

  async readBinary(relPath: string): Promise<Uint8Array> {
    return fs.readFile(this.resolvePath(relPath));
  }

  async writeBinaryAtomic(relPath: string, content: Uint8Array): Promise<void> {
    const dest = this.resolvePath(relPath);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    const tmp = `${dest}.${randomUUID()}.tmp`;
    await fs.writeFile(tmp, content);
    await fs.rename(tmp, dest);
  }

  async remove(relPath: string): Promise<void> {
    try {
      await fs.unlink(this.resolvePath(relPath));
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT') throw err;
    }
  }

  async rename(fromRelPath: string, toRelPath: string): Promise<void> {
    const dest = this.resolvePath(toRelPath);
    await fs.mkdir(path.dirname(dest), { recursive: true });
    await fs.rename(this.resolvePath(fromRelPath), dest);
  }

  async exists(relPath: string): Promise<boolean> {
    try {
      await fs.access(this.resolvePath(relPath));
      return true;
    } catch {
      return false;
    }
  }

  async stat(relPath: string): Promise<FileStat> {
    const s = await fs.stat(this.resolvePath(relPath));
    return { size: s.size, mtimeMs: s.mtimeMs, birthtimeMs: s.birthtimeMs };
  }

  async listDir(relDir: string): Promise<string[]> {
    try {
      return await fs.readdir(this.resolvePath(relDir));
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return [];
      throw err;
    }
  }

  async mkdirp(relDir: string): Promise<void> {
    await fs.mkdir(this.resolvePath(relDir), { recursive: true });
  }
}
