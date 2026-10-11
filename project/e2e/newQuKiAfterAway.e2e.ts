import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type QukiWindow = typeof window & {
  qukiView: { state: { doc: { toString(): string } }; contentDOM: HTMLElement; hasFocus: boolean };
  qukiSystemBack: () => Promise<void>;
  __visibility: DocumentVisibilityState;
};

const TAG = "[e2e-newQuKiAfterAway]";

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as QukiWindow).qukiView.state.doc.toString());
}

async function waitForBody(page: Page, body: string, what: string): Promise<void> {
  try {
    await page.waitForFunction((expected) => (window as QukiWindow).qukiView.state.doc.toString() === expected, body, { timeout: 5000 });
  } catch {
    throw new Error(`ASSERTION FAILED: ${what}: expected the editor to hold ${JSON.stringify(body)}, got ${JSON.stringify(await editorBody(page))}`);
  }
}

async function visibleView(page: Page): Promise<string> {
  return page.evaluate(() =>
    ["editor", "list", "settings", "trash"].filter((name) => !document.querySelector<HTMLElement>(`#view-${name}`)!.hidden).join(","),
  );
}

async function typeQuKi(page: Page, text: string): Promise<void> {
  await page.locator(".cm-content .cm-line").first().click();
  await page.keyboard.insertText(text);
}

async function setVisibility(page: Page, state: DocumentVisibilityState): Promise<void> {
  await page.evaluate((state) => {
    (window as QukiWindow).__visibility = state;
    document.dispatchEvent(new Event("visibilitychange"));
  }, state);
}

/** The app goes out of sight, `minutes` pass on the clock, and it comes back. */
async function goAway(page: Page, minutes: number): Promise<void> {
  await setVisibility(page, "hidden");
  await page.clock.fastForward(minutes * 60_000);
  await setVisibility(page, "visible");
  await page.waitForTimeout(500);
}

async function openFreshApp(browser: Browser, url: string): Promise<{ page: Page; done: () => Promise<void> }> {
  const context = await browser.newContext({ viewport: { width: 420, height: 700 } });
  await context.addInitScript(() => {
    (window as QukiWindow).__visibility = "visible";
    Object.defineProperty(document, "visibilityState", { configurable: true, get: () => (window as QukiWindow).__visibility });
    Object.defineProperty(document, "hidden", { configurable: true, get: () => (window as QukiWindow).__visibility === "hidden" });
    navigator.share = () => Promise.resolve();
  });
  const page = await context.newPage();
  await page.clock.install();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await page.waitForFunction(() => typeof (window as QukiWindow).qukiSystemBack === "function");
  return {
    page,
    done: async () => {
      assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
      await context.close();
    },
  };
}

async function editorHasFocus(page: Page): Promise<boolean> {
  return page.evaluate(() => (window as QukiWindow).qukiView.hasFocus);
}

async function awayLongEnoughStartsANewQuKi(browser: Browser, url: string): Promise<void> {
  const { page, done } = await openFreshApp(browser, url);
  await typeQuKi(page, "first thought");
  await page.evaluate(() => (window as QukiWindow).qukiView.contentDOM.blur());
  await goAway(page, 3);
  await waitForBody(page, "", "after three minutes away");
  assert(await editorHasFocus(page), "the new QuKi takes focus, ready to type");
  console.log(`${TAG} PASS: three minutes away starts a new, focused, blank QuKi`);

  await page.evaluate(() => (window as QukiWindow).qukiSystemBack());
  await waitForBody(page, "first thought", "Back from the new QuKi");
  console.log(`${TAG} PASS: the QuKi left behind was saved and Back returns to it`);

  await page.click("#btn-quki-list");
  await page.waitForSelector("#view-list .quki-row, #view-list li", { timeout: 5000 }).catch(() => undefined);
  const listText = await page.locator("#view-list").innerText();
  assert(listText.includes("first thought"), `the QuKi list holds the saved QuKi, got: ${listText}`);
  await done();
}

