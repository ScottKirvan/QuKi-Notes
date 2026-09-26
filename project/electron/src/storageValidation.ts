import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * Real functional check that a candidate storage root is safe to adopt: it
 * exists, is actually a directory (not a file, not missing), and is
 * genuinely writable. Shared by flutterMigration.ts (adopting a Flutter
 * install's recorded folder) and main.ts (re-validating this app's own
 * previously-chosen storagePath on every normal startup) - both need the
 * same guarantee: silently adopting a stale path (folder moved, deleted, on
 * a now-disconnected drive, permissions changed) would make a user believe
 * their existing QuKis are there when the app is about to treat an empty or
 * freshly-created folder as their whole library.
 *
 * A permissions-bit check (fs.accessSync with a mode flag) is trusted
 * blindly by the caller and can be wrong - notably on Windows, where a
 * directory's "read-only" attribute does not reliably predict whether
 * creating a file inside it will actually succeed. Performing the real
 * operation - create a uniquely-named marker file, then remove it - is the
 * only check that can't lie about what a subsequent real write would do.
 */
export function isValidWritableDirectory(dir: string): boolean {
  let stat: fs.Stats;
  try {
    stat = fs.statSync(dir);
  } catch {
    return false;
  }
  if (!stat.isDirectory()) return false;

  const probePath = path.join(
    dir,
    `.quki-storage-write-probe-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  );
  try {
    fs.writeFileSync(probePath, '');
  } catch {
    return false;
  }
  try {
    fs.unlinkSync(probePath);
  } catch {
    // The write already proved the directory is writable; a failed cleanup
    // doesn't undo that, though it does leave a stray marker file behind.
  }
  return true;
}
