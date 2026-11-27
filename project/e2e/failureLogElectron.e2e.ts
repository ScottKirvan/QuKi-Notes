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

const SENTINEL_TEXT = "SENTINEL-BODY-TEXT-electron-8812";
const SENTINEL_FILE = "sentinel-private-name";

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
}

// See e2e/electron.e2e.ts for why ELECTRON_RUN_AS_NODE must not be inherited.
const baseChildEnv = { ...process.env, QUKI_ELECTRON_DIR: "" };
delete baseChildEnv.ELECTRON_RUN_AS_NODE;

async function launch(storageDir: string, userDataDir: string): Promise<{ app: ElectronApplication; page: Page }> {
  const env: NodeJS.ProcessEnv = { ...baseChildEnv, QUKI_ELECTRON_DIR: storageDir, QUKI_ELECTRON_USERDATA_DIR: userDataDir };
  const app = await electron.launch({ executablePath: electronExecutablePath, args: [electronMain], env });
  const page = await app.firstWindow();
  await page.waitForSelector(".cm-content");
  return { app, page };
}

async function main(): Promise<void> {
  if (!fs.existsSync(electronMain)) {
    throw new Error(`${electronMain} not found - run "npm run build" in project/electron first`);
  }

  const storageDir = fs.mkdtempSync(path.join(os.tmpdir(), `quki-${SENTINEL_FILE}-e2e-storage-`));
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "quki-failurelog-e2e-userdata-"));
  // A regular file where the sidecar folder belongs makes every first save fail
  // inside the main process (the folder cannot be created), on every OS and
  // without depending on file permissions.
  fs.writeFileSync(path.join(storageDir, ".meta"), "not a folder");

  const { app, page } = await launch(storageDir, userDataDir);
  try {
    await page.click(".cm-content");
    await page.keyboard.type(`typed ${SENTINEL_TEXT}`);
    await page.waitForSelector("#save-status:not([hidden])", { timeout: 8000 });
    const banner = await page.textContent("#save-status");
    assert(
      banner === "Could not save — an unexpected error occurred. Your latest edits have not been written to disk.",
      `the failed-save banner must be unchanged, got: ${banner}`,
    );

    const logFile = path.join(userDataDir, "failure-log.json");
    for (let i = 0; i < 50 && !fs.existsSync(logFile); i++) await page.waitForTimeout(100);
    assert(fs.existsSync(logFile), "the main process should have written failure-log.json in userData");
    assert(!fs.existsSync(path.join(storageDir, "failure-log.json")), "the log must not be written into the QuKi folder");
    assert(!fs.existsSync(path.join(storageDir, ".quki")), "the log must not create .quki/ in the QuKi folder");

    const entries = JSON.parse(fs.readFileSync(logFile, "utf8")) as Array<Record<string, string>>;
    const fromMain = entries.find((e) => e.process === "main" && e.kind === "storage");
    assert(fromMain !== undefined, `a storage failure recorded by the main process was expected, got: ${JSON.stringify(entries)}`);
    assert(/^(EEXIST|ENOTDIR)$/.test(fromMain.code ?? ""), `the main-process entry should carry the OS error code, got: ${JSON.stringify(fromMain)}`);
    assert(fromMain.backend === "electron-fs" && fromMain.platform === process.platform, `the entry should name backend and platform, got: ${JSON.stringify(fromMain)}`);
    assert(entries.some((e) => e.process === "renderer" && e.kind === "save" && e.op === "save"), "the renderer's failed save should be logged too");

    await page.click("#btn-settings");
    await page.locator(".view:not([hidden]) .failure-log-btn").click();
    await page.waitForFunction(() => (document.querySelector(".failure-log-text")?.textContent ?? "").includes("[storage]"));
    const text = (await page.textContent(".failure-log-text")) ?? "";
    assert(/\[storage\] \S+ .*electron-fs main/.test(text), `Settings should show the main-process entry, got:\n${text}`);
    assert(/\[save\] save .*electron-ipc renderer/.test(text), `Settings should show the renderer entry, got:\n${text}`);

    const onDisk = fs.readFileSync(logFile, "utf8");
    for (const secret of [SENTINEL_TEXT, SENTINEL_FILE, storageDir, userDataDir]) {
      assert(!onDisk.includes(secret) && !text.includes(secret), `the log must never contain "${secret}"`);
    }
    console.log("[e2e-failure-log-electron] PASS: a main-process storage failure and the renderer's failed save are logged in userData, without text, filename or path");

    await page.click(".failure-log-clear-btn");
    await page.waitForFunction(() => document.querySelector(".failure-log-text")?.textContent === "No failures recorded.");
    assert(!fs.existsSync(logFile), "Clear should remove the log file");
    console.log("[e2e-failure-log-electron] PASS: Clear removes the log file");
  } finally {
    await app.close();
    fs.rmSync(storageDir, { recursive: true, force: true });
    fs.rmSync(userDataDir, { recursive: true, force: true });
  }
  console.log("[e2e-failure-log-electron] ALL SCENARIOS PASSED");
}

main().catch((err: unknown) => {
  console.error("[e2e-failure-log-electron] FAILED:", err);
  process.exit(1);
});
