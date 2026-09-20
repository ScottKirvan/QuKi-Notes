import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { _electron as electron, type ElectronApplication, type Page } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const electronDir = path.join(__dirname, "..", "electron");
const electronMain = path.join(electronDir, "dist", "main.js");
// playwright's _electron.launch() resolves the `electron` package (for its
// executablePath) relative to the current working directory, but the
// electron binary is installed under electron/node_modules (its own
// package, matching cli/mcp's pattern), not project/node_modules - so it
// must be resolved explicitly rather than left to playwright's default.
const electronRequire = createRequire(path.join(electronDir, "package.json"));
const electronExecutablePath = electronRequire("electron") as unknown as string;

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
}

function mkTempStorageDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "quki-electron-e2e-"));
}

// This e2e script itself often runs inside a host that sets
// ELECTRON_RUN_AS_NODE=1 (e.g. an Electron-based dev tool) so that the
// *host's own* embedded Electron binary behaves as plain Node. Inherited
// into the launched Electron *app under test*, that same variable would
// make it start as plain Node too (no app/BrowserWindow, no window at
// all) - real Electron sets this on its own subprocesses as needed, so it
// must not be inherited from this script's environment.
const childEnv = { ...process.env, QUKI_ELECTRON_DIR: "" };
delete childEnv.ELECTRON_RUN_AS_NODE;

async function launch(storageDir: string): Promise<{ app: ElectronApplication; page: Page }> {
  const app = await electron.launch({
    executablePath: electronExecutablePath,
    args: [electronMain],
    env: { ...childEnv, QUKI_ELECTRON_DIR: storageDir },
  });
  const page = await app.firstWindow();
  await page.waitForSelector(".cm-content");
  return { app, page };
}

async function readEditorBody(page: Page): Promise<string> {
  return page.evaluate(
    () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
  );
}

