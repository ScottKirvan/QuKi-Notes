import { chromium, type Browser, type BrowserContextOptions, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

type QukiView = {
  state: { doc: { toString(): string; lineAt(pos: number): { number: number } }; selection: { main: { head: number } } };
  documentTop: number;
  defaultLineHeight: number;
  contentDOM: HTMLElement;
  coordsAtPos(pos: number): { top: number; bottom: number } | null;
};
type WindowWithQukiView = typeof window & { qukiView: QukiView };

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

/** A point in the editor `lineIndex` lines down from the top of the text, measured from the live editor. */
async function pointOnLine(page: Page, lineIndex: number): Promise<{ x: number; y: number; lineHeight: number }> {
  return page.evaluate((index) => {
    const view = (window as WindowWithQukiView).qukiView;
    const left = view.contentDOM.getBoundingClientRect().left;
    return { x: left + 40, y: view.documentTop + (index + 0.5) * view.defaultLineHeight, lineHeight: view.defaultLineHeight };
  }, lineIndex);
}

async function caret(page: Page): Promise<{ line: number; top: number; bottom: number }> {
  return page.evaluate(() => {
    const view = (window as WindowWithQukiView).qukiView;
    const head = view.state.selection.main.head;
    const coords = view.coordsAtPos(head)!;
    return { line: view.state.doc.lineAt(head).number, top: coords.top, bottom: coords.bottom };
  });
}

async function editorHasFocus(page: Page): Promise<boolean> {
  return page.evaluate(() => document.activeElement === (window as WindowWithQukiView).qukiView.contentDOM);
}

async function openEditor(browser: Browser, url: string, options: BrowserContextOptions = {}): Promise<{ page: Page; done: () => Promise<void> }> {
  const context = await browser.newContext(options);
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

async function blankQuKiTapMidPage(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-tap-below:blank]";
  const { page, done } = await openEditor(browser, url);
  const target = await pointOnLine(page, 8);
  await page.mouse.click(target.x, target.y);

  const at = await caret(page);
  assert(at.line === 9, `${tag} the caret should be on line 9, where the tap landed, got line ${at.line}`);
  assert(at.top <= target.y && target.y <= at.bottom, `${tag} the caret should be at the tapped height ${target.y}, got ${at.top}-${at.bottom}`);
  await page.keyboard.type("mid page");
  const body = await editorBody(page);
  assert(body === "\n".repeat(8) + "mid page", `${tag} typing should land mid page, got ${JSON.stringify(body)}`);
  console.log(`${tag} PASS: a tap mid-page on a blank QuKi starts typing there`);
  await done();
}

async function tapBelowExistingText(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-tap-below:existing]";
  const { page, done } = await openEditor(browser, url);
  await clickFirstLine(page);
  await page.keyboard.type("line one");
  await page.keyboard.press("Enter");
  await page.keyboard.type("- line two");
  const target = await pointOnLine(page, 6);
  await page.mouse.click(target.x, target.y);

  const at = await caret(page);
  assert(at.line === 7, `${tag} the caret should be on line 7, got line ${at.line}`);
  await page.keyboard.type("later");
  const body = await editorBody(page);
  assert(body === "line one\n- line two\n\n\n\n\nlater", `${tag} the text above must be untouched, got ${JSON.stringify(body)}`);
  console.log(`${tag} PASS: a tap below the text adds lines without touching what's there`);
  await done();
}

async function tapThenLeaveCreatesNothing(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-tap-below:nothing-typed]";
  const { page, done } = await openEditor(browser, url);
  const target = await pointOnLine(page, 5);
  await page.mouse.click(target.x, target.y);
  assert((await editorBody(page)) === "\n".repeat(5), `${tag} precondition: the tap padded the blank QuKi`);

  await page.waitForTimeout(2600);
  assert((await page.getAttribute("#btn-quki-list", "disabled")) !== null, `${tag} padding alone must not create a QuKi (QuKis button stays disabled)`);
  console.log(`${tag} PASS: tapping a blank QuKi and typing nothing creates no QuKi`);
  await done();
}

async function touchTapWhileReading(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-tap-below:touch-reading]";
  const { page, done } = await openEditor(browser, url, { hasTouch: true });
  await clickFirstLine(page);
  await page.keyboard.type("read me");
  await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
  await page.locator(".formatting-toolbar").waitFor({ state: "hidden" });

  const target = await pointOnLine(page, 4);
  await page.touchscreen.tap(target.x, target.y);
  await page.waitForTimeout(200);
  assert(await editorHasFocus(page), `${tag} a tap below the text while reading should start editing`);
  const at = await caret(page);
  assert(at.line === 5, `${tag} the caret should be on line 5, got line ${at.line}`);
  assert((await editorBody(page)) === "read me\n\n\n\n", `${tag} the tap should pad to the tapped line, got ${JSON.stringify(await editorBody(page))}`);
  console.log(`${tag} PASS: a touch tap below the text while reading starts a line there`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-tap-below] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await blankQuKiTapMidPage(browser, url);
    await tapBelowExistingText(browser, url);
    await tapThenLeaveCreatesNothing(browser, url);
    await touchTapWhileReading(browser, url);
    console.log("[e2e-tap-below] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-tap-below] FAILED:", err);
    process.exit(1);
  });
