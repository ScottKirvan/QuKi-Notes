import { describe, expect, it, vi } from "vitest";

import { decideAndroidStorageSetup, type AndroidSetupDecisionDeps } from "./androidSetupDecision.js";

function fakeDeps(overrides: {
  storagePath?: string | null;
  storageChosen?: boolean;
  validPaths?: Set<string>;
  migratedPath?: string | null;
}): AndroidSetupDecisionDeps & { writeSettings: ReturnType<typeof vi.fn> } {
  const validPaths = overrides.validPaths ?? new Set<string>();
  return {
    readSettings: vi.fn(async () => ({
      storagePath: overrides.storagePath ?? null,
      storageChosen: overrides.storageChosen ?? false,
    })),
    writeSettings: vi.fn(async () => undefined),
    isValidWritableDirectory: vi.fn(async (path: string) => validPaths.has(path)),
    resolveMigratedStorageRoot: vi.fn(async () => overrides.migratedPath ?? null),
  };
}

describe("decideAndroidStorageSetup", () => {
  it("uses the settings-file path directly when it is present and still valid", async () => {
    const deps = fakeDeps({
      storageChosen: true,
      storagePath: "/storage/emulated/0/Documents/QuKi_Notes",
      validPaths: new Set(["/storage/emulated/0/Documents/QuKi_Notes"]),
    });

    const outcome = await decideAndroidStorageSetup(deps);

    expect(outcome).toEqual({ kind: "use-path", path: "/storage/emulated/0/Documents/QuKi_Notes" });
    expect(deps.resolveMigratedStorageRoot).not.toHaveBeenCalled();
    expect(deps.writeSettings).not.toHaveBeenCalled();
  });

  it("reports recovery when the settings-file path is present but no longer valid", async () => {
    const deps = fakeDeps({
      storageChosen: true,
      storagePath: "/moved-or-deleted-folder",
      validPaths: new Set(),
    });

    const outcome = await decideAndroidStorageSetup(deps);

    expect(outcome).toEqual({ kind: "recovery", unreachablePath: "/moved-or-deleted-folder" });
    expect(deps.resolveMigratedStorageRoot).not.toHaveBeenCalled();
  });

  it("silently adopts and persists a migrated path when no settings-file choice exists yet", async () => {
    const deps = fakeDeps({
      storageChosen: false,
      migratedPath: "/data/data/com.quki.quki_notes/app_flutter/qukis",
    });

    const outcome = await decideAndroidStorageSetup(deps);

    expect(outcome).toEqual({ kind: "use-path", path: "/data/data/com.quki.quki_notes/app_flutter/qukis" });
    expect(deps.writeSettings).toHaveBeenCalledWith({
      storagePath: "/data/data/com.quki.quki_notes/app_flutter/qukis",
      storageChosen: true,
    });
  });

  it("signals first-launch when there is no settings-file choice and no migration found", async () => {
    const deps = fakeDeps({ storageChosen: false, migratedPath: null });

    const outcome = await decideAndroidStorageSetup(deps);

    expect(outcome).toEqual({ kind: "first-launch" });
    expect(deps.writeSettings).not.toHaveBeenCalled();
  });

  it("treats storageChosen true with a null storagePath the same as not-chosen (falls through to migration)", async () => {
    const deps = fakeDeps({ storageChosen: true, storagePath: null, migratedPath: null });

    const outcome = await decideAndroidStorageSetup(deps);

    expect(outcome).toEqual({ kind: "first-launch" });
  });
});
