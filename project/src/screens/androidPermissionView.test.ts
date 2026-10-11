import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createBackDismissStack } from "../backDismissStack";
import { createAndroidPermissionView } from "./androidPermissionView";

vi.mock("./icons", () => ({ setIconButton: () => {} }));

class FakeElement {
  hidden = false;
  disabled = false;
  className = "";
  innerHTML = "";
  parent: FakeElement | null = null;
  readonly children: FakeElement[] = [];
  private readonly parts = new Map<string, FakeElement>();
  private readonly listeners: Array<() => void> = [];

  get isConnected(): boolean {
    return this.parent !== null;
  }

  appendChild(child: FakeElement): void {
    child.remove();
    child.parent = this;
    this.children.push(child);
  }

  remove(): void {
    if (!this.parent) return;
    const siblings = this.parent.children;
    siblings.splice(siblings.indexOf(this), 1);
    this.parent = null;
  }

  querySelector(selector: string): FakeElement {
    let part = this.parts.get(selector);
    if (!part) {
      part = new FakeElement();
      this.parts.set(selector, part);
    }
    return part;
  }

  addEventListener(_type: string, listener: () => void): void {
    this.listeners.push(listener);
  }

  click(): void {
    for (const listener of this.listeners) listener();
  }
}

describe("createAndroidPermissionView", () => {
  const globals = globalThis as unknown as { document?: unknown };
  let previousDocument: unknown;

  beforeEach(() => {
    previousDocument = globals.document;
    globals.document = { createElement: () => new FakeElement() };
  });

  afterEach(() => {
    globals.document = previousDocument;
  });

  function overlays(host: FakeElement): FakeElement[] {
    return host.children.filter((child) => child.className === "android-permission-overlay");
  }

  it("leaves no overlay behind after repeated grant and back-out flows, as when Change location picks Filesystem storage again", () => {
    const host = new FakeElement();
    const backDismiss = createBackDismissStack();

    for (let flow = 0; flow < 3; flow++) {
      const view = createAndroidPermissionView(host as unknown as HTMLElement, () => {}, () => {}, backDismiss);
      view.render("checking");
      view.render("needs-permission");
      expect(overlays(host)).toHaveLength(1);
      expect(overlays(host)[0]!.hidden).toBe(false);
      view.render("waiting-for-settings");
      view.render("checking");
      expect(overlays(host)).toHaveLength(1);
      view.render("granted");
      expect(overlays(host)).toHaveLength(0);
    }

    for (let flow = 0; flow < 3; flow++) {
      const view = createAndroidPermissionView(host as unknown as HTMLElement, () => {}, () => {}, backDismiss);
      view.render("needs-permission");
      expect(overlays(host)).toHaveLength(1);
      expect(backDismiss.dismissTop()).toBe(true);
      expect(overlays(host)).toHaveLength(0);
    }

    expect(backDismiss.dismissTop()).toBe(false);
  });

  it("shows the same overlay again when access is lost and re-requested within one flow", () => {
    const host = new FakeElement();
    const view = createAndroidPermissionView(host as unknown as HTMLElement, () => {}, () => {});

    view.render("needs-permission");
    const first = overlays(host)[0];
    view.render("granted");
    view.render("needs-permission");

    expect(overlays(host)).toEqual([first]);
    expect(first!.hidden).toBe(false);
  });

  it("still wires Grant access, the back button and Android Back to the callbacks", () => {
    const host = new FakeElement();
    const backDismiss = createBackDismissStack();
    let requests = 0;
    let backOuts = 0;
    const view = createAndroidPermissionView(
      host as unknown as HTMLElement,
      () => requests++,
      () => backOuts++,
      backDismiss,
    );

    view.render("needs-permission");
    const overlay = overlays(host)[0]!;
    overlay.querySelector(".android-permission-btn").click();
    expect(requests).toBe(1);

    view.render("waiting-for-settings");
    expect(overlay.querySelector(".android-permission-btn").disabled).toBe(true);
    expect(overlay.querySelector(".android-permission-waiting").hidden).toBe(false);

    overlay.querySelector(".android-permission-back-btn").click();
    expect(backOuts).toBe(1);
    expect(overlays(host)).toHaveLength(0);
    expect(backDismiss.dismissTop()).toBe(false);

    view.render("needs-permission");
    expect(backDismiss.dismissTop()).toBe(true);
    expect(backOuts).toBe(2);
  });
});
