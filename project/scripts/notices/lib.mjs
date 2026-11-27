// Builds the third-party licence notices file shipped with every QuKi build.
// Shared by the web build (vite.config.ts), the cli and mcp esbuild bundles,
// and the tests that stop a dependency shipping without a licence text.
import { existsSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, join, sep } from "node:path";

const LICENCE_FILE = /^(licen[cs]e|copying|notice|unlicense)([-._].*)?$/i;

export const NOTICES_FILE_NAME = "THIRD_PARTY_NOTICES.txt";

/** The package directory a bundled module id sits in, or null if it is not from node_modules. */
export function packageDirOfModule(id) {
  const clean = id.split("?")[0];
  if (clean.includes("\0")) return null;
  const marker = `${sep}node_modules${sep}`;
  const normalised = clean.replaceAll("/", sep);
  const at = normalised.lastIndexOf(marker);
  if (at < 0) return null;
  const rest = normalised.slice(at + marker.length).split(sep);
  const parts = rest[0].startsWith("@") ? rest.slice(0, 2) : rest.slice(0, 1);
  return join(normalised.slice(0, at + marker.length), ...parts);
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf-8"));
}

/** Package directories reachable from `rootDir`'s package.json through dependencies and optionalDependencies. */
export function productionClosure(rootDir) {
  const found = new Map();
  const queue = [rootDir];
  while (queue.length > 0) {
    const dir = queue.pop();
    const pkg = readJson(join(dir, "package.json"));
    const names = [...Object.keys(pkg.dependencies ?? {}), ...Object.keys(pkg.optionalDependencies ?? {})];
    for (const name of names) {
      const depDir = resolvePackageDir(dir, name);
      if (depDir === null) {
        if (pkg.optionalDependencies && name in pkg.optionalDependencies) continue;
        throw new Error(`Cannot find ${name} (a dependency of ${pkg.name}) from ${dir}`);
      }
      if (!found.has(depDir)) {
        found.set(depDir, true);
        queue.push(depDir);
      }
    }
  }
  return [...found.keys()];
}

/** Node-style lookup of a package directory, starting beside `fromDir`. */
export function resolvePackageDir(fromDir, name) {
  let dir = fromDir;
  for (;;) {
    const candidate = join(dir, "node_modules", name);
    if (existsSync(join(candidate, "package.json"))) return realpathSync(candidate);
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

function licenceIdentifier(pkg) {
  if (typeof pkg.license === "string") return pkg.license;
  if (pkg.license && typeof pkg.license.type === "string") return pkg.license.type;
  if (Array.isArray(pkg.licenses)) return pkg.licenses.map((l) => l.type ?? String(l)).join(" OR ");
  return "UNSPECIFIED";
}

function normaliseText(text) {
  return text.replace(/^\uFEFF/, "").replaceAll("\r\n", "\n").replaceAll("\r", "\n").trim();
}

/** One package's name, version, licence identifier and the text of its own licence files. */
export function readPackageNotice(dir) {
  const pkg = readJson(join(dir, "package.json"));
  const files = readdirSync(dir)
    .filter((f) => LICENCE_FILE.test(f) && statSync(join(dir, f)).isFile())
    .sort();
  const text = files.map((f) => normaliseText(readFileSync(join(dir, f), "utf-8"))).filter((t) => t !== "").join("\n\n");
  return {
    name: pkg.name,
    version: pkg.version,
    licence: licenceIdentifier(pkg),
    private: pkg.private === true,
    files,
    text,
  };
}

/**
 * Notices for the given package directories. Our own private packages are left
 * out. `notes` maps a package name to a remark printed beside it.
 */
export function collectNotices(packageDirs, notes = {}) {
  const unique = [...new Set(packageDirs)];
  const packages = unique.map(readPackageNotice).filter((p) => !p.private);
  packages.sort((a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version));
  const missing = packages.filter((p) => p.text === "");
  return { packages: packages.filter((p) => p.text !== ""), missing, notes };
}

const RULE = "=".repeat(78);

/** Renders the notices; identical licence texts are printed once with the packages that carry them. */
export function renderNotices({ packages, notes }, heading) {
  const groups = new Map();
  for (const p of [...packages].sort((a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version))) {
    const key = p.text.replace(/\s+/g, " ");
    if (!groups.has(key)) groups.set(key, { text: p.text, packages: [] });
    groups.get(key).packages.push(p);
  }
  const ordered = [...groups.values()].sort((a, b) => a.packages[0].name.localeCompare(b.packages[0].name));
  if (packages.length === 0) return `${heading}

This software bundles no third-party packages.
`;
  const out = [
    heading,
    "",
    "This software includes the third-party packages listed below. Each is",
    "distributed under the licence text printed with it.",
    "",
    `${packages.length} packages, ${ordered.length} distinct licence texts.`,
    "",
  ];
  ordered.forEach((group, i) => {
    out.push(RULE, `Licence text ${i + 1} of ${ordered.length}`, "", "Applies to:");
    for (const p of group.packages) {
      const note = notes[p.name] ? ` - ${notes[p.name]}` : "";
      out.push(`  ${p.name}@${p.version} (${p.licence})${note}`);
    }
    out.push("", group.text, "");
  });
  return out.join("\n");
}

/** Throws a message naming every package with no licence text. */
export function assertNoMissing(missing) {
  if (missing.length === 0) return;
  const list = missing.map((p) => `${p.name}@${p.version} (${p.licence})`).join(", ");
  throw new Error(`No licence text found for shipped package(s): ${list}`);
}

/** Directories of the packages esbuild bundled, from its metafile. */
export function packageDirsFromMetafile(metafile, baseDir) {
  const dirs = new Set();
  for (const input of Object.keys(metafile.inputs)) {
    const dir = packageDirOfModule(join(baseDir, input));
    if (dir !== null) dirs.add(realpathSync(dir));
  }
  return [...dirs];
}
