import { chromium, type Browser, type BrowserContext, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

async function typeInEditor(page: Page, text: string): Promise<void> {
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(text);
}

/**
 * Stubs navigator.share before the page's own scripts run, so main.ts's
 * `typeof navigator.share === "function"` check (src/main.ts's
 * sendCurrentQuKi) picks up the stub exactly the way it would a real
 * browser implementation. Real headless Chromium's Web Share support is
 * platform/OS-dependent and not something this suite controls, so this is
 * the only way to exercise both branches of webShare.ts's real behavior
 * deterministically end-to-end, on top of webShare.test.ts's unit coverage
 * of the same branches with a mocked shareApi.
 */
async function stubNavigatorShare(context: BrowserContext, behavior: "resolve" | "abort" | "unavailable"): Promise<void> {
  await context.addInitScript((behavior) => {
    (window as unknown as { __shareCalls: unknown[] }).__shareCalls = [];
    if (behavior === "unavailable") {
      // @ts-expect-error - deleting a lib.dom method for the test
      delete navigator.share;
      return;
    }
    navigator.share = (data: ShareData): Promise<void> => {
      (window as unknown as { __shareCalls: unknown[] }).__shareCalls.push(data);
      if (behavior === "abort") {
        const err = new DOMException("cancelled", "AbortError");
        return Promise.reject(err);
      }
      return Promise.resolve();
    };
  }, behavior);
}

async function shareCalls(page: Page): Promise<unknown[]> {
  return page.evaluate(() => (window as unknown as { __shareCalls: unknown[] }).__shareCalls);
}

async function toastText(page: Page): Promise<string | null> {
  const toast = page.locator(".toast");
  const hidden = await toast.isHidden();
  if (hidden) return null;
  return toast.textContent();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-web-send] serving dist/ at ${url}`);
  const browser: Browser = await chromium.launch();

  try {
    // --- Scenario 1: Send is enabled on the plain web build (previously
    // unconditionally disabled - see the KNOWN DEFICIENCY comment removed
    // from src/main.ts's Send wiring). ---
    {
      const context = await browser.newContext();
      const page = await context.newPage();
      await page.goto(url);
      await page.waitForSelector(".cm-content");

      const disabled = await page.getAttribute("#btn-send", "disabled");
      assert(disabled === null, "Send button should be enabled on the plain web build");
      console.log("[e2e-web-send] PASS: Send button is enabled on the plain web build");

      await context.close();
    }

    // --- Scenario 2: empty body shows the exact guard message and never
    // calls navigator.share. ---
    {
      const context = await browser.newContext();
      await stubNavigatorShare(context, "resolve");
      const page = await context.newPage();
      await page.goto(url);
      await page.waitForSelector(".cm-content");

      await page.click("#btn-send");
      await page.waitForFunction(() => document.querySelector(".toast")?.textContent === "Nothing to send — write something first.");
      assert((await shareCalls(page)).length === 0, "the empty-body guard must not call navigator.share");
      console.log("[e2e-web-send] PASS: empty body shows the guard message and never calls navigator.share");

      await context.close();
    }

    // --- Scenario 3: navigator.share available and resolving - the real
    // OS share sheet is its own feedback, so no app toast appears, matching
    // Android's native share sheet behavior. ---
    {
      const context = await browser.newContext();
      await stubNavigatorShare(context, "resolve");
      const page = await context.newPage();
      await page.goto(url);
      await page.waitForSelector(".cm-content");

      const marker = `web share e2e proof ${Date.now()}`;
      await typeInEditor(page, marker);
      await page.click("#btn-send");
      await page.waitForFunction((expected) => (window as unknown as { __shareCalls: { text: string }[] }).__shareCalls.length > 0 && (window as unknown as { __shareCalls: { text: string }[] }).__shareCalls[0]!.text === expected, marker);

      const calls = await shareCalls(page);
      assert(calls.length === 1, `expected exactly one navigator.share call, got ${calls.length}`);
      assert((calls[0] as { text: string }).text === marker, `navigator.share should receive the QuKi body, got ${JSON.stringify(calls[0])}`);

      await page.waitForTimeout(300);
      const toast = await toastText(page);
      assert(toast === null, `no app toast should appear when navigator.share succeeds - the share sheet is its own feedback, got "${toast}"`);
      console.log("[e2e-web-send] PASS: navigator.share is called with the QuKi body and no app toast is layered on top");

      await context.close();
    }

    // --- Scenario 4: navigator.share unavailable - falls back to the real
    // OS clipboard, same as the Electron desktop path. ---
    {
      const context = await browser.newContext();
      await context.grantPermissions(["clipboard-read", "clipboard-write"]);
      await stubNavigatorShare(context, "unavailable");
      const page = await context.newPage();
      await page.goto(url);
      await page.waitForSelector(".cm-content");

      const shareIsFunction = await page.evaluate(() => typeof navigator.share === "function");
      assert(!shareIsFunction, "test setup: navigator.share should be unavailable in this scenario");

      const marker = `web clipboard fallback e2e proof ${Date.now()}`;
      await typeInEditor(page, marker);
      await page.click("#btn-send");
      await page.waitForFunction(() => document.querySelector(".toast")?.textContent === "Copied to clipboard.");

      const clipboardContent = await page.evaluate(() => navigator.clipboard.readText());
      assert(clipboardContent === marker, `clipboard should contain the sent body, got: "${clipboardContent}"`);
      console.log("[e2e-web-send] PASS: with no navigator.share, Send falls back to the real clipboard and shows the copied toast");

      await context.close();
    }

    // --- Scenario 5: the person cancelling the share sheet (AbortError) is
    // a quiet no-op, not a "Send failed" error. ---
    {
      const context = await browser.newContext();
      await stubNavigatorShare(context, "abort");
      const page = await context.newPage();
      await page.goto(url);
      await page.waitForSelector(".cm-content");

      const marker = `web share cancel e2e proof ${Date.now()}`;
      await typeInEditor(page, marker);
      await page.click("#btn-send");
      await page.waitForFunction((expected) => (window as unknown as { __shareCalls: { text: string }[] }).__shareCalls.length > 0 && (window as unknown as { __shareCalls: { text: string }[] }).__shareCalls[0]!.text === expected, marker);

      await page.waitForTimeout(300);
      const toast = await toastText(page);
      assert(toast === null, `cancelling the share sheet must not show an error toast, got "${toast}"`);
      console.log("[e2e-web-send] PASS: cancelling the share sheet (AbortError) shows no error toast");

      await context.close();
    }

    console.log("[e2e-web-send] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-web-send] FAILED:", err);
    process.exit(1);
  });
