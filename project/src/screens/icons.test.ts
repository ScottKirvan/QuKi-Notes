import { ArrowLeft, Trash2 } from "lucide";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { createIcon, setIconButton } from "./icons";

class FakeElement {
  readonly attributes = new Map<string, string>();
  readonly children: FakeElement[] = [];
  title = "";

  constructor(readonly tagName: string) {}

  setAttribute(name: string, value: string): void {
    this.attributes.set(name, value);
  }

  getAttribute(name: string): string | null {
    return this.attributes.get(name) ?? null;
  }

  appendChild(child: FakeElement): void {
    this.children.push(child);
  }

  replaceChildren(...nodes: FakeElement[]): void {
    this.children.length = 0;
    this.children.push(...nodes);
  }
}

describe("icon helpers", () => {
  const globals = globalThis as unknown as { document?: unknown };
  let previousDocument: unknown;

  beforeEach(() => {
    previousDocument = globals.document;
    globals.document = { createElementNS: (_ns: string, tag: string) => new FakeElement(tag) };
  });

  afterEach(() => {
    globals.document = previousDocument;
  });

  it("creates an SVG of the requested size that is hidden from assistive tech and inherits the text colour", () => {
    const icon = createIcon(ArrowLeft, 20) as unknown as FakeElement;

    expect(icon.tagName).toBe("svg");
    expect(icon.getAttribute("width")).toBe("20");
    expect(icon.getAttribute("height")).toBe("20");
    expect(icon.getAttribute("aria-hidden")).toBe("true");
    expect(icon.getAttribute("focusable")).toBe("false");
    expect(icon.getAttribute("stroke")).toBe("currentColor");
    expect(icon.children.length).toBeGreaterThan(0);
  });

  it("puts only the icon in a button and labels it with the aria-label and tooltip", () => {
    const button = new FakeElement("button");
    button.children.push(new FakeElement("span"));

    setIconButton(button as unknown as HTMLButtonElement, ArrowLeft, "Back to editor");

    expect(button.children).toHaveLength(1);
    expect(button.children[0]!.tagName).toBe("svg");
    expect(button.getAttribute("aria-label")).toBe("Back to editor");
    expect(button.title).toBe("Back to editor");
  });

  it("draws button icons at 24px by default, matching the Flutter app's icon buttons", () => {
    const button = new FakeElement("button");

    setIconButton(button as unknown as HTMLButtonElement, Trash2, "Delete");

    expect(button.children[0]!.getAttribute("width")).toBe("24");
    expect(button.children[0]!.getAttribute("height")).toBe("24");
  });

  it("passes an explicit size through to the icon", () => {
    const button = new FakeElement("button");

    setIconButton(button as unknown as HTMLButtonElement, Trash2, "Delete", 18);

    expect(button.children[0]!.getAttribute("width")).toBe("18");
  });
});
