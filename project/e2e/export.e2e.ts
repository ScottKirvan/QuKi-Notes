import * as fs from "node:fs";
import * as zlib from "node:zlib";

import { chromium, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

async function typeInEditor(page: Page, text: string): Promise<void> {
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(text);
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-export] serving dist/ at ${url}`);
  const browser = await chromium.launch();

  try {
    // --- Settings -> Export on the plain web build downloads a gzipped
    // tar containing the current QuKi's content (core's exportLibrary(),
    // STORAGE_CONTRACT.md's "Export everything" / web-to-desktop migration
    // path). ---
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    const marker = `export e2e proof ${Date.now()}`;
    await typeInEditor(page, marker);
    // Well inside the auto-save debounce - proves Export flushes first,
    // the same guarantee Send already has (BEHAVIOR_SPEC.md §4).
    await page.click("#btn-settings");
    await page.locator(".view:not([hidden]) .export-btn").waitFor();

    const disabledBeforeClick = await page.getAttribute(".view:not([hidden]) .export-btn", "disabled");
    assert(disabledBeforeClick === null, "Export button should be enabled");

    const [download] = await Promise.all([page.waitForEvent("download"), page.click(".view:not([hidden]) .export-btn")]);

    const suggestedName = download.suggestedFilename();
    assert(/^quki-export-\d{8}-\d{6}\.tar\.gz$/.test(suggestedName), `expected a timestamped quki-export-*.tar.gz filename, got "${suggestedName}"`);

    const downloadPath = await download.path();
    assert(downloadPath !== null, "download should have saved to a real temp path");
    const gunzipped = zlib.gunzipSync(fs.readFileSync(downloadPath));
    assert(gunzipped.includes(marker), `exported archive should contain the current QuKi's body ("${marker}")`);
    console.log(`[e2e-export] PASS: Export downloaded "${suggestedName}" containing the flushed QuKi body`);

    await context.close();
    console.log("[e2e-export] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-export] FAILED:", err);
    process.exit(1);
  });
