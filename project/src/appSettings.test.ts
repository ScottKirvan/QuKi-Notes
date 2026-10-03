import { describe, expect, it } from "vitest";

import { AppSettingsStore, type AppSettingsStorage } from "./appSettings";

class FakeStorage implements AppSettingsStorage {
  private readonly map = new Map<string, string>();

  getItem(key: string): string | null {
    return this.map.has(key) ? this.map.get(key)! : null;
  }

  setItem(key: string, value: string): void {
    this.map.set(key, value);
  }
}

describe("AppSettingsStore", () => {
  it("defaults deleteOrphanedImages to true when nothing has been stored (STORAGE_CONTRACT.md rule 13)", () => {
    const store = new AppSettingsStore(new FakeStorage());
    expect(store.getDeleteOrphanedImages()).toBe(true);
  });

  it("persists an explicit false and reads it back", () => {
    const storage = new FakeStorage();
    const store = new AppSettingsStore(storage);
    store.setDeleteOrphanedImages(false);
    expect(store.getDeleteOrphanedImages()).toBe(false);
  });

  it("persists across separate AppSettingsStore instances sharing the same storage", () => {
    const storage = new FakeStorage();
    new AppSettingsStore(storage).setDeleteOrphanedImages(false);
    expect(new AppSettingsStore(storage).getDeleteOrphanedImages()).toBe(false);
  });

  it("can be flipped back to true after having been set false", () => {
    const storage = new FakeStorage();
    const store = new AppSettingsStore(storage);
    store.setDeleteOrphanedImages(false);
    store.setDeleteOrphanedImages(true);
    expect(store.getDeleteOrphanedImages()).toBe(true);
  });

  it("falls back to the default when the underlying storage throws on read", () => {
    const throwing: AppSettingsStorage = {
      getItem(): string {
        throw new Error("boom");
      },
      setItem(): void {},
    };
    expect(new AppSettingsStore(throwing).getDeleteOrphanedImages()).toBe(true);
  });

  it("does not throw when the underlying storage throws on write", () => {
    const throwing: AppSettingsStorage = {
      getItem(): string | null {
        return null;
      },
      setItem(): void {
        throw new Error("boom");
      },
    };
    expect(() => new AppSettingsStore(throwing).setDeleteOrphanedImages(false)).not.toThrow();
  });
});
