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

  // main.ts suppresses the default Electron menu only when app.isPackaged -
  // this e2e run always launches the unpackaged dist/main.js directly, so
  // the default dev menu (Reload, Toggle DevTools, ...) must still be
  // present here. This only proves the gate is a no-op in dev, not that a
  // packaged build actually suppresses it - that would need a real
  // electron-builder distributable, which this run does not build.
  const hasDefaultMenuInDev = await app.evaluate(({ Menu }) => Menu.getApplicationMenu() !== null);
  assert(hasDefaultMenuInDev, "the default Electron menu should still be present in an unpackaged/dev run");
  console.log("[e2e] PASS: default menu is untouched in dev (app.isPackaged is false) - packaged suppression not exercised by this run");

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

  // --- Scenario 5: a link opened from the app's own content (or the Help
  // screen's Documentation/Discord/GitHub rows, all rendered as
  // target="_blank" anchors - see reveal/widgets.ts, screens/aboutDialog.ts)
  // must not open inside the app as a second Electron window
  // (electron/src/main.ts's attachExternalLinkHandling / setWindowOpenHandler).
  // window.open() is exactly what Chromium's own target="_blank" handling
  // triggers under the hood, so this exercises the same main-process hook a
  // real link click would, without depending on any specific page markup. ---
  const windowCountBeforeOpen = app.windows().length;
  await page.evaluate(() => window.open("https://example.com/quki-e2e-window-open-test", "_blank"));
  await page.waitForTimeout(500);
  assert(
    app.windows().length === windowCountBeforeOpen,
    `window.open() on an external URL must not create a new Electron window (setWindowOpenHandler should deny it), had ${windowCountBeforeOpen}, now ${app.windows().length}`,
  );
  console.log("[e2e] PASS: window.open() to an external URL did not open a second Electron window");

  // Best-effort, non-asserted signal that the denied window.open actually
  // reached shell.openExternal and handed off to a real OS browser, not
  // just that it was blocked in-app - not asserted on, since whether this
  // sandbox has a default browser registered at all is environment-
  // dependent, not something main.ts's code controls.
  try {
    const { execSync } = await import("node:child_process");
    const before = execSync('tasklist /fi "IMAGENAME eq msedge.exe"').toString();
    await page.evaluate(() => window.open("https://example.com/quki-e2e-real-browser-check", "_blank"));
    await page.waitForTimeout(1500);
    const after = execSync('tasklist /fi "IMAGENAME eq msedge.exe"').toString();
    console.log(
      after.length > before.length
        ? "[e2e] INFO: a real msedge.exe process appeared after the denied window.open - shell.openExternal reached the OS browser"
        : "[e2e] INFO: could not confirm a new OS browser process via tasklist (no default browser registered here, or it uses a different process name) - not asserted on",
    );
  } catch (err) {
    console.log(`[e2e] INFO: skipped the best-effort OS-browser process check (${err instanceof Error ? err.message : String(err)})`);
  }

  // --- Scenario 6: a top-level navigation away from the app's own origin
  // (the other way content could leave the app, distinct from window.open)
  // must also be blocked - attachExternalLinkHandling's will-navigate guard.
  // Triggered via a real anchor click, exactly as a real link click in the
  // app's own content would. noWaitAfter is required here: Playwright's
  // default post-click behavior waits for the navigation the click looks
  // like it should cause, but main.ts's will-navigate handler cancels that
  // navigation at the Electron main-process level in a way Playwright's own
  // wait never observes as resolved, hanging the click until its 30s
  // timeout - this is precisely Playwright's documented exceptional case
  // for the option ("navigating to inaccessible pages"). ---
  await page.evaluate(() => {
    const a = document.createElement("a");
    a.id = "quki-e2e-will-navigate-test";
    a.href = "https://example.com/quki-e2e-will-navigate-test";
    a.textContent = "external";
    document.body.appendChild(a);
  });
  const urlBeforeNavigate = page.url();
  await page.click("#quki-e2e-will-navigate-test", { noWaitAfter: true });
  await page.waitForTimeout(500);
  assert(
    page.url() === urlBeforeNavigate,
    `navigating the window itself to an external origin must be blocked by will-navigate, window is now at ${page.url()}`,
  );
  console.log("[e2e] PASS: navigating the window to an external URL was blocked (will-navigate denied it)");
  await page.evaluate(() => document.getElementById("quki-e2e-will-navigate-test")?.remove());

  // --- Scenario 7: quitting the app must not lose an edit still sitting in
  // the 2s auto-save debounce - electron/src/main.ts's attachQuitFlush must
  // hold the window open until the renderer's pending save actually lands
  // on disk (project/src/main.ts's onFlushBeforeQuit wiring). Closing the
  // real BrowserWindow (not calling app.close(), which is Playwright's own
  // teardown, not a signal the app's own close handler necessarily sees the
  // same way) and waiting for the whole app to actually terminate is what
  // proves the handshake, not just that the call was made.
  //
  // The edit is dispatched straight at the CodeMirror view (window.qukiView,
  // also used by readEditorBody above) rather than via page.click/keyboard -
  // scenario 6's will-navigate cancellation above leaves Playwright's own
  // per-page navigation-lifecycle tracking permanently believing a
  // navigation is still pending (a known rough edge of cancelling
  // navigation at the Electron main-process level under Playwright, not
  // anything this app's code controls), which hangs every subsequent
  // page.click on this page. The view's updateListener (src/main.ts) calls
  // autoSave.notifyChange() on any docChanged update regardless of how the
  // change was made, so this exercises the identical auto-save path a real
  // keystroke would. ---
  const unflushedMarker = `${edited}\nunflushed at quit ${Date.now()}`;
  await page.evaluate((text) => {
    const view = (window as unknown as { qukiView: { dispatch(spec: unknown): void; state: { doc: { length: number } } } })
      .qukiView;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
  }, unflushedMarker);
  // Deliberately no wait for the 2s auto-save debounce: close immediately
  // while the save is still only pending, so it's the quit handshake - not
  // the debounce - that has to get it onto disk.
  await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0]!.close());
  await app.waitForEvent("close");
  assert(
    fs.readFileSync(mdPath, "utf8") === unflushedMarker,
    "quitting immediately after an edit should still flush it to disk before the app actually closes",
  );
  console.log("[e2e] PASS: quit-time flush handshake saved a still-pending edit before the app closed");

  // --- Scenario 8: restart the app (a real process restart, not a page
  // reload) and confirm the edited content survives - proving the file on
  // disk is the real source of truth, not in-memory state. ---
  ({ app, page } = await launch(storageDir));
  const bodyAfterRestart = await readEditorBody(page);
  assert(
    bodyAfterRestart === edited,
    `editor should reload the most-recently-modified QuKi from disk after a real process restart, got: ${bodyAfterRestart}`,
  );
  console.log("[e2e] PASS: content survived a real Electron process restart (loaded from disk, not memory)");

  // --- Scenario 9: delete via the editor's Delete button moves the real
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
