export const NOTICES_FILE_NAME: string;
export interface PackageNotice {
  name: string;
  version: string;
  licence: string;
  private: boolean;
  files: string[];
  text: string;
}
export interface Notices {
  packages: PackageNotice[];
  missing: PackageNotice[];
  notes: Record<string, string>;
}
export function packageDirOfModule(id: string): string | null;
export function productionClosure(rootDir: string): string[];
export function resolvePackageDir(fromDir: string, name: string): string | null;
export function readPackageNotice(dir: string): PackageNotice;
export function collectNotices(packageDirs: string[], notes?: Record<string, string>): Notices;
export function renderNotices(notices: Notices, heading: string): string;
export function assertNoMissing(missing: PackageNotice[]): void;
export function packageDirsFromMetafile(metafile: { inputs: Record<string, unknown> }, baseDir: string): string[];
