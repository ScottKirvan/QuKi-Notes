import { describe, expect, it, vi } from "vitest";

import { createStorageAccessGate, type StorageAccessDeps, type StorageAccessState } from "./androidStorageAccess.js";

/**
 * Captures the callback the gate registers with onAppStateChange so tests
 * can simulate app foreground/background transitions directly, without any
 * real Capacitor App plugin or DOM involved.
 */
function fakeDeps(initialGranted: boolean): {
  deps: StorageAccessDeps;
  fireAppStateChange: (isActive: boolean) => void;
  setGranted: (granted: boolean) => void;
  removeSpy: ReturnType<typeof vi.fn>;
  isExternalStorageManager: ReturnType<typeof vi.fn>;
  requestAllFilesAccess: ReturnType<typeof vi.fn>;
} {
  let granted = initialGranted;
  let listener: ((isActive: boolean) => void) | undefined;
  const removeSpy = vi.fn();
  const isExternalStorageManager = vi.fn(async () => granted);
  const requestAllFilesAccess = vi.fn(async () => undefined);

  const deps: StorageAccessDeps = {
    isExternalStorageManager,
    requestAllFilesAccess,
    onAppStateChange: (callback) => {
      listener = callback;
      return { remove: removeSpy };
    },
  };

  return {
    deps,
    fireAppStateChange: (isActive: boolean) => listener?.(isActive),
    setGranted: (next: boolean) => {
      granted = next;
    },
    removeSpy,
    isExternalStorageManager,
    requestAllFilesAccess,
  };
}

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

describe("createStorageAccessGate", () => {
  it("resolves ready() immediately when access is already granted, without ever requesting it or showing needs-permission", async () => {
    const { deps, isExternalStorageManager, requestAllFilesAccess } = fakeDeps(true);
    const states: StorageAccessState[] = [];

    const gate = createStorageAccessGate(deps, (s) => states.push(s));
    await gate.ready();

    expect(states).toEqual(["checking", "granted"]);
    expect(isExternalStorageManager).toHaveBeenCalledTimes(1);
    expect(requestAllFilesAccess).not.toHaveBeenCalled();
    expect(gate.getState()).toBe("granted");
  });

  it("shows needs-permission when not granted, and stays pending until requestAccess is followed by a granted foreground resume", async () => {
    const { deps, fireAppStateChange, setGranted, requestAllFilesAccess } = fakeDeps(false);
    const states: StorageAccessState[] = [];

    const gate = createStorageAccessGate(deps, (s) => states.push(s));
    await flushMicrotasks();
    expect(states).toEqual(["checking", "needs-permission"]);

    let readyResolved = false;
    void gate.ready().then(() => {
      readyResolved = true;
    });

    await gate.requestAccess();
    expect(requestAllFilesAccess).toHaveBeenCalledTimes(1);
    expect(gate.getState()).toBe("waiting-for-settings");
    expect(readyResolved).toBe(false);

    // The user grants access on the system settings screen, then switches
    // back — the only signal available is the app returning to foreground.
    setGranted(true);
    fireAppStateChange(true);
    await flushMicrotasks();

    expect(readyResolved).toBe(true);
    expect(gate.getState()).toBe("granted");
    expect(states).toEqual(["checking", "needs-permission", "waiting-for-settings", "checking", "granted"]);
  });

  it("returns to needs-permission, and leaves ready() pending, when the user backs out of settings without granting", async () => {
    const { deps, fireAppStateChange } = fakeDeps(false);
    const states: StorageAccessState[] = [];

    const gate = createStorageAccessGate(deps, (s) => states.push(s));
    await flushMicrotasks();

    let readyResolved = false;
    void gate.ready().then(() => {
      readyResolved = true;
    });

    await gate.requestAccess();
    fireAppStateChange(true); // still not granted
    await flushMicrotasks();

    expect(readyResolved).toBe(false);
    expect(gate.getState()).toBe("needs-permission");
    expect(states.at(-1)).toBe("needs-permission");
  });

  it("ignores a foreground resume that was not preceded by requestAccess", async () => {
    const { deps, fireAppStateChange, isExternalStorageManager } = fakeDeps(false);

    const gate = createStorageAccessGate(deps, () => {});
    await flushMicrotasks();
    isExternalStorageManager.mockClear();

    // e.g. the user switched to another app and back, unrelated to settings.
    fireAppStateChange(true);
    await flushMicrotasks();

    expect(isExternalStorageManager).not.toHaveBeenCalled();
    expect(gate.getState()).toBe("needs-permission");
  });

  it("ignores a transition to the background while waiting for settings", async () => {
    const { deps, fireAppStateChange, isExternalStorageManager } = fakeDeps(false);

    const gate = createStorageAccessGate(deps, () => {});
    await flushMicrotasks();
    await gate.requestAccess();
    isExternalStorageManager.mockClear();

    fireAppStateChange(false); // leaving to go to the settings screen
    await flushMicrotasks();

    expect(isExternalStorageManager).not.toHaveBeenCalled();
    expect(gate.getState()).toBe("waiting-for-settings");
  });

  it("destroy() removes the underlying app-state listener", () => {
    const { deps, removeSpy } = fakeDeps(true);
    const gate = createStorageAccessGate(deps, () => {});

    gate.destroy();

    expect(removeSpy).toHaveBeenCalledTimes(1);
  });
});