async function shortTripOrStayingVisibleChangesNothing(browser: Browser, url: string): Promise<void> {
  const { page, done } = await openFreshApp(browser, url);
  await typeQuKi(page, "keep me");
  await goAway(page, 1);
  await waitForBody(page, "keep me", "after one minute away");
  console.log(`${TAG} PASS: a one-minute trip away changes nothing`);

  await page.clock.fastForward(30 * 60_000);
  await setVisibility(page, "visible");
  await page.waitForTimeout(500);
  assert((await editorBody(page)) === "keep me", "an app left open and visible changes nothing, however long");
  console.log(`${TAG} PASS: thirty minutes open and visible changes nothing`);
  await done();
}

async function chooseAway(page: Page, value: string): Promise<void> {
  await page.click("#btn-settings");
  await page.waitForSelector("#view-settings .away-select", { state: "visible" });
  await page.selectOption("#view-settings .away-select", value);
  await page.click("#view-settings .back-btn");
  await page.waitForTimeout(300);
}

async function theSettingControlsIt(browser: Browser, url: string): Promise<void> {
  const { page, done } = await openFreshApp(browser, url);
  await page.click("#btn-settings");
  const initial = await page.inputValue("#view-settings .away-select");
  assert(initial === "2", `the setting defaults to 2 minutes, got ${initial}`);
  const labels = await page.$$eval("#view-settings .away-select option", (options) => options.map((o) => o.textContent));
  assert(
    JSON.stringify(labels) === JSON.stringify(["Off", "After 2 minutes", "After 5 minutes", "After 15 minutes", "After 30 minutes"]),
    `choices: ${JSON.stringify(labels)}`,
  );
  await page.click("#view-settings .back-btn");
  await page.waitForTimeout(300);

  await chooseAway(page, "off");
  await typeQuKi(page, "stays");
  await goAway(page, 60);
  await waitForBody(page, "stays", "with the setting Off, after an hour away");
  console.log(`${TAG} PASS: Off never starts a new QuKi`);

  await chooseAway(page, "5");
  await goAway(page, 3);
  await waitForBody(page, "stays", "set to 5 minutes, after 3 away");
  await goAway(page, 6);
  await waitForBody(page, "", "set to 5 minutes, after 6 away");
  console.log(`${TAG} PASS: the chosen time is the one that counts`);

  await page.reload();
  await page.waitForSelector(".cm-content");
  await page.click("#btn-settings");
  const persisted = await page.inputValue("#view-settings .away-select");
  assert(persisted === "5", `the choice persists across a reload, got ${persisted}`);
  console.log(`${TAG} PASS: the choice persists across a reload`);
  await done();
}

async function sendsShareSheetDoesNotCount(browser: Browser, url: string): Promise<void> {
  const { page, done } = await openFreshApp(browser, url);
  await typeQuKi(page, "sent away");
  await page.click("#btn-send");
  await page.waitForTimeout(300);
  await goAway(page, 5);
  await waitForBody(page, "sent away", "coming back from Send's share sheet");
  console.log(`${TAG} PASS: coming back from Send's share sheet keeps the QuKi that was sent`);

  await goAway(page, 5);
  await waitForBody(page, "", "the next trip away after a Send");
  console.log(`${TAG} PASS: the next trip away counts as usual`);
  await done();
}

async function awayFromTheListLandsInANewQuKi(browser: Browser, url: string): Promise<void> {
  const { page, done } = await openFreshApp(browser, url);
  await typeQuKi(page, "listed");
  await page.click("#btn-quki-list");
  await page.waitForTimeout(500);
  await goAway(page, 3);
  await waitForBody(page, "", "coming back to the list after three minutes");
  const view = await visibleView(page);
  assert(view === "editor", `coming back shows the editor, got ${view}`);
  await page.evaluate(() => (window as QukiWindow).qukiSystemBack());
  await page.waitForTimeout(500);
  const afterBack = await visibleView(page);
  assert(afterBack === "list", `Back from the new QuKi returns to the list the user left, got ${afterBack}`);
  console.log(`${TAG} PASS: away from the list lands in a new QuKi, and Back returns to the list`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    await awayLongEnoughStartsANewQuKi(browser, url);
    await shortTripOrStayingVisibleChangesNothing(browser, url);
    await theSettingControlsIt(browser, url);
    await sendsShareSheetDoesNotCount(browser, url);
    await awayFromTheListLandsInANewQuKi(browser, url);
    console.log(`${TAG} ALL SCENARIOS PASSED`);
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error(`${TAG} FAILED:`, err);
    process.exit(1);
  });
