import { chromium, type Browser, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

type QukiView = {
  state: { doc: { length: number; line(n: number): { from: number } }; selection: { main: { head: number } } };
  dispatch(spec: unknown): void;
  defaultLineHeight: number;
  documentTop: number;
  contentDOM: HTMLElement;
  scrollDOM: HTMLElement;
  coordsAtPos(pos: number): { top: number; bottom: number } | null;
};
type WindowWithQukiView = typeof window & { qukiView: QukiView };

const LONG_QUKI = Array.from({ length: 80 }, (_, i) => `line ${i + 1}`).join("\n");

type Clearance = { gap: number; lineHeight: number; caretTop: number; scrollerTop: number };

/** Space between the caret's bottom and the formatting toolbar's top, in px and in the editor's line height. */
async function clearance(page: Page): Promise<Clearance> {
  return page.evaluate(() => {
    const view = (window as WindowWithQukiView).qukiView;
    const caret = view.coordsAtPos(view.state.selection.main.head);
    if (caret === null) throw new Error("the caret has no on-screen position");
    const toolbar = document.querySelector(".formatting-toolbar")!.getBoundingClientRect();
    if (toolbar.height === 0) throw new Error("the formatting toolbar is not showing");
    return {
      gap: toolbar.top - caret.bottom,
      lineHeight: view.defaultLineHeight,
      caretTop: caret.top,
      scrollerTop: view.scrollDOM.getBoundingClientRect().top,
    };
  });
}

function assertTwoLinesClear(tag: string, c: Clearance, what: string): void {
  assert(c.caretTop >= c.scrollerTop, `${tag} ${what}: the caret should be on screen, its top ${c.caretTop} is above the editor's top ${c.scrollerTop}`);
  assert(
    c.gap >= 2 * c.lineHeight - 1,
    `${tag} ${what}: expected at least two lines (${2 * c.lineHeight}px) between the caret and the toolbar, got ${c.gap}px`,
  );
}

async function openLongQuKi(browser: Browser, url: string, height: number): Promise<{ page: Page; done: () => Promise<void> }> {
  const context = await browser.newContext({ viewport: { width: 400, height } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await clickFirstLine(page);
  await page.evaluate((text) => {
    const view = (window as WindowWithQukiView).qukiView;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: 0 } });
  }, LONG_QUKI);
  return {
    page,
    done: async () => {
      assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
      await context.close();
    },
  };
}

async function readingMode(page: Page): Promise<void> {
  await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
  await page.locator(".formatting-toolbar").waitFor({ state: "hidden" });
}

/** The lowest line wholly visible in the editor, as a point to tap. */
async function lowestVisibleLine(page: Page): Promise<{ x: number; y: number }> {
  return page.evaluate(() => {
    const scrollerBottom = (window as WindowWithQukiView).qukiView.scrollDOM.getBoundingClientRect().bottom;
    let best: DOMRect | null = null;
    for (const line of Array.from(document.querySelectorAll(".cm-line"))) {
      const box = line.getBoundingClientRect();
      if (box.bottom <= scrollerBottom && (best === null || box.bottom > best.bottom)) best = box;
    }
    if (best === null) throw new Error("no visible line");
    return { x: best.left + 5, y: (best.top + best.bottom) / 2 };
  });
}

async function typingDownTheMiddle(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-caret-clearance:typing]";
  const { page, done } = await openLongQuKi(browser, url, 500);
  for (let i = 0; i < 30; i++) await page.keyboard.press("ArrowDown");
  assertTwoLinesClear(tag, await clearance(page), "after moving the caret down past the bottom");
  await page.keyboard.press("End");
  await page.keyboard.press("Enter");
  await page.keyboard.type("new line");
  assertTwoLinesClear(tag, await clearance(page), "after Enter and typing");
  console.log(`${tag} PASS: typing at the bottom of the screen keeps two lines above the toolbar`);
  await done();
}

async function enterAtTheEnd(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-caret-clearance:end]";
  const { page, done } = await openLongQuKi(browser, url, 500);
  await page.keyboard.press("Control+End");
  await page.keyboard.press("Enter");
  await page.keyboard.type("last");
  assertTwoLinesClear(tag, await clearance(page), "after Enter at the end of the QuKi");
  console.log(`${tag} PASS: Enter at the very end of a long QuKi keeps two lines above the toolbar`);
  await done();
}

async function tapLowLineWhileReading(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-caret-clearance:tap-reading]";
  const { page, done } = await openLongQuKi(browser, url, 500);
  await readingMode(page);
  await page.evaluate(() => {
    const scroller = (window as WindowWithQukiView).qukiView.scrollDOM;
    scroller.scrollTop = scroller.scrollHeight / 3;
  });
  const target = await lowestVisibleLine(page);
  await page.mouse.click(target.x, target.y);
  await page.waitForTimeout(100);
  assertTwoLinesClear(tag, await clearance(page), "after tapping the lowest visible line while reading");
  console.log(`${tag} PASS: tapping a low line while reading keeps two lines above the toolbar`);
  await done();
}

async function tapBelowTextNearTheToolbar(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-caret-clearance:tap-below]";
  const context = await browser.newContext({ viewport: { width: 400, height: 500 } });
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await clickFirstLine(page);
  const target = await page.evaluate(() => {
    const view = (window as WindowWithQukiView).qukiView;
    const toolbarTop = document.querySelector(".formatting-toolbar")!.getBoundingClientRect().top;
    return { x: view.contentDOM.getBoundingClientRect().left + 40, y: toolbarTop - view.defaultLineHeight / 2 };
  });
  await page.mouse.click(target.x, target.y);
  await page.waitForTimeout(100);
  assertTwoLinesClear(tag, await clearance(page), "after a tap below the text just above the toolbar");
  console.log(`${tag} PASS: a tap below the text just above the toolbar keeps two lines above it`);
  await context.close();
}

// A SIMULATION of Android's keyboard coming up: Chromium has no on-screen
// keyboard, so the viewport is shrunk after the tap, the way the WebView
// shrinks when the keyboard rises. It cannot show the real keyboard's timing.
async function keyboardRisesOverTheCaret(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-caret-clearance:keyboard]";
  const { page, done } = await openLongQuKi(browser, url, 800);
  await readingMode(page);
  await page.evaluate(() => {
    (window as WindowWithQukiView).qukiView.scrollDOM.scrollTop = 0;
  });
  const target = await lowestVisibleLine(page);
  await page.mouse.click(target.x, target.y);
  await page.waitForTimeout(100);
  await page.setViewportSize({ width: 400, height: 450 });
  await page.waitForTimeout(200);
  assertTwoLinesClear(tag, await clearance(page), "after the keyboard (simulated) shrinks the screen");
  console.log(`${tag} PASS: when the screen shrinks for the keyboard (simulated), the caret stays two lines above the toolbar`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-caret-clearance] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  const failures: string[] = [];
  try {
    for (const scenario of [typingDownTheMiddle, enterAtTheEnd, tapLowLineWhileReading, tapBelowTextNearTheToolbar, keyboardRisesOverTheCaret]) {
      try {
        await scenario(browser, url);
      } catch (err) {
        console.error(String(err));
        failures.push(scenario.name);
      }
    }
    if (failures.length > 0) throw new Error(`failed: ${failures.join(", ")}`);
    console.log("[e2e-caret-clearance] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-caret-clearance] FAILED:", err);
    process.exit(1);
  });
