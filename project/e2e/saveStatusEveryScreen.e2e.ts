import { chromium, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

function intersects(a: Box, b: Box): boolean {
  return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}

async function bannerBox(page: Page, where: string): Promise<Box> {
  await page.waitForFunction(() => document.querySelector("#save-status")?.hasAttribute("hidden") === false, { timeout: 5000 });
  // Wait out the screen's slide-in, so control positions are final.
  await page.waitForFunction(() => document.querySelector(".view:not([hidden])")?.getBoundingClientRect().left === 0, { timeout: 5000 });
  assert(await page.isVisible("#save-status"), `the save-status banner should be visible on ${where}`);
  const box = await page.locator("#save-status").boundingBox();
  assert(box !== null && box.width > 0 && box.height > 0, `the save-status banner should have a size on ${where}`);
  const viewport = page.viewportSize()!;
  assert(box.y >= 0 && box.y + box.height <= viewport.height, `the banner should sit inside the viewport on ${where}, got ${JSON.stringify(box)}`);
  return box;
}

/**
 * Every visible match of each selector must sit clear of the banner and be
 * the topmost thing at its own centre, so the banner neither overlaps nor
 * hides any of the screen's own controls.
 */
async function assertControlsUncovered(page: Page, banner: Box, selectors: string[], where: string): Promise<void> {
  const viewport = page.viewportSize()!;
  for (const selector of selectors) {
    const elements = await page.locator(selector).all();
    let checked = 0;
    for (const element of elements) {
      if (!(await element.isVisible())) continue;
      const box = (await element.boundingBox())!;
      if (box.y >= viewport.height) continue;
      checked++;
      assert(!intersects(box, banner), `${selector} on ${where} overlaps the banner: control ${JSON.stringify(box)}, banner ${JSON.stringify(banner)}`);
      const hitBy = await element.evaluate((el) => {
        const r = el.getBoundingClientRect();
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + Math.min(r.height, window.innerHeight - r.top) / 2);
        if (hit !== null && (el === hit || el.contains(hit))) return null;
        return hit === null ? "nothing" : hit.outerHTML.slice(0, 120);
      });
      assert(hitBy === null, `${selector} on ${where} is covered at its centre by ${hitBy}`);
    }
    assert(checked > 0, `expected at least one visible ${selector} on ${where}`);
  }
}

