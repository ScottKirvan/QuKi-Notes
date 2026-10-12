import { chromium, devices, type Browser, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

type QukiView = {
  state: {
    doc: { length: number; lineAt(pos: number): { number: number } };
    selection: { main: { head: number } };
  };
  dispatch(spec: unknown): void;
  defaultLineHeight: number;
  hasFocus: boolean;
  contentDOM: HTMLElement;
  scrollDOM: HTMLElement;
  dom: HTMLElement;
  posAtCoords(coords: { x: number; y: number }): number | null;
  coordsAtPos(pos: number): { top: number; bottom: number } | null;
};
type CapacitorGlobal = { getPlatform(): string; isNativePlatform(): boolean };
type TestWindow = typeof window & { qukiView: QukiView; Capacitor: CapacitorGlobal };

const LONG_QUKI = Array.from({ length: 300 }, (_, i) => `line ${i + 1} of a long QuKi`).join("\n");
const PHONE_HEIGHT = devices["Pixel 7"].viewport.height;
const KEYBOARD_UP_HEIGHT = 450;

type Path = "android" | "web";
type KeyboardTiming = "none" | "at-focus" | "after-tap";

/** A long QuKi, saved, then opened from the QuKi list: reading mode, caret at the start. */
async function openLongQuKiFromList(browser: Browser, url: string, path: Path): Promise<{ page: Page; done: () => Promise<void> }> {
  const context = await browser.newContext({ ...devices["Pixel 7"] });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await clickFirstLine(page);
  await page.evaluate((text) => {
    const view = (window as TestWindow).qukiView;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
  }, LONG_QUKI);
  await page.click("#btn-quki-list");
  await page.locator("#view-list .list-row").first().waitFor();
  await page.locator("#view-list .list-row-main").first().click();
  await page.waitForSelector("#view-list", { state: "hidden" });
  await page.locator(".formatting-toolbar").waitFor({ state: "hidden" });
  assert(
    await page.evaluate(() => (window as TestWindow).qukiView.state.selection.main.head === 0),
    "precondition: a QuKi opened from the list has its caret at the start",
  );
  if (path === "android") {
    // The Android branch of the edit-mode switch, run in Chromium: from here
    // on Capacitor reports a native Android platform. Startup already ran as
    // the web build (its storage needs the real native plugins).
    await page.evaluate(() => {
      const capacitor = (window as TestWindow).Capacitor;
      capacitor.getPlatform = () => "android";
      capacitor.isNativePlatform = () => true;
    });
  }
  return {
    page,
    done: async () => {
      assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
      await context.close();
    },
  };
}

async function scrollTop(page: Page): Promise<number> {
  return page.evaluate(() => (window as TestWindow).qukiView.scrollDOM.scrollTop);
}

async function caretLine(page: Page): Promise<number> {
  return page.evaluate(() => {
    const view = (window as TestWindow).qukiView;
    return view.state.doc.lineAt(view.state.selection.main.head).number;
  });
}

/** Space between the caret and the toolbar, in lines, and whether the caret is below the editor's top. */
async function caretClearance(page: Page): Promise<{ lines: number; onScreen: boolean }> {
  return page.evaluate(() => {
    const view = (window as TestWindow).qukiView;
    const caret = view.coordsAtPos(view.state.selection.main.head);
    if (caret === null) throw new Error("the caret has no on-screen position");
    const toolbar = document.querySelector(".formatting-toolbar")!.getBoundingClientRect();
    return {
      lines: (toolbar.top - caret.bottom) / view.defaultLineHeight,
      onScreen: caret.top >= view.scrollDOM.getBoundingClientRect().top,
    };
  });
}

async function scrollFarDown(page: Page): Promise<void> {
  await page.evaluate(() => {
    (window as TestWindow).qukiView.scrollDOM.scrollTop = 4000;
  });
  await page.waitForTimeout(200);
}

/** A point 40% of the way down the editor, and the line under it. */
async function pointOnALine(page: Page): Promise<{ x: number; y: number; line: number }> {
  return page.evaluate(() => {
    const view = (window as TestWindow).qukiView;
    const box = view.scrollDOM.getBoundingClientRect();
    const x = view.contentDOM.getBoundingClientRect().left + 30;
    const y = box.top + box.height * 0.4;
    const pos = view.posAtCoords({ x, y });
    if (pos === null) throw new Error("no text under the tap point");
    return { x, y, line: view.state.doc.lineAt(pos).number };
  });
}

// A SIMULATION of Android's keyboard coming up: Chromium has no on-screen
// keyboard, so the screen shrinks the way the WebView does when it rises.
// "at-focus" shrinks the editor inside the tap's own focus event, before
// the tap's caret has landed; "after-tap" shrinks the viewport once it has.
async function tapWhileReading(browser: Browser, url: string, path: Path, timing: KeyboardTiming): Promise<void> {
  const tag = `[e2e-tap-to-type:${path}:${timing}]`;
  const { page, done } = await openLongQuKiFromList(browser, url, path);
  await scrollFarDown(page);
  const before = await scrollTop(page);
  const target = await pointOnALine(page);
  if (timing === "at-focus") {
    await page.evaluate((height) => {
      const view = (window as TestWindow).qukiView;
      view.contentDOM.addEventListener("focus", () => (view.dom.style.height = `${height}px`), { once: true });
    }, KEYBOARD_UP_HEIGHT - 100);
  }

  await page.touchscreen.tap(target.x, target.y);
  await page.waitForTimeout(150);
  assert(await page.evaluate(() => (window as TestWindow).qukiView.hasFocus), `${tag} the tap should start editing`);
  assert((await caretLine(page)) === target.line, `${tag} the cursor should be on the tapped line ${target.line}, got line ${await caretLine(page)}`);
  if (timing === "none") {
    const after = await scrollTop(page);
    assert(Math.abs(after - before) <= 1, `${tag} the view should stay where it was: scrollTop ${before} -> ${after}`);
  }

  if (timing === "after-tap") {
    await page.setViewportSize({ width: devices["Pixel 7"].viewport.width, height: KEYBOARD_UP_HEIGHT });
    await page.waitForTimeout(200);
    const clear = await caretClearance(page);
    assert(clear.onScreen && clear.lines >= 2 - 0.05, `${tag} with the keyboard up the caret should be on screen two lines above the toolbar, got ${clear.lines.toFixed(2)} lines`);
  }
  const after = await scrollTop(page);
  assert(after > before / 2, `${tag} the view must not jump back toward the top: scrollTop ${before} -> ${after}`);
  assert((await caretLine(page)) === target.line, `${tag} the cursor should still be on line ${target.line}, got line ${await caretLine(page)}`);
  console.log(`${tag} PASS: a tap while reading far down keeps the view and puts the cursor on the tapped line`);
  await done();
}

async function resizeLeavesAnOffScreenCaretAlone(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-tap-to-type:resize-off-screen-caret]";
  const { page, done } = await openLongQuKiFromList(browser, url, "web");
  await clickFirstLine(page);
  await page.waitForTimeout(200);
  await scrollFarDown(page);
  const before = await scrollTop(page);
  await page.setViewportSize({ width: devices["Pixel 7"].viewport.width, height: PHONE_HEIGHT - 300 });
  await page.waitForTimeout(200);
  const after = await scrollTop(page);
  assert(after >= before, `${tag} the screen shrinking must not scroll to a caret that was off screen: scrollTop ${before} -> ${after}`);
  console.log(`${tag} PASS: the screen shrinking leaves the view alone when the caret was off screen`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-tap-to-type] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  const failures: string[] = [];
  const scenarios: Array<[string, () => Promise<void>]> = [];
  for (const path of ["android", "web"] as const) {
    for (const timing of ["none", "at-focus", "after-tap"] as const) {
      scenarios.push([`${path}:${timing}`, () => tapWhileReading(browser, url, path, timing)]);
    }
  }
  scenarios.push(["resize-off-screen-caret", () => resizeLeavesAnOffScreenCaretAlone(browser, url)]);
  try {
    for (const [name, run] of scenarios) {
      try {
        await run();
      } catch (err) {
        console.error(String(err));
        failures.push(name);
      }
    }
    if (failures.length > 0) throw new Error(`failed: ${failures.join(", ")}`);
    console.log("[e2e-tap-to-type] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-tap-to-type] FAILED:", err);
    process.exit(1);
  });
