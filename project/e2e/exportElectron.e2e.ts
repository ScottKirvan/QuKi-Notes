import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as zlib from "node:zlib";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { _electron as electron, type ElectronApplication, type Page } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const electronDir = path.join(__dirname, "..", "electron");
const electronMain = path.join(electronDir, "dist", "main.js");
const electronRequire = createRequire(path.join(electronDir, "package.json"));
const electronExecutablePath = electronRequire("electron") as unknown as string;

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
}

function mkTempDir(prefix: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

// See e2e/electron.e2e.ts for why ELECTRON_RUN_AS_NODE must not be inherited.
const baseChildEnv = { ...process.env, QUKI_ELECTRON_DIR: "" };
delete baseChildEnv.ELECTRON_RUN_AS_NODE;

async function launch(storageDir: string, forceExportSavePath?: string): Promise<{ app: ElectronApplication; page: Page }> {
  const env: NodeJS.ProcessEnv = { ...baseChildEnv, QUKI_ELECTRON_DIR: storageDir };
  if (forceExportSavePath !== undefined) env.QUKI_TEST_FORCE_EXPORT_SAVE_PATH = forceExportSavePath;
  else delete env.QUKI_TEST_FORCE_EXPORT_SAVE_PATH;
  const app = await electron.launch({ executablePath: electronExecutablePath, args: [electronMain], env });
  const page = await app.firstWindow();
  await page.waitForSelector(".cm-content");
  return { app, page };
}

async function typeInEditor(page: Page, text: string): Promise<void> {
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(text);
}

async function openSettings(page: Page): Promise<void> {
  await page.click("#btn-settings");
  await page.locator(".view:not([hidden]) .export-btn").waitFor();
}

async function main(): Promise<void> {
  if (!fs.existsSync(electronMain)) {
    throw new Error(`${electronMain} not found - run "npm run build" in project/electron first`);
  }

  // --- Scenario 1: Export writes the real gzipped tar to the path chosen
  // in the native Save As dialog (QUKI_TEST_FORCE_EXPORT_SAVE_PATH stands in
  // for that choice - Playwright cannot drive an OS-native dialog, the same
  // seam already used for the storage-location picker). Also proves
  // flush-before-export: Export is clicked immediately after typing, well
  // inside the 2s auto-save debounce. ---
  {
    const storageDir = mkTempDir("quki-export-e2e-storage-");
    const outDir = mkTempDir("quki-export-e2e-out-");
    const destPath = path.join(outDir, "chosen-export.tar.gz");
    const { app, page } = await launch(storageDir, destPath);

    const marker = `Export e2e proof ${Date.now()}`;
    await typeInEditor(page, marker);
    await openSettings(page);
    await page.click(".export-btn");

    await page.waitForFunction((expected) => document.querySelector(".toast")?.textContent === expected, `Exported to ${destPath}.`);

    assert(fs.existsSync(destPath), `expected the exported archive at ${destPath}`);
    const gunzipped = zlib.gunzipSync(fs.readFileSync(destPath));
    assert(gunzipped.includes(marker), `exported archive should contain the flushed QuKi body ("${marker}")`);
    console.log(`[e2e-export-electron] PASS: Export wrote a real archive to ${destPath} containing the flushed QuKi body, and toasted the real path`);

    await app.close();
    fs.rmSync(storageDir, { recursive: true, force: true });
    fs.rmSync(outDir, { recursive: true, force: true });
  }

  // --- Scenario 2: cancelling the native Save As dialog (empty string
  // standing in for cancellation, matching chooseFilesystem's convention)
  // writes nothing and shows no toast. ---
  {
    const storageDir = mkTempDir("quki-export-e2e-storage-");
    const { app, page } = await launch(storageDir, "");

    await typeInEditor(page, `Export cancel e2e proof ${Date.now()}`);
    await openSettings(page);
    await page.click(".export-btn");

    // Give any (wrongly shown) toast a chance to appear before asserting its absence.
    await page.waitForTimeout(500);
    const toastHidden = await page.locator(".toast").isHidden();
    assert(toastHidden, "cancelling the Save As dialog must not show a toast");
    console.log("[e2e-export-electron] PASS: cancelling the Save As dialog writes nothing and shows no toast");

    await app.close();
    fs.rmSync(storageDir, { recursive: true, force: true });
  }
}

main()
  .then(() => {
    console.log("[e2e-export-electron] ALL SCENARIOS PASSED");
    process.exit(0);
  })
  .catch((err: unknown) => {
    console.error("[e2e-export-electron] FAILED:", err);
    process.exit(1);
  });
