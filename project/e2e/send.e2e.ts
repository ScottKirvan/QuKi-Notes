import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
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

function mkTempStorageDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "quki-send-e2e-"));
}

// See e2e/electron.e2e.ts for why ELECTRON_RUN_AS_NODE must not be inherited.
const baseChildEnv = { ...process.env, QUKI_ELECTRON_DIR: "" };
delete baseChildEnv.ELECTRON_RUN_AS_NODE;

/**
 * QUKI_TEST_FORCE_PLATFORM (see electron/src/preload.ts) lets this proof
 * exercise the Linux clipboard path and the Windows disabled-button
 * gating for real, on whatever OS actually runs the test - the same
 * override-seam pattern already used for the storage-location picker and
 * temp storage dir elsewhere in this suite.
 */
async function launch(storageDir: string, forcePlatform?: string): Promise<{ app: ElectronApplication; page: Page }> {
  const env: NodeJS.ProcessEnv = { ...baseChildEnv, QUKI_ELECTRON_DIR: storageDir };
  if (forcePlatform) env.QUKI_TEST_FORCE_PLATFORM = forcePlatform;
  else delete env.QUKI_TEST_FORCE_PLATFORM;
  const app = await electron.launch({
    executablePath: electronExecutablePath,
    args: [electronMain],
    env,
  });
  const page = await app.firstWindow();
  await page.waitForSelector(".cm-content");
  return { app, page };
}

/** Reads the real native OS clipboard via Electron's main-process clipboard module - not navigator.clipboard, so this proves the actual OS clipboard, not just what the page believes it wrote. */
async function readOsClipboard(app: ElectronApplication): Promise<string> {
  return app.evaluate(({ clipboard }) => clipboard.readText());
}

async function typeInEditor(page: Page, text: string): Promise<void> {
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(text);
}

async function main(): Promise<void> {
  if (!fs.existsSync(electronMain)) {
    throw new Error(`${electronMain} not found - run "npm run build" in project/electron first`);
  }

  // --- Scenario 1: win32 has no real native share sheet (see the
  // KNOWN DEFICIENCY comment in src/main.ts and quki-rewrite-path.md) - as
  // an accepted, deliberate stand-in, it now uses the same clipboard path
  // already built for Linux rather than staying disabled. Prove it actually
  // writes to the real OS clipboard, the same rigor as the Linux case. ---
  {
    const storageDir = mkTempStorageDir();
    const { app, page } = await launch(storageDir, "win32");

    const disabled = await page.getAttribute("#btn-send", "disabled");
    assert(disabled === null, "Send button should be enabled on win32 (clipboard stand-in)");

    const marker = `Send e2e proof win32 ${Date.now()}`;
    await typeInEditor(page, marker);
    await page.click("#btn-send");

    await page.waitForFunction(() => document.querySelector(".toast")?.textContent === "Copied to clipboard.");
    const clipboardContent = await readOsClipboard(app);
    assert(clipboardContent === marker, `real OS clipboard should contain the sent body on win32, got: "${clipboardContent}"`);
    console.log(`[e2e-send] PASS: win32 Send (clipboard stand-in) wrote the real OS clipboard: "${clipboardContent}"`);

    await app.close();
    fs.rmSync(storageDir, { recursive: true, force: true });
  }

  // --- Scenario 1b: a platform with no built Send destination at all
  // (neither linux nor win32) stays disabled, and forcing a click must not
  // touch the clipboard - the "no silent fallback" guarantee for whatever
  // platform genuinely isn't supported yet. ---
  {
    const storageDir = mkTempStorageDir();
    const { app, page } = await launch(storageDir, "darwin");

    const disabled = await page.getAttribute("#btn-send", "disabled");
    assert(disabled !== null, "Send button should stay disabled on a platform with no built Send destination (darwin)");
    console.log("[e2e-send] PASS: Send button is disabled on darwin (no destination built for it)");

    await app.close();
    fs.rmSync(storageDir, { recursive: true, force: true });
  }

  // --- Scenario 2: on Linux, Send is enabled; sending an empty QuKi shows
  // the exact empty-body message and does not touch the clipboard. ---
  {
    const storageDir = mkTempStorageDir();
    const { app, page } = await launch(storageDir, "linux");

    const disabled = await page.getAttribute("#btn-send", "disabled");
    assert(disabled === null, "Send button should be enabled on linux");

    // Prime the clipboard with a known sentinel so we can tell "unchanged" from "changed".
    await app.evaluate(({ clipboard }, text) => clipboard.writeText(text), "sentinel-before-send");

    await page.click("#btn-send");
    await page.waitForFunction(() => document.querySelector(".toast")?.textContent === "Nothing to send — write something first.");
    const emptyToast = await page.textContent(".toast");
    assert(emptyToast === "Nothing to send — write something first.", `expected exact empty-body message, got: "${emptyToast}"`);

    const clipboardAfterEmptyGuard = await readOsClipboard(app);
    assert(
      clipboardAfterEmptyGuard === "sentinel-before-send",
      `empty-body guard must not touch the clipboard, got: "${clipboardAfterEmptyGuard}"`,
    );
    console.log("[e2e-send] PASS: empty body shows the exact guard message and does not touch the clipboard");

    await app.close();
    fs.rmSync(storageDir, { recursive: true, force: true });
  }

  // --- Scenario 3: sending real content copies it to the real OS
  // clipboard and shows the success toast (2s). Also proves flush-before-
  // send: Send is clicked immediately after typing, well inside the 2s
  // auto-save debounce, so only an explicit flush() (not the debounce)
  // could have gotten this content onto disk / into what gets sent. ---
  {
    const storageDir = mkTempStorageDir();
    const { app, page } = await launch(storageDir, "linux");

    const marker = `Send e2e proof ${Date.now()}`;
    await typeInEditor(page, marker);
    // No wait here - clicking well inside the 2s debounce window is the point.
    await page.click("#btn-send");

    await page.waitForFunction(() => document.querySelector(".toast")?.textContent === "Copied to clipboard.");
    const successToast = await page.textContent(".toast");
    assert(successToast === "Copied to clipboard.", `expected exact success message, got: "${successToast}"`);

    const clipboardContent = await readOsClipboard(app);
    assert(clipboardContent === marker, `real OS clipboard should contain the sent body, got: "${clipboardContent}"`);
    console.log(`[e2e-send] PASS: real OS clipboard contains the sent QuKi body: "${clipboardContent}"`);

    const mdFiles = fs.readdirSync(storageDir).filter((f) => f.endsWith(".md"));
    assert(mdFiles.length === 1, `expected exactly one .md file after send, found: ${mdFiles.join(", ")}`);
    const onDisk = fs.readFileSync(path.join(storageDir, mdFiles[0]!), "utf8");
    assert(onDisk === marker, `Send must flush to disk first - on-disk content should equal the typed marker, got: "${onDisk}"`);
    console.log("[e2e-send] PASS: Send flushed the very recent edit to disk before sending (not a stale copy)");

    await app.close();
    fs.rmSync(storageDir, { recursive: true, force: true });
  }
}

main()
  .then(() => {
    console.log("[e2e-send] ALL SEND SCENARIOS PASSED");
    process.exit(0);
  })
  .catch((err: unknown) => {
    console.error("[e2e-send] FAILED:", err);
    process.exit(1);
  });
