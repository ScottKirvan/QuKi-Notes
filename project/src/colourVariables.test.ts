import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

const projectDir = fileURLToPath(new URL("..", import.meta.url));
const srcDir = join(projectDir, "src");

// Obsidian variables the app uses without declaring a default for, because it
// deliberately relies on the environment (a loaded theme) defining them.
// Empty today: the default layer declares everything the app uses.
const EXTERNAL_OBSIDIAN_VARIABLES: string[] = [];

// Not colours and not Obsidian's: geometry that reveal/hangingIndent.ts sets
// per line at runtime.
const RUNTIME_LAYOUT_VARIABLES = ["--quki-hang-width", "--quki-hang-height", "--quki-hang-top"];

// The app's own colour names before it adopted Obsidian's. --text-muted is not
// listed: Obsidian's name for muted text is the same string.
const RETIRED_NAMES = [
  "--surface",
  "--surface-subtle",
  "--text",
  "--accent",
  "--accent-emphasis",
  "--border",
  "--danger",
  "--tint-hover",
  "--tint-pressed",
];

function read(path: string): string {
  return readFileSync(path, "utf-8");
}

function listFiles(dir: string, keep: (name: string) => boolean): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return listFiles(path, keep);
    return keep(entry.name) ? [path] : [];
  });
}

const css = read(join(srcDir, "style.css")).replace(/\/\*[\s\S]*?\*\//g, "");
const indexHtml = read(join(projectDir, "index.html"));
const sourceFiles = listFiles(srcDir, (name) => name.endsWith(".ts") && !name.endsWith(".test.ts"));
const e2eFiles = listFiles(join(projectDir, "e2e"), (name) => name.endsWith(".ts"));

const DEFAULT_LAYER_RULE = /body\.theme-(dark|light)\s*\{([^}]*)\}/g;

function declaredIn(block: string): string[] {
  return [...block.matchAll(/(--[\w-]+)\s*:/g)].map((m) => m[1]!);
}

function defaultLayer(): Record<"dark" | "light", string[]> {
  const layer: Record<"dark" | "light", string[]> = { dark: [], light: [] };
  for (const match of css.matchAll(DEFAULT_LAYER_RULE)) {
    layer[match[1] as "dark" | "light"].push(...declaredIn(match[2]!));
  }
  return layer;
}