async function main(): Promise<void> {
  if (!fs.existsSync(electronMain)) {
    throw new Error(`${electronMain} not found - run "npm run build" in project/electron first`);
  }

  const storageDir = mkTempStorageDir();
  console.log(`[e2e] Electron QUKI_ELECTRON_DIR: ${storageDir}`);

  // --- Scenario 1: create a QuKi in the real Electron app; confirm a real
  // .md file appears on disk at the expected path with the expected content. ---
  let { app, page } = await launch(storageDir);

  const marker = `Electron e2e proof ${Date.now()}`;
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(marker);
  await page.waitForTimeout(2500); // 2s debounce + margin

  let mdFiles = fs.readdirSync(storageDir).filter((f) => f.endsWith(".md"));
  assert(mdFiles.length === 1, `expected exactly one .md file in ${storageDir}, found: ${mdFiles.join(", ")}`);
  const mdPath = path.join(storageDir, mdFiles[0]!);
  assert(fs.readFileSync(mdPath, "utf8") === marker, "on-disk file should equal the typed marker");
  console.log(`[e2e] PASS: real .md file on disk at ${mdPath} with expected content`);

  // --- Scenario 2: edit it, confirm the file updates. ---
  const edited = `${marker}\nedited via Electron`;
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(edited);
  await page.waitForTimeout(2500);

  assert(fs.readFileSync(mdPath, "utf8") === edited, "on-disk file should reflect the edit");
  console.log("[e2e] PASS: editing in the Electron app updated the real file on disk");

  // --- Scenario 3: list screen (store.list() + per-row store.read(), both
  // proxied over IPC) renders a preview derived from the real file. ---
  await page.click("#btn-quki-list");
  await page.waitForSelector("#view-list:not([hidden])");
  await page.waitForFunction(() => {
    const preview = document.querySelector(".list-row-preview");
    return !!preview && preview.textContent !== "…";
  });
  const previewText = await page.textContent(".list-row-preview");
  assert(!!previewText && previewText.includes("Electron e2e proof"), `list preview should reflect the file body, got: ${previewText}`);
  console.log(`[e2e] PASS: list screen rendered a real preview over IPC: "${previewText}"`);

  await page.click("#view-list .back-btn");
  await page.waitForSelector("#view-editor:not([hidden])");

  // --- Scenario 4: settings -> trash navigation, both backed by the same
  // IPC store; trash starts empty. ---
  await page.click("#btn-settings");
  await page.waitForSelector("#view-settings:not([hidden])");
  await page.click(".trash-btn");
  await page.waitForSelector("#view-trash:not([hidden])");
  const trashEmptyText = await page.textContent(".empty-state");
  assert(trashEmptyText === "No notes in Trash.", `trash should start empty, got: ${trashEmptyText}`);
  console.log("[e2e] PASS: trash screen opened over IPC and correctly shows empty");

  await page.click("#view-trash .back-btn");
  await page.waitForSelector("#view-settings:not([hidden])");
  await page.click("#view-settings .back-btn");
  await page.waitForSelector("#view-editor:not([hidden])");

  await app.close();

  // --- Scenario 5: restart the app (a real process restart, not a page
  // reload) and confirm the edited content survives - proving the file on
  // disk is the real source of truth, not in-memory state. ---
  ({ app, page } = await launch(storageDir));
  const bodyAfterRestart = await readEditorBody(page);
  assert(
    bodyAfterRestart === edited,
    `editor should reload the most-recently-modified QuKi from disk after a real process restart, got: ${bodyAfterRestart}`,
  );
  console.log("[e2e] PASS: content survived a real Electron process restart (loaded from disk, not memory)");

  // --- Scenario 6: delete via the editor's Delete button moves the real
  // file into .trash/ on disk; the trash screen then shows it and restoring
  // it moves the real file back. ---
  await page.click("#btn-delete");
  await page.waitForTimeout(300);

  mdFiles = fs.readdirSync(storageDir).filter((f) => f.endsWith(".md"));
  assert(mdFiles.length === 0, `expected no .md files left in the root after delete, found: ${mdFiles.join(", ")}`);
  const trashDir = path.join(storageDir, ".trash");
  const trashedFiles = fs.readdirSync(trashDir).filter((f) => f.endsWith(".md"));
  assert(trashedFiles.length === 1, `expected exactly one .md file in ${trashDir}, found: ${trashedFiles.join(", ")}`);
  assert(fs.readFileSync(path.join(trashDir, trashedFiles[0]!), "utf8") === edited, "trashed file should retain its content");
  console.log("[e2e] PASS: Delete moved the real file into .trash/ on disk");

  await page.click("#btn-settings");
  await page.waitForSelector("#view-settings:not([hidden])");
  await page.click(".trash-btn");
  await page.waitForSelector("#view-trash:not([hidden])");
  await page.waitForFunction(() => document.querySelectorAll("#view-trash .list-row").length === 1);

  await page.click("#view-trash .list-row-content");
  // Restoring asks for confirmation first (BEHAVIOR_SPEC.md §6: "Restore note?").
  await page.waitForSelector(".confirm-overlay:not([hidden])");
  const confirmTitle = await page.textContent(".confirm-title");
  assert(confirmTitle === "Restore note?", `expected the restore confirmation dialog, got title: ${confirmTitle}`);
  await page.click(".confirm-confirm");

  await page.waitForSelector("#view-settings:not([hidden])");

  const restoredFiles = fs.readdirSync(storageDir).filter((f) => f.endsWith(".md"));
  assert(restoredFiles.length === 1, `expected the restored .md file back in the root, found: ${restoredFiles.join(", ")}`);
  const trashDirAfterRestore = fs.readdirSync(trashDir).filter((f) => f.endsWith(".md"));
  assert(trashDirAfterRestore.length === 0, "expected .trash/ to be empty again after restore");
  console.log("[e2e] PASS: restoring from the Trash screen moved the real file back on disk");

  await app.close();
  fs.rmSync(storageDir, { recursive: true, force: true });
}

main()
  .then(() => {
    console.log("[e2e] ALL ELECTRON SCENARIOS PASSED");
    process.exit(0);
  })
  .catch((err: unknown) => {
    console.error("[e2e] FAILED:", err);
    process.exit(1);
  });