async function bodyOf(page: Page): Promise<string> {
  return page.evaluate(() => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString());
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    // --- Scenario 1 (issue #439): a background auto-save fails while the
    // QuKi list is showing - the flush showList() runs on the way into the
    // list. The banner must be visible on the list, and stay visible on
    // Settings, Trash and back in the editor, without covering any of
    // their controls. ---
    const context = await browser.newContext({ viewport: { width: 420, height: 800 } });
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");
    await clickFirstLine(page);
    await page.keyboard.type("seed QuKi for the banner scenario");
    await page.waitForSelector("#btn-quki-list:not([disabled])", { timeout: 5000 });

    await page.evaluate(() => {
      Object.defineProperty(FileSystemFileHandle.prototype, "createWritable", {
        configurable: true,
        value: () => Promise.reject(new DOMException("simulated write failure", "NoModificationAllowedError")),
      });
    });
    await clickFirstLine(page);
    await page.keyboard.press("End");
    await page.keyboard.type(" plus an edit whose save fails");
    await page.click("#btn-quki-list");

    const listBanner = await bannerBox(page, "the QuKi list");
    const listText = (await page.textContent("#save-status")) ?? "";
    assert(/could not save/i.test(listText), `the list's banner should report the failed save, got "${listText}"`);
    await assertControlsUncovered(
      page,
      listBanner,
      ["#view-list .back-btn", "#view-list .new-btn", "#view-list .help-btn", "#view-list .settings-btn", "#view-list .search-input", "#view-list .list-row"],
      "the QuKi list",
    );
    console.log(`[e2e] PASS: a save that failed on the way into the QuKi list shows its banner there: "${listText}"`);

    await page.click("#view-list .settings-btn");
    await page.waitForSelector("#view-settings:not([hidden]) .trash-btn");
    const settingsBanner = await bannerBox(page, "Settings");
    await assertControlsUncovered(page, settingsBanner, ["#view-settings .back-btn", "#view-settings .settings-row"], "Settings");
    console.log("[e2e] PASS: the banner stays visible on Settings without covering its rows");

    await page.click("#view-settings .trash-btn");
    await page.waitForSelector("#view-trash:not([hidden]) .empty-trash-btn");
    const trashBanner = await bannerBox(page, "Trash");
    await assertControlsUncovered(page, trashBanner, ["#view-trash .back-btn", "#view-trash .empty-trash-btn"], "Trash");
    console.log("[e2e] PASS: the banner stays visible on Trash without covering its buttons");

    await page.click("#view-trash .back-btn");
    await page.waitForSelector("#view-settings:not([hidden])");
    await page.click("#view-settings .back-btn");
    await page.waitForSelector("#view-list:not([hidden])");
    await page.click("#view-list .back-btn");
    await page.waitForSelector("#view-editor:not([hidden])");
    await clickFirstLine(page);
    await page.waitForSelector(".formatting-toolbar:not([hidden])");
    const editorBanner = await bannerBox(page, "the editor");
    await assertControlsUncovered(
      page,
      editorBanner,
      ["#view-editor .app-header .app-bar-btn", ".cm-content .cm-line", ".formatting-toolbar .toolbar-btn"],
      "the editor",
    );
    const toolbarBox = (await page.locator(".formatting-toolbar").boundingBox())!;
    assert(
      toolbarBox.y + toolbarBox.height <= page.viewportSize()!.height,
      `the formatting toolbar must stay inside the viewport while the banner shows, got ${JSON.stringify(toolbarBox)}`,
    );
    assert((await bodyOf(page)).includes("plus an edit whose save fails"), "the unsaved edit should still be in the editor");
    console.log("[e2e] PASS: back in the editor the banner still shows without covering the app bar, text or toolbar, and the toolbar stays on screen");

    await context.close();

    // --- Scenario 2 (issue #439's own example): opening a QuKi from the
    // list whose read throws. The list stays on screen, so the banner must
    // be visible on the list. ---
    const openContext = await browser.newContext({ viewport: { width: 420, height: 800 } });
    const openPage = await openContext.newPage();
    await openPage.goto(url);
    await openPage.waitForSelector(".cm-content");
    await clickFirstLine(openPage);
    await openPage.keyboard.type("seed QuKi for the open-failure banner");
    await openPage.waitForSelector("#btn-quki-list:not([disabled])", { timeout: 5000 });
    await openPage.click("#btn-new-quki");
    await openPage.click("#btn-quki-list");
    const seedRow = openPage.locator(".list-row-preview", { hasText: "seed QuKi for the open-failure banner" });
    await seedRow.waitFor({ timeout: 5000 });
    await openPage.evaluate(() => {
      Object.defineProperty(FileSystemFileHandle.prototype, "getFile", {
        configurable: true,
        value: () => {
          throw new DOMException("simulated read failure", "NotReadableError");
        },
      });
    });
    await seedRow.click();
    const openBanner = await bannerBox(openPage, "the QuKi list after a failed open");
    const openText = (await openPage.textContent("#save-status")) ?? "";
    assert(/could not open/i.test(openText), `the banner should report the failed open, got "${openText}"`);
    await assertControlsUncovered(openPage, openBanner, ["#view-list .back-btn", "#view-list .search-input", "#view-list .list-row"], "the QuKi list after a failed open");
    console.log(`[e2e] PASS: a failed open from the QuKi list shows its banner on the list: "${openText}"`);

    await openContext.close();
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => {
    console.log("[e2e] ALL SCENARIOS PASSED");
    process.exit(0);
  })
  .catch((err: unknown) => {
    console.error("[e2e] FAILED:", err);
    process.exit(1);
  });
