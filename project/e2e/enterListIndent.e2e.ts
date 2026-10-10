import { chromium, type Browser, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

type WindowWithQukiView = typeof window & {
  qukiView: { state: { doc: { toString(): string } } };
};

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

async function linePaddingLeft(page: Page, index: number): Promise<string> {
  return page.locator(".cm-content .cm-line").nth(index).evaluate((el) => getComputedStyle(el).paddingLeft);
}

async function openEditor(browser: Browser, url: string): Promise<{ page: Page; done: () => Promise<void> }> {
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

async function typeIndentedTask(page: Page): Promise<void> {
  await clickFirstLine(page);
  await page.keyboard.type("- [ ] top");
  await page.keyboard.press("Enter");
  await page.keyboard.type("a");
  await page.keyboard.press("Tab");
  assert((await editorBody(page)) === "- [ ] top\n\t- [ ] a", `precondition: Tab indents the task, got ${JSON.stringify(await editorBody(page))}`);
  await page.keyboard.press("Enter");
}

async function enterKeepsIndentedTaskDepth(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-enter-indent:rendered]";
  const { page, done } = await openEditor(browser, url);
  await typeIndentedTask(page);

  const body = await editorBody(page);
  assert(body === "- [ ] top\n\t- [ ] a\n\t- [ ] ", `${tag} Enter must start the next task at the same tab indent, got ${JSON.stringify(body)}`);
  await page.keyboard.type("b");
  const above = await linePaddingLeft(page, 1);
  const below = await linePaddingLeft(page, 2);
  assert(above === below, `${tag} the new task must be drawn at the same depth (${above}), got ${below}`);
  console.log(`${tag} PASS: Enter after an indented task starts one at the same depth`);
  await done();
}

async function newEmptyItemDrawnAtDepth(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-enter-indent:empty-item-depth]";
  const { page, done } = await openEditor(browser, url);
  await typeIndentedTask(page);

  const above = await linePaddingLeft(page, 1);
  const below = await linePaddingLeft(page, 2);
  assert(above === below, `${tag} the new empty task must be drawn at its depth (${above}) before anything is typed, got ${below}`);
  const checkboxes = await page.locator(".cm-content .cm-line").nth(2).locator(".cm-quki-checkbox").count();
  assert(checkboxes === 1, `${tag} the new empty task must show its checkbox, got ${checkboxes}`);
  console.log(`${tag} PASS: a new empty indented task is drawn at its depth straight away`);
  await done();
}

async function enterKeepsIndentInPlainText(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-enter-indent:plain-text]";
  const { page, done } = await openEditor(browser, url);
  await clickFirstLine(page);
  await page.click("#btn-mode-toggle");
  assert((await page.getAttribute("#btn-mode-toggle", "aria-pressed")) === "true", `${tag} precondition: plain-text mode is on`);
  await typeIndentedTask(page);

  const body = await editorBody(page);
  assert(body === "- [ ] top\n\t- [ ] a\n\t- [ ] ", `${tag} Enter must start the next task at the same tab indent, got ${JSON.stringify(body)}`);
  console.log(`${tag} PASS: the same holds in plain-text mode`);
  await done();
}

async function enterOnEmptySecondItemEndsList(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-enter-indent:empty-second-item]";
  const { page, done } = await openEditor(browser, url);
  await clickFirstLine(page);
  await page.keyboard.type("- item");
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");

  const body = await editorBody(page);
  assert(body === "- item\n", `${tag} Enter on the empty second item must end the list, got ${JSON.stringify(body)}`);
  console.log(`${tag} PASS: Enter on an empty second item ends the list`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-enter-indent] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await enterKeepsIndentedTaskDepth(browser, url);
    await newEmptyItemDrawnAtDepth(browser, url);
    await enterKeepsIndentInPlainText(browser, url);
    await enterOnEmptySecondItemEndsList(browser, url);
    console.log("[e2e-enter-indent] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-enter-indent] FAILED:", err);
    process.exit(1);
  });
