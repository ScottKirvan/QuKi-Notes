import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { createSaveStatusBanner } from "./saveStatusBanner";

class FakeElement {
  hidden = false;
  textContent = "";
  className = "";
  type = "";
  onclick: (() => void) | null = null;
  readonly children: FakeElement[] = [];

  appendChild(child: FakeElement): void {
    this.children.push(child);
  }
}

describe("createSaveStatusBanner", () => {
  const globals = globalThis as unknown as { document?: unknown };
  let previousDocument: unknown;

  beforeEach(() => {
    previousDocument = globals.document;
    globals.document = { createElement: () => new FakeElement() };
  });

  afterEach(() => {
    globals.document = previousDocument;
  });

  it("does nothing when the container is null, e.g. main.ts's document.querySelector came up empty", () => {
    const banner = createSaveStatusBanner(null);
    expect(() => banner.show("Could not start — an unexpected error occurred.")).not.toThrow();
    expect(() => banner.hide()).not.toThrow();
  });

  it("shows a message and unhides the container - this is what a startup failure or a trash-action failure now reaches", () => {
    const container = new FakeElement();
    const banner = createSaveStatusBanner(container as unknown as HTMLElement);

    banner.show("QuKi Notes could not start — an unexpected error occurred.");

    expect(container.hidden).toBe(false);
    const messageEl = container.children[0]!;
    expect(messageEl.textContent).toBe("QuKi Notes could not start — an unexpected error occurred.");
  });

  it("wires an action button when one is given, and hides it when the next show has none", () => {
    const container = new FakeElement();
    const banner = createSaveStatusBanner(container as unknown as HTMLElement);
    let clicked = false;

    banner.show("Could not save — it changed elsewhere.", { label: "Overwrite", onClick: () => (clicked = true) });
    const actionBtn = container.children[1]!;
    expect(actionBtn.hidden).toBe(false);
    expect(actionBtn.textContent).toBe("Overwrite");
    actionBtn.onclick!();
    expect(clicked).toBe(true);

    banner.show("A later message with no action.");
    expect(actionBtn.hidden).toBe(true);
    expect(actionBtn.onclick).toBeNull();
  });

  it("hide() re-hides the container and clears any pending action", () => {
    const container = new FakeElement();
    const banner = createSaveStatusBanner(container as unknown as HTMLElement);

    banner.show("Could not save.", { label: "Retry", onClick: () => {} });
    banner.hide();

    expect(container.hidden).toBe(true);
    const actionBtn = container.children[1]!;
    expect(actionBtn.hidden).toBe(true);
    expect(actionBtn.onclick).toBeNull();
  });

  it("reuses the same message/action elements across repeated show() calls rather than appending new ones", () => {
    const container = new FakeElement();
    const banner = createSaveStatusBanner(container as unknown as HTMLElement);

    banner.show("First.");
    banner.show("Second.");

    expect(container.children).toHaveLength(2);
    expect(container.children[0]!.textContent).toBe("Second.");
  });
});
