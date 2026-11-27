// The Maven libraries compiled into the Android app. The list in
// androidLibraries.json is written by `./gradlew updateAndroidLibraryNotices`
// (project/android) and checked against the real release runtime classpath by
// `checkAndroidLibraryNotices`, which runs before every Android build. The web
// build only reads the committed list, so it needs no Gradle or Java.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));

export const ANDROID_LIBRARY_NOTE = "Android app only (native library)";

function normaliseText(text) {
  return text.replace(/^\uFEFF/, "").replaceAll("\r\n", "\n").replaceAll("\r", "\n").trim();
}

/**
 * The Android libraries as notice packages (name, version, licence, licence
 * text), plus the NOTICE texts some of them ship. Throws on a licence with no
 * canonical text, so a library cannot be listed without its licence.
 */
export function readAndroidLibraries(listFile = join(here, "androidLibraries.json"), licenceDir = join(here, "licences")) {
  const { libraries } = JSON.parse(readFileSync(listFile, "utf-8"));
  if (!Array.isArray(libraries) || libraries.length === 0) throw new Error(`${listFile} lists no libraries`);
  const packages = [];
  const notices = [];
  for (const lib of libraries) {
    const ids = lib.licence.split(" AND ");
    const text = ids
      .map((id) => {
        if (!/^[A-Za-z0-9.+-]+$/.test(id)) throw new Error(`${lib.name}: bad licence identifier ${id}`);
        try {
          return normaliseText(readFileSync(join(licenceDir, `${id}.txt`), "utf-8"));
        } catch {
          throw new Error(`${lib.name}@${lib.version}: no licence text for ${id} in ${licenceDir}`);
        }
      })
      .join("\n\n");
    packages.push({ name: lib.name, version: lib.version, licence: lib.licence, private: false, files: [], text });
    for (const n of lib.notices ?? []) notices.push({ name: lib.name, version: lib.version, text: normaliseText(n) });
  }
  return { packages, notices, notes: Object.fromEntries(packages.map((p) => [p.name, ANDROID_LIBRARY_NOTE])) };
}

/** The NOTICE texts that Android libraries ship, or "" when there are none. */
export function renderLibraryNotices(notices) {
  if (notices.length === 0) return "";
  const out = ["=".repeat(78), "NOTICE texts shipped with Android libraries", ""];
  for (const n of [...notices].sort((a, b) => a.name.localeCompare(b.name) || a.text.localeCompare(b.text))) {
    out.push(`${n.name}@${n.version}`, "", n.text, "");
  }
  return out.join("\n");
}
