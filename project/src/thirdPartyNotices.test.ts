import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { afterEach, describe, expect, it } from "vitest";

import { readAndroidLibraries, renderLibraryNotices } from "../scripts/notices/androidLibraries.mjs";
import {
  collectNotices,
  packageDirOfModule,
  productionClosure,
  renderNotices,
  resolvePackageDir,
} from "../scripts/notices/lib.mjs";

const projectDir = fileURLToPath(new URL("..", import.meta.url));
// Packages the generated service worker inlines (see scripts/notices/vitePlugin.mjs).
const SERVICE_WORKER_PACKAGES = ["workbox-core", "workbox-expiration", "workbox-precaching", "workbox-routing", "workbox-strategies"];

describe("shipped production dependencies", () => {
  it("each has licence text to ship", () => {
    const dirs = productionClosure(projectDir);
    const build = resolvePackageDir(projectDir, "workbox-build");
    expect(build).not.toBeNull();
    for (const name of SERVICE_WORKER_PACKAGES) {
      const dir = resolvePackageDir(build as string, name);
      expect(dir, name).not.toBeNull();
      dirs.push(dir as string, ...productionClosure(dir as string));
    }
    const notices = collectNotices(dirs);
    expect(notices.missing.map((p) => `${p.name}@${p.version}`)).toEqual([]);
    expect(notices.packages.length).toBeGreaterThan(20);
  });
});

describe("notices library", () => {
  let tmp: string;
  afterEach(() => rmSync(tmp || join(tmpdir(), "quki-notices-none"), { recursive: true, force: true }));

  function fakePackage(name: string, files: Record<string, string>, extra: object = {}): string {
    tmp ||= mkdtempSync(join(tmpdir(), "quki-notices-"));
    const dir = join(tmp, "node_modules", name);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "package.json"), JSON.stringify({ name, version: "1.0.0", license: "MIT", ...extra }));
    for (const [file, text] of Object.entries(files)) writeFileSync(join(dir, file), text);
    return dir;
  }

  it("reports a package with no licence file as missing", () => {
    tmp = "";
    const dir = fakePackage("no-licence", { "README.md": "MIT, trust me" });
    const notices = collectNotices([dir]);
    expect(notices.missing.map((p) => p.name)).toEqual(["no-licence"]);
    expect(notices.packages).toEqual([]);
  });

  it("reads LICENSE, COPYING and NOTICE files and ignores other files", () => {
    tmp = "";
    const dir = fakePackage("apache-ish", { LICENSE: "Apache text\r\n", NOTICE: "Notice text", "index.js": "x" });
    const [pkg] = collectNotices([dir]).packages;
    expect(pkg.files).toEqual(["LICENSE", "NOTICE"]);
    expect(pkg.text).toBe("Apache text\n\nNotice text");
  });

  it("prints identical licence texts once and keeps different ones apart", () => {
    tmp = "";
    const a = fakePackage("a", { LICENSE: "Copyright A\nMIT" });
    const b = fakePackage("b", { LICENSE: "Copyright A\n\nMIT" });
    const c = fakePackage("c", { LICENSE: "Copyright C\nMIT" });
    const out = renderNotices(collectNotices([c, b, a]), "heading");
    expect(out).toContain("3 packages, 2 distinct licence texts.");
    expect(out.match(/Copyright A/g)).toHaveLength(1);
    expect(out.indexOf("a@1.0.0")).toBeLessThan(out.indexOf("b@1.0.0"));
  });

  it("is deterministic regardless of input order", () => {
    tmp = "";
    const a = fakePackage("a", { LICENSE: "A" });
    const b = fakePackage("b", { LICENSE: "B" });
    expect(renderNotices(collectNotices([a, b]), "h")).toBe(renderNotices(collectNotices([b, a]), "h"));
  });

  it("leaves out private packages, which are our own code", () => {
    tmp = "";
    const dir = fakePackage("ours", {}, { private: true });
    const notices = collectNotices([dir]);
    expect(notices.packages).toEqual([]);
    expect(notices.missing).toEqual([]);
  });

  it("finds the package directory of a bundled module, scoped or nested", () => {
    const sep = "/";
    expect(packageDirOfModule(`/p/node_modules/@a/b/dist/x.js`)?.replaceAll("\\", sep)).toBe("/p/node_modules/@a/b");
    expect(packageDirOfModule(`/p/node_modules/a/node_modules/c/x.js`)?.replaceAll("\\", sep)).toBe("/p/node_modules/a/node_modules/c");
    expect(packageDirOfModule("/p/src/main.ts")).toBeNull();
    expect(packageDirOfModule("\0virtual:thing")).toBeNull();
  });
});

describe("Android library notices", () => {
  let tmp = "";
  afterEach(() => rmSync(tmp || join(tmpdir(), "quki-notices-none"), { recursive: true, force: true }));

  function fixture(list: object, licences: Record<string, string>): [string, string] {
    tmp = mkdtempSync(join(tmpdir(), "quki-android-notices-"));
    const dir = join(tmp, "licences");
    mkdirSync(dir);
    for (const [id, text] of Object.entries(licences)) writeFileSync(join(dir, `${id}.txt`), text);
    const file = join(tmp, "libs.json");
    writeFileSync(file, JSON.stringify(list));
    return [file, dir];
  }

  it("gives every committed library its licence text", () => {
    const { packages } = readAndroidLibraries();
    expect(packages.length).toBeGreaterThan(30);
    for (const p of packages) expect(p.text, p.name).toContain("Apache License");
  });

  it("lists the libraries in the combined notices once per licence text", () => {
    const [file, dir] = fixture(
      { libraries: [{ name: "g:b", version: "2", licence: "Apache-2.0" }, { name: "g:a", version: "1", licence: "Apache-2.0" }] },
      { "Apache-2.0": "Apache text" },
    );
    const android = readAndroidLibraries(file, dir);
    const out = renderNotices({ packages: android.packages, missing: [], notes: android.notes }, "h");
    expect(out).toContain("2 packages, 1 distinct licence texts.");
    expect(out.indexOf("g:a@1")).toBeLessThan(out.indexOf("g:b@2"));
    expect(out.match(/Apache text/g)).toHaveLength(1);
  });

  it("throws when a library's licence has no canonical text", () => {
    const [file, dir] = fixture({ libraries: [{ name: "g:a", version: "1", licence: "MIT" }] }, {});
    expect(() => readAndroidLibraries(file, dir)).toThrow(/g:a@1: no licence text for MIT/);
  });

  it("throws on an empty list and on a path-like licence identifier", () => {
    const [empty, dir] = fixture({ libraries: [] }, {});
    expect(() => readAndroidLibraries(empty, dir)).toThrow(/lists no libraries/);
    const [bad, dir2] = fixture({ libraries: [{ name: "g:a", version: "1", licence: "../x" }] }, {});
    expect(() => readAndroidLibraries(bad, dir2)).toThrow(/bad licence identifier/);
  });

  it("prints NOTICE texts a library ships, and nothing when there are none", () => {
    const [file, dir] = fixture({ libraries: [{ name: "g:a", version: "1", licence: "Apache-2.0", notices: ["  Notice A  "] }] }, { "Apache-2.0": "T" });
    const { notices } = readAndroidLibraries(file, dir);
    expect(renderLibraryNotices(notices)).toContain("g:a@1\n\nNotice A\n");
    expect(renderLibraryNotices([])).toBe("");
  });
});
