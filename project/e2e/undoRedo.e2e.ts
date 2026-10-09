import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type WindowWithQukiView = typeof window & {
  qukiView: { state: { doc: { toString(): string } } };
};

// CodeMirror merges edits made within 500ms of each other into one undo step;
// waiting past that keeps each step in these scenarios separate.
const PAST_UNDO_GROUPING_MS = 700;

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

async function waitForBody(page: Page, body: string): Promise<void> {
  await page.waitForFunction((expected) => (window as WindowWithQukiView).qukiView.state.doc.toString() === expected, body);
}

async function openFreshEditor(browser: Browser, url: string): Promise<{ page: Page; done: () => Promise<void> }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  return {
    page,
    done: async () => {
      assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
      await context.close();
    },
  };
}

async function undoDoesNotReachIntoThePreviousQuKiAfterNew(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-undo:new-quki]";
  const { page, done } = await openFreshEditor(browser, url);

  await page.click(".cm-content");
  await page.keyboard.type("Undo QuKi A");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);
  await page.click("#btn-new-quki");
  await waitForBody(page, "");

  await page.click(".cm-content");
  await page.keyboard.press("Control+z");
  await page.waitForTimeout(200);
  const body = await editorBody(page);
  assert(body === "", `${tag} undo in a new QuKi must not bring back the previous QuKi's text, got "${body}"`);
  console.log(`${tag} PASS: undo in a new QuKi stays empty`);
  await done();
}

async function undoDoesNotReachIntoThePreviousQuKiAfterOpeningOne(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-undo:opened-quki]";
  const { page, done } = await openFreshEditor(browser, url);

  await page.click(".cm-content");
  await page.keyboard.type("Undo QuKi A");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);
  await page.click("#btn-new-quki");
  await waitForBody(page, "");
  await page.click(".cm-content");
  await page.keyboard.type("Undo QuKi B");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);

  await page.click("#btn-quki-list");
  const list = page.locator("#view-list");
  await list.locator(".list-row-preview", { hasText: "Undo QuKi A" }).click({ timeout: 5000 });
  await waitForBody(page, "Undo QuKi A");

  await page.click(".cm-content");
  await page.keyboard.press("Control+z");
  await page.waitForTimeout(200);
  const body = await editorBody(page);
  assert(body === "Undo QuKi A", `${tag} undo right after opening a QuKi must leave it unchanged, got "${body}"`);
  console.log(`${tag} PASS: undo right after opening a QuKi leaves it unchanged`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-undo] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await undoDoesNotReachIntoThePreviousQuKiAfterNew(browser, url);
    await undoDoesNotReachIntoThePreviousQuKiAfterOpeningOne(browser, url);
    console.log("[e2e-undo] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-undo] FAILED:", err);
    process.exit(1);
  });
