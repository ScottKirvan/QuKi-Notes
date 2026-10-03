function pad(n: number): string {
  return String(n).padStart(2, "0");
}

/**
 * The suggested filename for a Settings -> Export archive - a browser
 * download's default name, an Electron Save As dialog's default path, and
 * the relative path CapacitorFsBackend writes into on Android. Timestamped
 * (not a fixed name) so exporting more than once doesn't silently overwrite
 * a previous export - on Android in particular, where there is no save
 * dialog to ask the person first.
 *
 * Local time, not UTC: this names a file the person will see in their own
 * file browser, not a machine-readable log entry.
 */
export function buildExportFileName(now: Date = new Date()): string {
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  return `quki-export-${stamp}.tar.gz`;
}
