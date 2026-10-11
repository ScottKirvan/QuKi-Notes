// Runs every web e2e file in e2e/ (`*.e2e.ts`), one after another, so a new
// test file needs no list to be registered in. Files that drive the Electron
// app (they use Playwright's `_electron`) are left to `npm run test:e2e:electron`.
// `--list` prints the files without running them.
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const e2eDir = fileURLToPath(new URL("../e2e/", import.meta.url));

const files = readdirSync(e2eDir)
  .filter((name) => name.endsWith(".e2e.ts"))
  .filter((name) => !readFileSync(join(e2eDir, name), "utf8").includes("_electron"))
  .sort();

if (process.argv.includes("--list")) {
  for (const name of files) console.log(name);
  process.exit(0);
}

const failed = [];
for (const name of files) {
  console.log(`\n=== ${name}`);
  const result = spawnSync(process.execPath, [join(e2eDir, name)], { stdio: "inherit" });
  if (result.status !== 0) failed.push(name);
}

console.log(`\n${files.length - failed.length}/${files.length} e2e files passed.`);
if (failed.length > 0) {
  console.log(`Failed: ${failed.join(", ")}`);
  process.exit(1);
}
