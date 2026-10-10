import { describe, expect, it, vi } from "vitest";

import { createBackDismissStack, type BackDismissStack } from "./backDismissStack.js";

function openDialog(stack: BackDismissStack): { cancel: ReturnType<typeof vi.fn> } {
  let unregister = (): void => {};
  const cancel = vi.fn(() => unregister());
  unregister = stack.push(cancel);
  return { cancel };
}

describe("createBackDismissStack", () => {
  it("reports nothing to dismiss when no dialog is open", () => {
    expect(createBackDismissStack().dismissTop()).toBe(false);
  });

  it("cancels the most recently opened dialog first, one per call", () => {
    const stack = createBackDismissStack();
    const first = openDialog(stack);
    const second = openDialog(stack);

    expect(stack.dismissTop()).toBe(true);
    expect(second.cancel).toHaveBeenCalledTimes(1);
    expect(first.cancel).not.toHaveBeenCalled();

    expect(stack.dismissTop()).toBe(true);
    expect(first.cancel).toHaveBeenCalledTimes(1);
    expect(stack.dismissTop()).toBe(false);
  });

  it("forgets a dialog that closed on its own", () => {
    const stack = createBackDismissStack();
    const dismiss = vi.fn();
    const unregister = stack.push(dismiss);
    unregister();

    expect(stack.dismissTop()).toBe(false);
    expect(dismiss).not.toHaveBeenCalled();
  });

  it("a dialog that ignores the cancel still takes Back, and stays registered", () => {
    const stack = createBackDismissStack();
    const busy = vi.fn();
    stack.push(busy);

    expect(stack.dismissTop()).toBe(true);
    expect(stack.dismissTop()).toBe(true);
    expect(busy).toHaveBeenCalledTimes(2);
  });

  it("unregistering twice removes only that dialog", () => {
    const stack = createBackDismissStack();
    const other = openDialog(stack);
    const unregister = stack.push(vi.fn());
    unregister();
    unregister();

    expect(stack.dismissTop()).toBe(true);
    expect(other.cancel).toHaveBeenCalledTimes(1);
  });
});
