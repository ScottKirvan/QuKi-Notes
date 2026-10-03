import { describe, expect, it } from "vitest";

import { performTrashAction } from "./trashView";

describe("performTrashAction", () => {
  it("returns the action's own result and never calls showToast when the action resolves", async () => {
    const toasts: Array<[string, number]> = [];
    const showToast = (message: string, durationMs: number): void => {
      toasts.push([message, durationMs]);
    };

    const result = await performTrashAction(() => Promise.resolve({ id: "a", renamed: false }), showToast, "Could not restore — an unexpected error occurred.");

    expect(result).toEqual({ id: "a", renamed: false });
    expect(toasts).toHaveLength(0);
  });

  it("surfaces a rejected restore via the toast instead of letting it become an unhandled rejection", async () => {
    const toasts: Array<[string, number]> = [];
    const showToast = (message: string, durationMs: number): void => {
      toasts.push([message, durationMs]);
    };

    const result = await performTrashAction(
      () => Promise.reject(new Error("permission denied")),
      showToast,
      "Could not restore — an unexpected error occurred.",
    );

    expect(result).toBeNull();
    expect(toasts).toEqual([["Could not restore — an unexpected error occurred.", 4000]]);
  });

  it("surfaces a rejected permanent delete via the toast", async () => {
    const toasts: Array<[string, number]> = [];
    const showToast = (message: string, durationMs: number): void => {
      toasts.push([message, durationMs]);
    };

    const result = await performTrashAction(
      () => Promise.reject(new Error("disk full")),
      showToast,
      "Could not delete — an unexpected error occurred.",
    );

    expect(result).toBeNull();
    expect(toasts).toEqual([["Could not delete — an unexpected error occurred.", 4000]]);
  });

  it("surfaces a rejected empty-trash via the toast", async () => {
    const toasts: Array<[string, number]> = [];
    const showToast = (message: string, durationMs: number): void => {
      toasts.push([message, durationMs]);
    };

    const result = await performTrashAction(
      () => Promise.reject(new Error("file gone")),
      showToast,
      "Could not empty Trash — an unexpected error occurred.",
    );

    expect(result).toBeNull();
    expect(toasts).toEqual([["Could not empty Trash — an unexpected error occurred.", 4000]]);
  });

  it("does not itself throw or leave the rejection unhandled when the action rejects with a non-Error value", async () => {
    const showToast = (): void => {};

    await expect(performTrashAction(() => Promise.reject("a string rejection"), showToast, "Could not delete.")).resolves.toBeNull();
  });
});