function usedIn(text: string): string[] {
  return [...text.matchAll(/var\(\s*(--[\w-]+)/g)].map((m) => m[1]!);
}

const layer = defaultLayer();
const declared = new Set([...layer.dark, ...layer.light]);
const cssOutsideDefaultLayer = css.replace(DEFAULT_LAYER_RULE, "");
const defaultLayerText = [...css.matchAll(DEFAULT_LAYER_RULE)].map((m) => m[2]!).join("\n");

const usedByApp = new Set([
  ...usedIn(cssOutsideDefaultLayer),
  ...usedIn(indexHtml),
  ...sourceFiles.flatMap((file) => usedIn(read(file))),
]);

describe("colour variables use Obsidian's names", () => {
  it("has a default layer for both body.theme-dark and body.theme-light", () => {
    expect(layer.dark.length).toBeGreaterThan(0);
    expect(layer.light.length).toBeGreaterThan(0);
  });

  it("declares exactly the same variables for dark and light", () => {
    expect([...layer.dark].sort()).toEqual([...layer.light].sort());
  });

  it("declares no variable twice within one scheme", () => {
    expect(new Set(layer.dark).size).toBe(layer.dark.length);
    expect(new Set(layer.light).size).toBe(layer.light.length);
  });

  it("declares custom properties only in the default layer, never on :root or in a media query", () => {
    expect(declaredIn(cssOutsideDefaultLayer)).toEqual([]);
  });

  it("no longer keys the palette on prefers-color-scheme", () => {
    expect(css).not.toMatch(/prefers-color-scheme/);
  });

  it("uses only variables the default layer declares, the allowlist, or the runtime layout variables", () => {
    const known = new Set([...declared, ...EXTERNAL_OBSIDIAN_VARIABLES, ...RUNTIME_LAYOUT_VARIABLES]);
    const unknown = [...usedByApp].filter((name) => !known.has(name)).sort();
    expect(unknown).toEqual([]);
  });

  it("declares no default that nothing uses", () => {
    const referencedByDefaults = new Set(usedIn(defaultLayerText));
    const dead = [...declared].filter((name) => !usedByApp.has(name) && !referencedByDefaults.has(name)).sort();
    expect(dead).toEqual([]);
  });

  it("keeps the allowlist honest: every entry is used and none is also declared", () => {
    for (const name of EXTERNAL_OBSIDIAN_VARIABLES) {
      expect(usedByApp.has(name), `${name} is allowlisted but unused`).toBe(true);
      expect(declared.has(name), `${name} is allowlisted but also declared`).toBe(false);
    }
  });

  it("sets each runtime layout variable in hangingIndent.ts", () => {
    const hangingIndent = read(join(srcDir, "reveal", "hangingIndent.ts"));
    for (const name of RUNTIME_LAYOUT_VARIABLES) {
      expect(hangingIndent, name).toContain(`"${name}"`);
    }
  });

  it("no longer mentions any of the app's retired colour names", () => {
    const retired = new RegExp(`(${RETIRED_NAMES.join("|")})(?![\\w-])`, "g");
    const sources: Array<[string, string]> = [
      ["src/style.css", css],
      ["index.html", indexHtml],
      ...[...sourceFiles, ...e2eFiles].map((file): [string, string] => [file, read(file)]),
    ];
    const found = sources.flatMap(([name, text]) => [...text.matchAll(retired)].map((m) => `${name}: ${m[1]}`));
    expect(found).toEqual([]);
  });

  it("does not treat the muted-text name as retired, since Obsidian uses the same string", () => {
    expect(RETIRED_NAMES).not.toContain("--text-muted");
    expect(declared.has("--text-muted")).toBe(true);
  });
});

// Obsidian's mechanism (its own app.css): a theme sets --font-*-theme, and the
// app consumes --font-interface, --font-text and --font-monospace, each
// computed from its -theme variable.
const FONT_KINDS = ["interface", "text", "monospace"] as const;

describe("font variables follow Obsidian's mechanism", () => {
  it("declares each --font-*-theme default and its computed --font-* in both schemes", () => {
    for (const kind of FONT_KINDS) {
      for (const scheme of ["dark", "light"] as const) {
        expect(layer[scheme], `--font-${kind}-theme in ${scheme}`).toContain(`--font-${kind}-theme`);
        expect(layer[scheme], `--font-${kind} in ${scheme}`).toContain(`--font-${kind}`);
      }
    }
  });

  it("computes each --font-* from its own --font-*-theme", () => {
    for (const kind of FONT_KINDS) {
      expect(defaultLayerText).toMatch(new RegExp(`--font-${kind}\\s*:\\s*var\\(--font-${kind}-theme\\)`));
    }
  });

  it("uses only the computed variables outside the default layer, never a --font-*-theme one", () => {
    expect([...usedByApp].filter((name) => /^--font-.*-theme$/.test(name))).toEqual([]);
    for (const kind of FONT_KINDS) {
      expect(usedByApp.has(`--font-${kind}`), `--font-${kind} is never used`).toBe(true);
    }
  });

  it("sets every font-family from a computed variable, never a literal font stack", () => {
    const allowed = /^var\(\s*--font-(interface|text|monospace)\s*\)$/;
    const values = [
      ...[...cssOutsideDefaultLayer.matchAll(/font-family\s*:\s*([^;}]+)/g)].map((m) => ["src/style.css", m[1]!.trim()] as const),
      ...[...indexHtml.matchAll(/font-family\s*:\s*([^;}"']+)/g)].map((m) => ["index.html", m[1]!.trim()] as const),
      ...sourceFiles.flatMap((file) =>
        [...read(file).matchAll(/fontFamily\s*:\s*["'`]([^"'`]*)["'`]/g)].map((m) => [file, m[1]!.trim()] as const),
      ),
    ];
    expect(values.length).toBeGreaterThan(0);
    expect(values.filter(([, value]) => !allowed.test(value))).toEqual([]);
  });
});
