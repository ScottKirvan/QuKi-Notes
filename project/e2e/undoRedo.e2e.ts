import { chromium, type Browser, type Locator, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

type WindowWithQukiView = typeof window & {
  qukiView: { state: { doc: { toString(): string } }; contentDOM: HTMLElement };
};

// CodeMirror merges edits made within 500ms of each other into one undo step;
// waiting past that keeps each step in these scenarios separate.
const PAST_UNDO_GROUPING_MS = 700;

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

async function editorHasFocus(page: Page): Promise<boolean> {
  return page.evaluate(() => document.activeElement === (window as WindowWithQukiView).qukiView.contentDOM);
}

async function waitForBody(page: Page, body: string): Promise<void> {
  await page.waitForFunction((expected) => (window as WindowWithQukiView).qukiView.state.doc.toString() === expected, body);
}

function toolbarButton(page: Page, label: string): Locator {
  return page.locator(`.formatting-toolbar .toolbar-btn[aria-label="${label}"]`);
}

async function isDisabled(button: Locator): Promise<boolean> {
  const greyedOut = await button.evaluate((el) => el.getAttribute("aria-disabled") === "true" && getComputedStyle(el).opacity === "0.45");
  return greyedOut;
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

  await clickFirstLine(page);
  await page.keyboard.type("Undo QuKi A");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);
  await page.click("#btn-new-quki");
  await waitForBody(page, "");

  await clickFirstLine(page);
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

  await clickFirstLine(page);
  await page.keyboard.type("Undo QuKi A");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);
  await page.click("#btn-new-quki");
  await waitForBody(page, "");
  await clickFirstLine(page);
  await page.keyboard.type("Undo QuKi B");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);

  await page.click("#btn-quki-list");
  const list = page.locator("#view-list");
  await list.locator(".list-row-preview", { hasText: "Undo QuKi A" }).click({ timeout: 5000 });
  await waitForBody(page, "Undo QuKi A");

  await clickFirstLine(page);
  await page.keyboard.press("Control+z");
  await page.waitForTimeout(200);
  const body = await editorBody(page);
  assert(body === "Undo QuKi A", `${tag} undo right after opening a QuKi must leave it unchanged, got "${body}"`);
  console.log(`${tag} PASS: undo right after opening a QuKi leaves it unchanged`);
  await done();
}

async function toolbarUndoAndRedo(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-undo:toolbar]";
  const { page, done } = await openFreshEditor(browser, url);
  const undoBtn = toolbarButton(page, "Undo");
  const redoBtn = toolbarButton(page, "Redo");

  await clickFirstLine(page);
  await page.locator(".formatting-toolbar").waitFor({ state: "visible" });

  const labels = await page.locator(".formatting-toolbar .toolbar-btn").evaluateAll((els) => els.map((el) => el.getAttribute("aria-label")));
  assert(labels[0] === "Undo" && labels[1] === "Redo", `${tag} Undo and Redo must be the first two toolbar buttons, got ${labels.join(", ")}`);
  assert(labels[2] === "Bold", `${tag} Bold must follow Redo, got ${labels[2]}`);
  console.log(`${tag} PASS: Undo and Redo sit at the left edge of the toolbar`);

  assert(await isDisabled(undoBtn), `${tag} Undo must be disabled with nothing to undo`);
  assert(await isDisabled(redoBtn), `${tag} Redo must be disabled with nothing to redo`);

  await redoBtn.click({ force: true });
  assert(await editorHasFocus(page), `${tag} tapping a disabled button must leave the editor focused`);
  assert(await page.locator(".formatting-toolbar").isVisible(), `${tag} tapping a disabled button must leave the toolbar up`);
  console.log(`${tag} PASS: both start disabled, and tapping a disabled one keeps editing`);

  await page.keyboard.type("abc");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);
  assert(!(await isDisabled(undoBtn)), `${tag} Undo must enable after typing`);
  assert(await isDisabled(redoBtn), `${tag} Redo must stay disabled after typing`);

  await undoBtn.click();
  await waitForBody(page, "");
  assert(await isDisabled(undoBtn), `${tag} Undo must disable once everything is undone`);
  assert(!(await isDisabled(redoBtn)), `${tag} Redo must enable after an undo`);
  assert(await editorHasFocus(page), `${tag} the editor must keep focus after Undo`);

  await redoBtn.click();
  await waitForBody(page, "abc");
  assert(!(await isDisabled(undoBtn)), `${tag} Undo must enable after a redo`);
  assert(await isDisabled(redoBtn), `${tag} Redo must disable with nothing left to redo`);
  assert(await editorHasFocus(page), `${tag} the editor must keep focus after Redo`);
  console.log(`${tag} PASS: Undo and Redo change the text and enable/disable to match`);

  await page.keyboard.press("Control+a");
  await toolbarButton(page, "Bold").click();
  await waitForBody(page, "**abc**");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);
  await undoBtn.click();
  await waitForBody(page, "abc");
  console.log(`${tag} PASS: a toolbar formatting change is undone by Undo`);

  await page.keyboard.type("x");
  await page.waitForTimeout(PAST_UNDO_GROUPING_MS);
  assert(await isDisabled(redoBtn), `${tag} a new edit after an undo must clear Redo`);
  console.log(`${tag} PASS: a new edit clears Redo`);

  await page.click("#btn-new-quki");
  await waitForBody(page, "");
  await clickFirstLine(page);
  await page.locator(".formatting-toolbar").waitFor({ state: "visible" });
  assert(await isDisabled(undoBtn), `${tag} Undo must be disabled in a freshly started QuKi`);
  assert(await isDisabled(redoBtn), `${tag} Redo must be disabled in a freshly started QuKi`);
  console.log(`${tag} PASS: a new QuKi starts with nothing to undo or redo`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-undo] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await undoDoesNotReachIntoThePreviousQuKiAfterNew(browser, url);
    await undoDoesNotReachIntoThePreviousQuKiAfterOpeningOne(browser, url);
    await toolbarUndoAndRedo(browser, url);
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
