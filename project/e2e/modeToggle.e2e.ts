import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type WindowWithQukiView = typeof window & {
  qukiView: { contentDOM: HTMLElement };
  editorBlurCount: number;
};

async function plainTextOn(page: Page): Promise<boolean> {
  return (await page.getAttribute("#btn-mode-toggle", "aria-pressed")) === "true";
}

async function editorHasFocus(page: Page): Promise<boolean> {
  return page.evaluate(() => document.activeElement === (window as WindowWithQukiView).qukiView.contentDOM);
}

async function toolbarVisible(page: Page): Promise<boolean> {
  return page.locator(".formatting-toolbar").isVisible();
}

/**
 * Counts every blur of the editor from now on. On Android the soft keyboard
 * goes away the moment the editor loses focus, even if it is refocused
 * straight after, so a tap must never blur the editor at all.
 */
async function startCountingEditorBlurs(page: Page): Promise<void> {
  await page.evaluate(() => {
    const w = window as WindowWithQukiView;
    w.editorBlurCount = 0;
    w.qukiView.contentDOM.addEventListener("blur", () => (w.editorBlurCount += 1));
  });
}

async function editorBlurCount(page: Page): Promise<number> {
  return page.evaluate(() => (window as WindowWithQukiView).editorBlurCount);
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

async function whileEditingItTogglesWithoutLeavingTheEditor(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-mode-toggle:editing]";
  const { page, done } = await openEditor(browser, url);
  await page.click(".cm-content");
  await page.keyboard.type("Some text");
  assert(await toolbarVisible(page), `${tag} precondition: editing, so the toolbar is up`);
  assert(!(await plainTextOn(page)), `${tag} precondition: starts in rendered mode`);
  await startCountingEditorBlurs(page);

  await page.click("#btn-mode-toggle");
  assert(await plainTextOn(page), `${tag} a tap while editing must switch to plain text`);
  assert((await editorBlurCount(page)) === 0, `${tag} the tap must never take focus from the editor (that drops the Android keyboard)`);
  assert(await editorHasFocus(page), `${tag} the editor must still have focus`);
  assert(await toolbarVisible(page), `${tag} still editing, so the toolbar stays up`);

  await page.click("#btn-mode-toggle");
  assert(!(await plainTextOn(page)), `${tag} a second tap while editing must switch back to rendered`);
  assert((await editorBlurCount(page)) === 0, `${tag} the second tap must not take focus from the editor either`);
  console.log(`${tag} PASS: while editing, a tap switches modes and the editor never loses focus`);
  await done();
}

async function whileReadingItOnlyBringsEditingBack(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-mode-toggle:reading]";
  const { page, done } = await openEditor(browser, url);
  await page.click(".cm-content");
  await page.keyboard.type("Some text");
  await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
  await page.locator(".formatting-toolbar").waitFor({ state: "hidden" });

  await page.click("#btn-mode-toggle");
  assert(!(await plainTextOn(page)), `${tag} a tap while reading must not switch modes`);
  assert(await editorHasFocus(page), `${tag} a tap while reading must bring editing back`);
  await page.locator(".formatting-toolbar").waitFor({ state: "visible", timeout: 2000 });

  await page.click("#btn-mode-toggle");
  assert(await plainTextOn(page), `${tag} once editing again, the next tap switches modes`);
  console.log(`${tag} PASS: while reading, a tap brings editing back without switching modes`);

  await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
  await page.waitForFunction(() => document.activeElement !== (window as WindowWithQukiView).qukiView.contentDOM);
  await page.click("#btn-mode-toggle");
  assert(await plainTextOn(page), `${tag} in plain text, a tap while reading must leave plain text on`);
  assert(await editorHasFocus(page), `${tag} in plain text, a tap while reading must bring editing back`);
  console.log(`${tag} PASS: the same holds in plain-text mode`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-mode-toggle] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await whileEditingItTogglesWithoutLeavingTheEditor(browser, url);
    await whileReadingItOnlyBringsEditingBack(browser, url);
    console.log("[e2e-mode-toggle] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-mode-toggle] FAILED:", err);
    process.exit(1);
  });
