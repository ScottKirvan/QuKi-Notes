import type { FileStat, StorageBackend } from './storageBackend.js';

// TypeScript's bundled lib.dom.d.ts does not yet include the async
// directory-iteration methods of the File System Access API, even though
// they are implemented and stable in Chromium (and are what this backend's
// listDir relies on).
declare global {
  interface FileSystemDirectoryHandle {
    keys(): AsyncIterableIterator<string>;
  }
}

function notFound(relPath: string): DOMException {
  return new DOMException(`OPFS entry not found: ${relPath}`, 'NotFoundError');
}

// getFileHandle/getDirectoryHandle reject with NotFoundError when nothing is
// there and TypeMismatchError when something is there but of the other kind
// (a file where a directory was requested, or vice versa) - both are routine
// outcomes callers below branch on deliberately. Any other rejection (quota,
// permissions, a genuinely broken OPFS) must propagate instead of collapsing
// into the same "not there" result, per STORAGE_CONTRACT.md.
function isExpectedLookupFailure(err: unknown): boolean {
  return err instanceof DOMException && (err.name === 'NotFoundError' || err.name === 'TypeMismatchError');
}

/**
 * StorageBackend backed by the browser's Origin Private File System.
 * `rootDirName` scopes all paths under a named subdirectory of the OPFS
 * root - analogous to NodeFsBackend's rootDir - so multiple backends (or
 * test runs) can share one origin without colliding. Pass '' to use the
 * OPFS root directly.
 *
 * OPFS has no rename/move primitive supported everywhere, so `rename` is
 * implemented as copy-then-delete rather than NodeFsBackend's single
 * fs.rename call - this is the one operation where OPFS's shape forces a
 * real deviation from the Node backend. Writes still get the atomicity
 * guarantee STORAGE_CONTRACT.md requires: a FileSystemWritableFileStream
 * writes to a swap file and only replaces the real one on close(), so a
 * concurrent reader can never observe a partially written file - the same
 * guarantee NodeFsBackend gets from its temp-file-plus-rename dance, just
 * provided natively by the platform instead of hand-rolled.
 */
export class OpfsBackend implements StorageBackend {
  private rootPromise: Promise<FileSystemDirectoryHandle> | null = null;

  constructor(private readonly rootDirName: string = '') {}

  private async getRoot(): Promise<FileSystemDirectoryHandle> {
    if (!this.rootPromise) {
      this.rootPromise = (async () => {
        const opfsRoot = await navigator.storage.getDirectory();
        if (this.rootDirName === '') return opfsRoot;
        return opfsRoot.getDirectoryHandle(this.rootDirName, { create: true });
      })();
    }
    return this.rootPromise;
  }

  private parseSegments(relPath: string): string[] {
    const rawParts = relPath.split('/').filter((p) => p !== '' && p !== '.');
    const stack: string[] = [];
    for (const part of rawParts) {
      if (part === '..') {
        if (stack.length === 0) {
          throw new Error(`Path escapes QuKi folder: ${relPath}`);
        }
        stack.pop();
      } else {
        stack.push(part);
      }
    }
    return stack;
  }

  resolvePath(relPath: string): string {
    return '/' + this.parseSegments(relPath).join('/');
  }

  private async getDirHandleForSegments(
    segments: string[],
    opts: { create: boolean },
  ): Promise<FileSystemDirectoryHandle> {
    let handle = await this.getRoot();
    for (const seg of segments) {
      try {
        handle = await handle.getDirectoryHandle(seg, { create: opts.create });
      } catch (err) {
        if (err instanceof DOMException && err.name === 'NotFoundError') throw notFound(seg);
        throw err;
      }
    }
    return handle;
  }

  private async getFileHandle(relPath: string, opts: { create: boolean }): Promise<FileSystemFileHandle> {
    const segments = this.parseSegments(relPath);
    if (segments.length === 0) throw new Error(`Not a file path: ${relPath}`);
    const dirSegments = segments.slice(0, -1);
    const fileName = segments[segments.length - 1]!;
    const dirHandle = await this.getDirHandleForSegments(dirSegments, opts);
    try {
      return await dirHandle.getFileHandle(fileName, { create: opts.create });
    } catch (err) {
      if (err instanceof DOMException && err.name === 'NotFoundError') throw notFound(relPath);
      throw err;
    }
  }

  async readText(relPath: string): Promise<string> {
    const handle = await this.getFileHandle(relPath, { create: false });
    const file = await handle.getFile();
    return file.text();
  }

  async writeTextAtomic(relPath: string, content: string): Promise<void> {
    const handle = await this.getFileHandle(relPath, { create: true });
    const writable = await handle.createWritable();
    await writable.write(content);
    await writable.close();
  }

  async readBinary(relPath: string): Promise<Uint8Array> {
    const handle = await this.getFileHandle(relPath, { create: false });
    const file = await handle.getFile();
    return new Uint8Array(await file.arrayBuffer());
  }

  async writeBinaryAtomic(relPath: string, content: Uint8Array): Promise<void> {
    const handle = await this.getFileHandle(relPath, { create: true });
    const writable = await handle.createWritable();
    await writable.write(new Uint8Array(content));
    await writable.close();
  }

  async remove(relPath: string): Promise<void> {
    const segments = this.parseSegments(relPath);
    if (segments.length === 0) return;
    const dirSegments = segments.slice(0, -1);
    const name = segments[segments.length - 1]!;
    try {
      const dirHandle = await this.getDirHandleForSegments(dirSegments, { create: false });
      await dirHandle.removeEntry(name);
    } catch (err) {
      if (err instanceof DOMException && err.name === 'NotFoundError') return;
      throw err;
    }
  }

  async rename(fromRelPath: string, toRelPath: string): Promise<void> {
    const sourceHandle = await this.getFileHandle(fromRelPath, { create: false });
    const file = await sourceHandle.getFile();
    const bytes = new Uint8Array(await file.arrayBuffer());

    const destHandle = await this.getFileHandle(toRelPath, { create: true });
    const writable = await destHandle.createWritable();
    await writable.write(bytes);
    await writable.close();

    await this.remove(fromRelPath);
  }

  async exists(relPath: string): Promise<boolean> {
    const segments = this.parseSegments(relPath);
    if (segments.length === 0) return true;
    try {
      await this.getFileHandle(relPath, { create: false });
      return true;
    } catch (err) {
      if (!isExpectedLookupFailure(err)) throw err;
      // Not there as a file, or there but as a directory - fall through and
      // check whether relPath names a directory instead.
    }
    try {
      await this.getDirHandleForSegments(segments, { create: false });
      return true;
    } catch (err) {
      if (isExpectedLookupFailure(err)) return false;
      throw err;
    }
  }

  async stat(relPath: string): Promise<FileStat> {
    const handle = await this.getFileHandle(relPath, { create: false });
    const file = await handle.getFile();
    return { size: file.size, mtimeMs: file.lastModified, birthtimeMs: 0 };
  }

  async listDir(relDir: string): Promise<string[]> {
    const segments = this.parseSegments(relDir);
    let dirHandle: FileSystemDirectoryHandle;
    try {
      dirHandle = await this.getDirHandleForSegments(segments, { create: false });
    } catch (err) {
      if (err instanceof DOMException && err.name === 'NotFoundError') return [];
      throw err;
    }
    const names: string[] = [];
    for await (const name of dirHandle.keys()) {
      names.push(name);
    }
    return names;
  }

  async mkdirp(relDir: string): Promise<void> {
    await this.getDirHandleForSegments(this.parseSegments(relDir), { create: true });
  }
}
