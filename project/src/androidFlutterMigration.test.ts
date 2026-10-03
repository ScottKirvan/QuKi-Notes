import { describe, expect, it, vi } from "vitest";

import {
  folderHasMarkdownFile,
  readFlutterMigrationChoice,
  resolveMigratedStorageRoot,
  type AndroidFlutterMigrationDeps,
} from "./androidFlutterMigration.js";

const APP_DOCUMENTS_PATH = "/data/data/com.quki.quki_notes/app_flutter";
const APP_STORAGE_QUKIS_DIR = `${APP_DOCUMENTS_PATH}/qukis`;

function fakeDeps(overrides: {
  locationChosen?: boolean;
  basePath?: string | null;
  appDocumentsPath?: string;
  validPaths?: Set<string>;
  dirEntries?: Record<string, string[]>;
}): AndroidFlutterMigrationDeps {
  const validPaths = overrides.validPaths ?? new Set<string>();
  const dirEntries = overrides.dirEntries ?? {};

  return {
    getFlutterMigrationInfo: vi.fn(async () => ({
      locationChosen: overrides.locationChosen ?? false,
      basePath: overrides.basePath ?? null,
      appDocumentsPath: overrides.appDocumentsPath ?? APP_DOCUMENTS_PATH,
    })),
    isValidWritableDirectory: vi.fn(async (path: string) => validPaths.has(path)),
    listDir: vi.fn(async (path: string) => {
      if (!(path in dirEntries)) throw new Error(`ENOENT: ${path}`);
      return dirEntries[path]!;
    }),
  };
}

describe("folderHasMarkdownFile", () => {
  it("returns false when listDir rejects (folder does not exist)", async () => {
    const deps = fakeDeps({ dirEntries: {} });
    expect(await folderHasMarkdownFile(deps, "/nope")).toBe(false);
  });

  it("returns false for an empty folder", async () => {
    const deps = fakeDeps({ dirEntries: { "/dir": [] } });
    expect(await folderHasMarkdownFile(deps, "/dir")).toBe(false);
  });

  it("returns false when the folder has files but none are .md", async () => {
    const deps = fakeDeps({ dirEntries: { "/dir": ["image.png", "notes.txt"] } });
    expect(await folderHasMarkdownFile(deps, "/dir")).toBe(false);
  });

  it("returns true when the folder has at least one .md file", async () => {
    const deps = fakeDeps({ dirEntries: { "/dir": ["note.md"] } });
    expect(await folderHasMarkdownFile(deps, "/dir")).toBe(true);
  });

  it("is case-insensitive on the .md extension", async () => {
    const deps = fakeDeps({ dirEntries: { "/dir": ["NOTE.MD"] } });
    expect(await folderHasMarkdownFile(deps, "/dir")).toBe(true);
  });
});

describe("readFlutterMigrationChoice", () => {
  it("returns null when location_chosen is false", async () => {
    const deps = fakeDeps({ locationChosen: false, basePath: "/some/folder" });
    expect(await readFlutterMigrationChoice(deps)).toBeNull();
  });

  it("returns null when location_chosen is true but basePath is null", async () => {
    const deps = fakeDeps({ locationChosen: true, basePath: null });
    expect(await readFlutterMigrationChoice(deps)).toBeNull();
  });

  it("returns the chosen base path when location_chosen is true and basePath is set", async () => {
    const deps = fakeDeps({ locationChosen: true, basePath: "/chosen/folder" });
    expect(await readFlutterMigrationChoice(deps)).toEqual({ basePath: "/chosen/folder" });
  });
});

describe("resolveMigratedStorageRoot", () => {
  it("adopts the Flutter app-recorded chosen path (a filesystem folder the user picked) when it validates", async () => {
    const deps = fakeDeps({
      locationChosen: true,
      basePath: "/storage/emulated/0/Documents/QuKi_Notes",
      validPaths: new Set(["/storage/emulated/0/Documents/QuKi_Notes"]),
    });

    expect(await resolveMigratedStorageRoot(deps)).toBe("/storage/emulated/0/Documents/QuKi_Notes");
  });

  it("adopts the Flutter app-recorded chosen path when it points at the app's own private app-storage default", async () => {
    const deps = fakeDeps({
      locationChosen: true,
      basePath: APP_STORAGE_QUKIS_DIR,
      validPaths: new Set([APP_STORAGE_QUKIS_DIR]),
    });

    expect(await resolveMigratedStorageRoot(deps)).toBe(APP_STORAGE_QUKIS_DIR);
  });

  it("does not adopt a Flutter-recorded path that fails validation, and does not fall back to an empty app-storage folder either", async () => {
    const deps = fakeDeps({
      locationChosen: true,
      basePath: "/moved-or-deleted-folder",
      validPaths: new Set(), // nothing validates
      dirEntries: {}, // app-storage qukis dir doesn't exist / listDir rejects
    });

    expect(await resolveMigratedStorageRoot(deps)).toBeNull();
  });

  it("falls through to the app-storage fallback when the Flutter-recorded path fails validation but the fallback folder validates and has QuKis", async () => {
    const deps = fakeDeps({
      locationChosen: true,
      basePath: "/moved-or-deleted-folder",
      validPaths: new Set([APP_STORAGE_QUKIS_DIR]),
      dirEntries: { [APP_STORAGE_QUKIS_DIR]: ["existing.md"] },
    });

    expect(await resolveMigratedStorageRoot(deps)).toBe(APP_STORAGE_QUKIS_DIR);
  });

  it("does not adopt an app-storage fallback folder that has markdown files but fails the writability probe", async () => {
    const deps = fakeDeps({
      locationChosen: false,
      validPaths: new Set(), // app-storage dir fails the probe
      dirEntries: { [APP_STORAGE_QUKIS_DIR]: ["existing.md"] },
    });

    expect(await resolveMigratedStorageRoot(deps)).toBeNull();
  });

  it("falls back to the app-storage folder when no Flutter choice was recorded but it already has QuKis", async () => {
    const deps = fakeDeps({
      locationChosen: false,
      validPaths: new Set([APP_STORAGE_QUKIS_DIR]),
      dirEntries: { [APP_STORAGE_QUKIS_DIR]: ["existing.md"] },
    });

    expect(await resolveMigratedStorageRoot(deps)).toBe(APP_STORAGE_QUKIS_DIR);
  });

  it("prefers the Flutter-recorded choice over the app-storage fallback when both are present and both validate", async () => {
    const deps = fakeDeps({
      locationChosen: true,
      basePath: "/storage/emulated/0/Documents/QuKi_Notes",
      validPaths: new Set(["/storage/emulated/0/Documents/QuKi_Notes", APP_STORAGE_QUKIS_DIR]),
      dirEntries: { [APP_STORAGE_QUKIS_DIR]: ["existing.md"] },
    });

    expect(await resolveMigratedStorageRoot(deps)).toBe("/storage/emulated/0/Documents/QuKi_Notes");
  });

  it("returns null when neither a Flutter choice nor an existing app-storage folder is found", async () => {
    const deps = fakeDeps({ locationChosen: false, dirEntries: {} });

    expect(await resolveMigratedStorageRoot(deps)).toBeNull();
  });
});
