import { chromium, type Browser, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

// A tab-indented list item on a QuKi's first line, or right after a paragraph,
// is still a list item: it renders at depth 1 and Enter continues it.

type WindowWithQukiView = typeof window & {
  qukiView: { state: { doc: { toString(): string } } };
};

const DEPTH_1_PADDING = "46px";

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

function line(page: Page, index: number) {
  return page.locator(".cm-content .cm-line").nth(index);
}

async function assertDrawnAsBulletAtDepth1(page: Page, index: number, tag: string): Promise<void> {
  const padding = await line(page, index).evaluate((el) => getComputedStyle(el).paddingLeft);
  assert(padding === DEPTH_1_PADDING, `${tag} line ${index} must be drawn at depth 1 (${DEPTH_1_PADDING}), got ${padding}`);
  const bullets = await line(page, index).locator(".cm-quki-marker").count();
  assert(bullets === 1, `${tag} line ${index} must show a bullet, got ${bullets}`);
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

async function indentWithToolbar(page: Page): Promise<void> {
  await page.locator('.formatting-toolbar .toolbar-btn[aria-label="Indent"]').click();
}

async function firstLine(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-indented-item:first-line]";
  const { page, done } = await openEditor(browser, url);
  await clickFirstLine(page);
  await page.keyboard.type("- item");
  await indentWithToolbar(page);
  assert((await editorBody(page)) === "\t- item", `${tag} precondition: Indent puts a tab before the marker, got ${JSON.stringify(await editorBody(page))}`);
  await assertDrawnAsBulletAtDepth1(page, 0, tag);

  await page.keyboard.press("Enter");
  const body = await editorBody(page);
  assert(body === "\t- item\n\t- ", `${tag} Enter must start the next item at the same indent, got ${JSON.stringify(body)}`);
  await assertDrawnAsBulletAtDepth1(page, 1, tag);
  console.log(`${tag} PASS: an indented item on the first line is a list item and Enter continues it`);
  await done();
}

async function afterParagraph(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-indented-item:after-paragraph]";
  const { page, done } = await openEditor(browser, url);
  await clickFirstLine(page);
  await page.keyboard.type("text");
  await page.keyboard.press("Enter");
  await page.keyboard.type("- item");
  await indentWithToolbar(page);
  assert((await editorBody(page)) === "text\n\t- item", `${tag} precondition: Indent puts a tab before the marker, got ${JSON.stringify(await editorBody(page))}`);
  await assertDrawnAsBulletAtDepth1(page, 1, tag);

  await page.keyboard.press("Enter");
  const body = await editorBody(page);
  assert(body === "text\n\t- item\n\t- ", `${tag} Enter must start the next item at the same indent, got ${JSON.stringify(body)}`);
  await assertDrawnAsBulletAtDepth1(page, 2, tag);
  console.log(`${tag} PASS: an indented item right after a paragraph is a list item and Enter continues it`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-indented-item] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await firstLine(browser, url);
    await afterParagraph(browser, url);
    console.log("[e2e-indented-item] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-indented-item] FAILED:", err);
    process.exit(1);
  });
