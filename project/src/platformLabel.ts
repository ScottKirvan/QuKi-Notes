/** "Windows 10.0.28120", "macOS 24.1.0", "Linux 6.8.0". */
export function osLabel(platform: string, release: string): string {
  const name = platform === "win32" ? "Windows" : platform === "darwin" ? "macOS" : platform === "linux" ? "Linux" : platform;
  return release ? `${name} ${release}` : name;
}

/**
 * The operating system named by a browser user-agent string, for bug reports.
 * Only Android's version is reliable there (Windows and macOS freeze theirs),
 * so the others are named without one. Empty when nothing is recognised.
 */
export function osLabelFromUserAgent(userAgent: string): string {
  const android = /Android (\d+(?:\.\d+)*)/.exec(userAgent);
  if (android) return osLabel("Android", android[1]!);
  if (/iPhone|iPad|iPod/.test(userAgent)) return osLabel("iOS", "");
  if (/Windows/.test(userAgent)) return osLabel("win32", "");
  if (/Macintosh|Mac OS X/.test(userAgent)) return osLabel("darwin", "");
  if (/CrOS/.test(userAgent)) return osLabel("ChromeOS", "");
  if (/Linux|X11/.test(userAgent)) return osLabel("linux", "");
  return "";
}
