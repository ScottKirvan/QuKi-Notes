import { chromium, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

const SENTINEL_TEXT = "SENTINEL-BODY-TEXT-e2e-4417";
const SENTINEL_FILE = "sentinel-private-name";
// Set only to take screenshots of the Settings entry (see the PR); the assertions do not depend on them.
const SHOT_DIR = process.env.QUKI_FAILURELOG_SHOT_DIR;
const SHOT_SCHEME = process.env.QUKI_FAILURELOG_SCHEME === "light" ? "light" : "dark";

async function openFailureLog(page: Page): Promise<string> {
  await page.click("#btn-settings");
  await page.locator(".view:not([hidden]) .failure-log-btn").click();
  await page.locator(".failure-log-panel:not([hidden])").waitFor();
  await page.waitForFunction(() => (document.querySelector(".failure-log-text")?.textContent ?? "") !== "");
  return (await page.textContent(".failure-log-text")) ?? "";
}

async function closeSettings(page: Page): Promise<void> {
  await page.click("#view-settings .back-btn");
  await page.waitForSelector("#view-editor:not([hidden])");
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-failure-log] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    // --- Scenario 1: the save-conflict path (rule 17) is recorded, with no text. ---
    {
      const context = await browser.newContext();
      const page = await context.newPage();
      await page.goto(url);
      await page.waitForSelector(".cm-content");

      const empty = await openFailureLog(page);
      assert(empty === "No failures recorded.", `a fresh install should have an empty log, got: ${empty}`);
      await closeSettings(page);

      await page.click(".cm-content");
      await page.keyboard.type(`first ${SENTINEL_TEXT}`);
      await page.waitForTimeout(2600);
      await page.evaluate(async () => {
        const root = await navigator.storage.getDirectory();
        const dir = await root.getDirectoryHandle("quki");
        for await (const [name, handle] of dir as unknown as AsyncIterable<[string, FileSystemHandle]>) {
          if (!name.endsWith(".md")) continue;
          const w = await (handle as FileSystemFileHandle).createWritable();
          await w.write("changed by another program");
          await w.close();
        }
      });
      await page.keyboard.type(" and more");
      await page.waitForSelector("#save-status:not([hidden])", { timeout: 6000 });
      const banner = await page.textContent("#save-status");
      assert(/Could not save — it changed elsewhere/.test(banner ?? ""), `the conflict banner must be unchanged, got: ${banner}`);

      const log = await openFailureLog(page);
      assert(/\[conflict\] save conflict=modified/.test(log), `the conflict should be logged, got:\n${log}`);
      assert(!log.includes(SENTINEL_TEXT), "the log must not contain QuKi text");
      console.log("[e2e-failure-log] PASS: a save conflict is logged without QuKi text");
      await context.close();
    }

    // --- Scenario 2: failed save, failed read, uncaught error, copy, clear. ---
    {
      const context = await browser.newContext({ viewport: { width: 420, height: 800 }, colorScheme: SHOT_SCHEME });
      await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: url });
      const page = await context.newPage();
      await page.goto(url);
      await page.waitForSelector(".cm-content");

      // A dropped-in file with a private name, already in the folder.
      await page.evaluate(
        async ({ file, text }) => {
          const root = await navigator.storage.getDirectory();
          const dir = await root.getDirectoryHandle("quki", { create: true });
          const handle = await dir.getFileHandle(`${file}.md`, { create: true });
          const w = await handle.createWritable();
          await w.write(text);
          await w.close();
        },
        { file: SENTINEL_FILE, text: SENTINEL_TEXT },
      );
      await page.reload();
      await page.waitForSelector(".cm-content");

      // A failing save: every write throws, with a message that names the file and holds the text.
      await page.evaluate(
        ({ file, text }) => {
          Object.defineProperty(FileSystemFileHandle.prototype, "createWritable", {
            configurable: true,
            value: () => {
              throw new DOMException(`could not write ${file}.md ${text}`, "QuotaExceededError");
            },
          });
        },
        { file: SENTINEL_FILE, text: SENTINEL_TEXT },
      );
      await page.click(".cm-content");
      await page.keyboard.type(`typed ${SENTINEL_TEXT}`);
      await page.waitForSelector("#save-status:not([hidden])", { timeout: 6000 });
      const banner = await page.textContent("#save-status");
      assert(
        banner === "Could not save — an unexpected error occurred. Your latest edits have not been written to disk.",
        `the failed-save banner must be unchanged, got: ${banner}`,
      );

      // A failing read of the dropped-in file, while the list loads.
      await page.evaluate(
        ({ file, text }) => {
          Object.defineProperty(FileSystemFileHandle.prototype, "getFile", {
            configurable: true,
            value: () => {
              throw new DOMException(`could not read ${file}.md ${text}`, "NotReadableError");
            },
          });
        },
        { file: SENTINEL_FILE, text: SENTINEL_TEXT },
      );
      await page.click("#btn-quki-list");
      await page.waitForSelector("#view-list:not([hidden])");
      await page.waitForTimeout(500);
      await page.click("#view-list .back-btn");
      await page.waitForSelector("#view-editor:not([hidden])");

      // An uncaught exception and an unhandled rejection.
      await page.evaluate(
        ({ file, text }) => {
          setTimeout(() => {
            throw new TypeError("widget.render is not a function");
          }, 0);
          setTimeout(() => {
            throw new TypeError(`bad value while handling ${file}.md ${text}`);
          }, 5);
          void Promise.reject(new RangeError("Maximum call stack size exceeded"));
        },
        { file: SENTINEL_FILE, text: SENTINEL_TEXT },
      );
      await page.waitForTimeout(300);

      const log = await openFailureLog(page);
      assert(/\[save\] save .*QuotaExceededError/.test(log), `the failed save should be logged, got:\n${log}`);
      assert(/\[storage\] (stat|readText) .*NotReadableError/.test(log), `the failed read should be logged, got:\n${log}`);
      assert(/\[uncaught\] window-error TypeError "widget.render is not a function"/.test(log), `the uncaught error should be logged, got:\n${log}`);
      assert(/\[unhandled-rejection\] promise RangeError "Maximum call stack size exceeded"/.test(log), `the rejection should be logged, got:\n${log}`);
      assert(/\[uncaught\] window-error TypeError( at [^ ]+)? \|/.test(log), `the app-written uncaught message should be dropped, got:
${log}`);
      assert(/\| v\d+\.\d+\.\d+ web opfs renderer/.test(log), `entries should carry version, platform and backend, got:\n${log}`);
      assert((log.match(/\[save\]/g) ?? []).length === 1, `a save retried against the same failure should be logged once, got:\n${log}`);
      const raw = await page.evaluate(() => localStorage.getItem("quki.failureLog") ?? "");
      for (const secret of [SENTINEL_TEXT, SENTINEL_FILE]) {
        assert(!log.includes(secret) && !raw.includes(secret), `the log must never contain "${secret}"`);
      }
      const opfsNames = await page.evaluate(async () => {
        const root = await navigator.storage.getDirectory();
        const names: string[] = [];
        for await (const [name] of root as unknown as AsyncIterable<[string, FileSystemHandle]>) names.push(name);
        const dir = await root.getDirectoryHandle("quki");
        for await (const [name] of dir as unknown as AsyncIterable<[string, FileSystemHandle]>) names.push(name);
        return names;
      });
      assert(!opfsNames.some((n) => /fail|log/i.test(n)), `the log must not be kept in the QuKi folder, found: ${opfsNames}`);
      console.log("[e2e-failure-log] PASS: save, read, uncaught and rejected failures are logged with no text or filename");

      if (SHOT_DIR) {
        await page.locator(".failure-log-panel").scrollIntoViewIfNeeded();
        const light = (await page.evaluate(() => document.body.className)).includes("theme-light");
        await page.screenshot({ path: `${SHOT_DIR}/failure-log-${light ? "light" : "dark"}.png` });
      }

      await page.click(".failure-log-copy-btn");
      await page.waitForFunction(() => document.querySelector(".toast")?.textContent === "Copied to clipboard.");
      const clipboard = await page.evaluate(() => navigator.clipboard.readText());
      assert(clipboard.split("\r\n").join("\n") === log, `Copy should put the whole log on the clipboard`);
      console.log("[e2e-failure-log] PASS: Copy puts the log on the clipboard");

      await page.click(".failure-log-clear-btn");
      await page.waitForFunction(() => document.querySelector(".failure-log-text")?.textContent === "No failures recorded.");
      assert((await page.evaluate(() => localStorage.getItem("quki.failureLog"))) === null, "Clear should remove the stored log");
      console.log("[e2e-failure-log] PASS: Clear empties the log");
      await context.close();
    }
    console.log("[e2e-failure-log] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((err: unknown) => {
  console.error("[e2e-failure-log] FAILED:", err);
  process.exit(1);
});
