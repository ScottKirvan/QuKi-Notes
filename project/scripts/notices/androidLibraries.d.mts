import type { PackageNotice } from "./lib.mjs";
export const ANDROID_LIBRARY_NOTE: string;
export interface AndroidLibraryNotices {
  packages: PackageNotice[];
  notices: { name: string; version: string; text: string }[];
  notes: Record<string, string>;
}
export function readAndroidLibraries(listFile?: string, licenceDir?: string): AndroidLibraryNotices;
export function renderLibraryNotices(notices: AndroidLibraryNotices["notices"]): string;
