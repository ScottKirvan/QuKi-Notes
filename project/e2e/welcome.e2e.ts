import { chromium, type Browser, type BrowserContextOptions, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type QukiWindow = typeof window & {
  qukiView: {
    state: { doc: { toString(): string } };
    contentDOM: HTMLElement;
    hasFocus: boolean;
    dispatch(spec: { changes: { from: number; insert: string } }): void;
  };
};

const TAG = "[e2e-welcome]";

async function body(page: Page): Promise<string> {
  return page.evaluate(() => (window as QukiWindow).qukiView.state.doc.toString());
}

async function editorHasFocus(page: Page): Promise<boolean> {
  return page.evaluate(() => (window as QukiWindow).qukiView.hasFocus);
}

async function open(browser: Browser, url: string, options: BrowserContextOptions = {}): Promise<{ page: Page; done: () => Promise<void> }> {
  const context = await browser.newContext({ viewport: { width: 420, height: 700 }, ...options });
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

async function welcomeGone(page: Page, what: string): Promise<void> {
  try {
    await page.waitForSelector(".welcome", { state: "detached", timeout: 3000 });
  } catch {
    throw new Error(`ASSERTION FAILED: ${what}: the welcome is still on screen`);
  }
}

async function welcomeShown(page: Page, what: string): Promise<void> {
  try {
    await page.waitForSelector(".welcome", { state: "visible", timeout: 3000 });
  } catch {
    throw new Error(`ASSERTION FAILED: ${what}: no welcome on screen`);
  }
}

/** Types a QuKi and starts a new one, which flushes the first to the folder. */
async function saveQuKiThenNew(page: Page, text: string): Promise<void> {
  await page.locator(".cm-content .cm-line").first().click();
  await page.keyboard.insertText(text);
  await page.click("#btn-new-quki");
  await page.waitForFunction(() => (window as QukiWindow).qukiView.state.doc.toString() === "");
}

async function showsOnLaunchWithContent(browser: Browser, url: string): Promise<void> {
  const { page, done } = await open(browser, url);
  await welcomeShown(page, "on launch");
  assert((await page.locator(".welcome-icon").getAttribute("src")) === "/icons/icon-192.png", "the app icon is shown");
  const greeting = (await page.locator(".welcome-greeting").textContent()) ?? "";
  assert(greeting.length > 0, "a greeting is shown");
  assert(((await page.locator(".welcome-tip").textContent()) ?? "").length > 0, "a tip is shown");
  assert((await page.locator(".welcome-recent-row").count()) === 0, "no recent list with no other QuKis");
  assert((await page.locator(".welcome").evaluate((el) => getComputedStyle(el).pointerEvents)) === "none", "the welcome takes no taps");
  assert((await page.locator(".welcome-decoration").getAttribute("aria-hidden")) === "true", "the decoration is hidden from assistive tech");
  assert(!(await page.locator(".cm-content").innerText()).includes(greeting), "the greeting is not in the editor");
  assert((await body(page)) === "", "the editor's text is empty");
  console.log(`${TAG} PASS: shows on launch with icon, greeting and tip, and no recent list when there are no QuKis`);
  await done();
}

async function tapDismissesAndStillFocuses(browser: Browser, url: string): Promise<void> {
  const { page, done } = await open(browser, url);
  await welcomeShown(page, "on launch");
  await page.evaluate(() => (window as QukiWindow).qukiView.contentDOM.blur());
  assert(!(await editorHasFocus(page)), "the editor starts the test without focus");
  // The first line sits under the welcome; the tap must reach it.
  await page.locator(".cm-content .cm-line").first().click();
  await welcomeGone(page, "after a tap");
  assert(await editorHasFocus(page), "the dismissing tap still focused the editor");
  assert((await body(page)) === "", "the tap added nothing to the text");
  console.log(`${TAG} PASS: a tap fades it and still focuses the editor`);

  await page.click("#btn-new-quki");
  await welcomeShown(page, "after New");
  await page.evaluate(() => (window as QukiWindow).qukiView.contentDOM.blur());
  await page.mouse.click(210, 450);
  await welcomeGone(page, "after a tap below the text");
  assert(await editorHasFocus(page), "a tap below the text still focuses the editor");
  const padded = await body(page);
  assert(padded.length > 0 && padded.trim() === "", "a tap below the text still pads blank lines as before");
  console.log(`${TAG} PASS: a tap below the text dismisses it and behaves as before`);
  await done();
}

async function typingDismissesAndLeavesTextAlone(browser: Browser, url: string): Promise<void> {
  const { page, done } = await open(browser, url);
  await welcomeShown(page, "on launch");
  await page.keyboard.press("a");
  await welcomeGone(page, "after a keystroke");
  assert((await body(page)) === "a", `the QuKi holds exactly what was typed, got ${JSON.stringify(await body(page))}`);
  console.log(`${TAG} PASS: a keystroke fades it, and the text is only what was typed`);
  await page.keyboard.press("Backspace");
  await page.waitForTimeout(300);
  assert((await page.locator(".welcome").count()) === 0, "emptying the QuKi does not bring it back");
  console.log(`${TAG} PASS: it does not come back after the QuKi is emptied`);
  await done();

  const second = await open(browser, url);
  await welcomeShown(second.page, "on launch");
  await second.page.evaluate(() => (window as QukiWindow).qukiView.dispatch({ changes: { from: 0, insert: "x" } }));
  await welcomeGone(second.page, "after an edit with no key or tap");
  console.log(`${TAG} PASS: any edit fades it`);
  await second.done();
}

async function newShowsItAgainAndRecentOpens(browser: Browser, url: string): Promise<void> {
  const { page, done } = await open(browser, url);
  await saveQuKiThenNew(page, "alpha note");
  await welcomeShown(page, "after New");
  await page.waitForSelector(".welcome-recent-row");
  const rows = await page.locator(".welcome-recent-row").allInnerTexts();
  assert(rows.length === 1 && rows[0]!.includes("alpha note") && rows[0]!.includes("just now"), `recent list: ${JSON.stringify(rows)}`);
  console.log(`${TAG} PASS: shows after New, with the saved QuKi in a recent list`);

  await page.locator(".welcome-recent-row").first().click();
  await page.waitForFunction(() => (window as QukiWindow).qukiView.state.doc.toString() === "alpha note");
  await welcomeGone(page, "after opening a recent QuKi");
  console.log(`${TAG} PASS: tapping a recent QuKi opens it, with no welcome`);

  await page.click("#btn-new-quki");
  await welcomeShown(page, "after New from an existing QuKi");
  await page.click("#btn-quki-list");
  await page.locator("#view-list .list-row-content").first().click();
  await page.waitForFunction(() => (window as QukiWindow).qukiView.state.doc.toString() === "alpha note");
  assert((await page.locator(".welcome").count()) === 0, "an existing QuKi opened from the list has no welcome");
  console.log(`${TAG} PASS: an existing QuKi never shows it`);
  await done();
}

async function recentListIsShortAndNewestFirst(browser: Browser, url: string): Promise<void> {
  const { page, done } = await open(browser, url);
  for (const text of ["one", "two", "three", "four"]) {
    await saveQuKiThenNew(page, text);
    await page.waitForTimeout(1100);
  }
  await page.waitForSelector(".welcome-recent-row");
  const rows = await page.locator(".welcome-recent-preview").allInnerTexts();
  assert(JSON.stringify(rows) === JSON.stringify(["four", "three", "two"]), `recent list: ${JSON.stringify(rows)}`);
  console.log(`${TAG} PASS: the recent list is the three newest, newest first`);
  await done();
}

async function reducedMotionRemovesItAtOnce(browser: Browser, url: string): Promise<void> {
  const { page, done } = await open(browser, url, { reducedMotion: "reduce" });
  await welcomeShown(page, "on launch");
  await page.keyboard.press("a");
  await page.waitForSelector(".welcome", { state: "detached", timeout: 150 });
  console.log(`${TAG} PASS: with reduced motion it goes without a fade`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    await showsOnLaunchWithContent(browser, url);
    await tapDismissesAndStillFocuses(browser, url);
    await typingDismissesAndLeavesTextAlone(browser, url);
    await newShowsItAgainAndRecentOpens(browser, url);
    await recentListIsShortAndNewestFirst(browser, url);
    await reducedMotionRemovesItAtOnce(browser, url);
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
