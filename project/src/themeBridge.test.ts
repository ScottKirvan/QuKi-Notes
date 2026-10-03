import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf-8");

function bodyStart(): string {
  const match = /<body[^>]*>/.exec(html);
  if (match === null) throw new Error("index.html has no <body>");
  return html.slice(match.index + match[0].length);
}

function inlineScript(): string {
  const match = /^\s*<script>([\s\S]*?)<\/script>/.exec(bodyStart());
  if (match === null) throw new Error("the first thing in <body> must be a plain inline <script>");
  return match[1]!;
}

interface FakeMedia {
  matches: boolean;
  handlers: Array<() => void>;
}

function runBridge(initiallyDark: boolean): { classes: Set<string>; media: FakeMedia; setDark(dark: boolean): void } {
  const classes = new Set<string>();
  const media: FakeMedia = { matches: initiallyDark, handlers: [] };
  const fakeWindow = {
    matchMedia: (query: string) => {
      expect(query).toBe("(prefers-color-scheme: dark)");
      return {
        get matches() {
          return media.matches;
        },
        addEventListener: (type: string, handler: () => void) => {
          expect(type).toBe("change");
          media.handlers.push(handler);
        },
      };
    },
  };
  const fakeDocument = {
    body: {
      classList: {
        toggle: (name: string, force: boolean) => {
          if (force) classes.add(name);
          else classes.delete(name);
        },
      },
    },
  };
  new Function("window", "document", inlineScript())(fakeWindow, fakeDocument);
  return {
    classes,
    media,
    setDark(dark: boolean) {
      media.matches = dark;
      for (const handler of media.handlers) handler();
    },
  };
}

describe("light/dark bridge in index.html", () => {
  it("is the first thing in <body>, ahead of any app content and of the module script", () => {
    const rest = bodyStart();
    const scriptEnd = rest.indexOf("</script>");
    expect(rest.indexOf('id="app"')).toBeGreaterThan(scriptEnd);
    expect(rest.indexOf('type="module"')).toBeGreaterThan(scriptEnd);
  });

  it("puts theme-dark, and only theme-dark, on <body> when the OS scheme is dark", () => {
    expect([...runBridge(true).classes]).toEqual(["theme-dark"]);
  });

  it("puts theme-light, and only theme-light, on <body> when the OS scheme is light", () => {
    expect([...runBridge(false).classes]).toEqual(["theme-light"]);
  });

  it("swaps the class when the OS scheme changes, never leaving both or neither", () => {
    const bridge = runBridge(false);
    bridge.setDark(true);
    expect([...bridge.classes]).toEqual(["theme-dark"]);
    bridge.setDark(false);
    expect([...bridge.classes]).toEqual(["theme-light"]);
  });
});
