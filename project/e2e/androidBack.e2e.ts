import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type QukiWindow = typeof window & {
  qukiView: { state: { doc: { toString(): string } }; scrollDOM: HTMLElement; contentDOM: HTMLElement };
  qukiSystemBack: () => Promise<void>;
};

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as QukiWindow).qukiView.state.doc.toString());
}

async function waitForBody(page: Page, body: string): Promise<void> {
  await page.waitForFunction((expected) => (window as QukiWindow).qukiView.state.doc.toString() === expected, body);
}

async function pressBack(page: Page): Promise<void> {
  await page.evaluate(() => (window as QukiWindow).qukiSystemBack());
}

async function visibleView(page: Page): Promise<string> {
  return page.evaluate(() => {
    const shown = ["editor", "list", "settings", "trash"].filter((name) => !document.querySelector<HTMLElement>(`#view-${name}`)!.hidden);
    return shown.join(",");
  });
}

// Clicks the (empty) first line: a tap in the empty space below the text adds lines down to where it lands.
async function typeQuKi(page: Page, text: string): Promise<void> {
  await page.locator(".cm-content .cm-line").first().click();
  await page.keyboard.insertText(text);
}

async function openFreshApp(browser: Browser, url: string): Promise<{ page: Page; done: () => Promise<void> }> {
  const context = await browser.newContext({ viewport: { width: 420, height: 700 } });
  const page = await context.newPage();
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

async function backWalksQuKisAndTheListAndRestoresScroll(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-back:history]";
  const { page, done } = await openFreshApp(browser, url);
  const bodyB = "Back QuKi B";
  const bodyA = Array.from({ length: 120 }, (_, i) => `Back QuKi A line ${i + 1}`).join("\n");

  await typeQuKi(page, bodyB);
  await page.click("#btn-new-quki");
  await waitForBody(page, "");
  await typeQuKi(page, bodyA);
  const savedScroll = await page.evaluate(() => {
    const scroller = (window as QukiWindow).qukiView.scrollDOM;
    scroller.scrollTop = 900;
    return scroller.scrollTop;
  });
  assert(savedScroll > 500, `${tag} QuKi A must be long enough to scroll, got scrollTop ${savedScroll}`);
  await page.waitForTimeout(100);

  await page.click("#btn-quki-list");
  const list = page.locator("#view-list");
  await list.locator(".list-row-preview", { hasText: bodyB }).click({ timeout: 5000 });
  await waitForBody(page, bodyB);
  assert((await visibleView(page)) === "editor", `${tag} opening B must show the editor`);

  await pressBack(page);
  assert((await visibleView(page)) === "list", `${tag} Back from B must land on the list, got ${await visibleView(page)}`);
  await list.locator(".list-row-preview", { hasText: bodyB }).waitFor({ timeout: 5000 });
  console.log(`${tag} PASS: Back from a QuKi opened from the list returns to the list`);

  await pressBack(page);
  await waitForBody(page, bodyA);
  assert((await visibleView(page)) === "editor", `${tag} Back from the list must show the editor`);
  await page.waitForTimeout(300);
  const restoredScroll = await page.evaluate(() => (window as QukiWindow).qukiView.scrollDOM.scrollTop);
  assert(Math.abs(restoredScroll - savedScroll) <= 2, `${tag} A must come back at scrollTop ${savedScroll}, got ${restoredScroll}`);
  const focused = await page.evaluate(() => document.activeElement === (window as QukiWindow).qukiView.contentDOM);
  assert(!focused, `${tag} a QuKi reopened by Back opens for reading, not editing`);
  console.log(`${tag} PASS: Back from the list returns to QuKi A at its old scroll position (${restoredScroll}px)`);

  await pressBack(page);
  await waitForBody(page, bodyB);
  console.log(`${tag} PASS: Back from A reaches B, the QuKi typed at launch`);
  await done();
}

async function backSkipsSettingsTrashAndDeletedQuKis(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-back:skips]";
  const { page, done } = await openFreshApp(browser, url);
  const bodyX = "Back QuKi X";
  const bodyY = "Back QuKi Y, deleted";
  const bodyZ = "Back QuKi Z";

  await typeQuKi(page, bodyX);
  await page.click("#btn-new-quki");
  await waitForBody(page, "");
  await typeQuKi(page, bodyY);
  await page.waitForFunction(() => !document.querySelector<HTMLButtonElement>("#btn-delete")!.disabled, undefined, { timeout: 5000 });
  await page.click("#btn-delete");
  await waitForBody(page, "");
  await typeQuKi(page, bodyZ);

  await page.click("#btn-settings");
  await page.click("#view-settings .trash-btn");
  const trash = page.locator("#view-trash");
  await trash.locator(".list-row-preview", { hasText: bodyY }).waitFor({ timeout: 5000 });

  await trash.locator(".empty-trash-btn").click();
  const dialog = page.locator(".confirm-overlay:not(.about-overlay)");
  await dialog.waitFor({ state: "visible" });
  await pressBack(page);
  assert(await dialog.isHidden(), `${tag} Back must close the confirm dialog`);
  assert((await visibleView(page)) === "trash", `${tag} Back on a dialog must do nothing but close it, got ${await visibleView(page)}`);
  assert((await trash.locator(".list-row").count()) === 1, `${tag} closing the dialog with Back must cancel, not empty Trash`);
  console.log(`${tag} PASS: Back closes a confirm dialog as Cancel and does nothing else`);

  await pressBack(page);
  assert((await visibleView(page)) === "editor", `${tag} Back from Trash must skip Settings, got ${await visibleView(page)}`);
  assert((await editorBody(page)) === bodyZ, `${tag} Back from Trash must return to the QuKi the user left`);
  console.log(`${tag} PASS: Back from Trash goes past Settings to where the user was`);

  await pressBack(page);
  await waitForBody(page, bodyX);
  assert((await visibleView(page)) === "editor", `${tag} Back must never land on Settings or Trash, got ${await visibleView(page)}`);
  console.log(`${tag} PASS: Back skips the deleted QuKi and never stops on Settings or Trash`);

  await page.click("#btn-quki-list");
  await page.locator("#view-list .list-row-preview", { hasText: bodyX }).waitFor({ timeout: 5000 });
  await page.click("#view-list .settings-btn, #view-list [aria-label='Settings']");
  assert((await visibleView(page)) === "settings", `${tag} Settings must open from the list`);
  await pressBack(page);
  assert((await visibleView(page)) === "list", `${tag} Back from Settings opened from the list returns to the list, got ${await visibleView(page)}`);
  console.log(`${tag} PASS: Back from Settings returns to the list it was opened from`);
  await done();
}

async function backClosesTheHelpDialogFirst(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-back:dialog]";
  const { page, done } = await openFreshApp(browser, url);
  await typeQuKi(page, "Back dialog QuKi");
  await page.click("#btn-quki-list");
  await page.locator("#view-list .list-row-preview", { hasText: "Back dialog QuKi" }).waitFor({ timeout: 5000 });
  await page.click("#view-list [aria-label='Help']");
  const about = page.locator(".about-overlay");
  await about.waitFor({ state: "visible" });

  await pressBack(page);
  assert(await about.isHidden(), `${tag} Back must close the Help dialog`);
  assert((await visibleView(page)) === "list", `${tag} closing Help with Back must stay on the list, got ${await visibleView(page)}`);
  console.log(`${tag} PASS: Back closes the Help dialog and stays put`);

  await pressBack(page);
  assert((await visibleView(page)) === "editor", `${tag} the next Back leaves the list`);
  console.log(`${tag} PASS: the next Back goes back as usual`);
  await done();
}

async function backReturnsToTheBlankLaunchQuKiThenExits(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-back:launch-blank]";
  const context = await browser.newContext({ viewport: { width: 420, height: 700 } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  const exitWarnings: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  page.on("console", (msg) => {
    if (msg.text().includes("exit on Back")) exitWarnings.push(msg.text());
  });
  const bodyA = "Back launch QuKi A";

  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await typeQuKi(page, bodyA);
  await page.waitForFunction(() => !document.querySelector<HTMLButtonElement>("#btn-delete")!.disabled, undefined, { timeout: 5000 });

  // A new session: the app launches on a blank QuKi again, with A on disk.
  await page.reload();
  await page.waitForSelector(".cm-content");
  await page.waitForFunction(() => typeof (window as QukiWindow).qukiSystemBack === "function");
  await page.waitForFunction(() => !document.querySelector<HTMLButtonElement>("#btn-quki-list")!.disabled, undefined, { timeout: 5000 });

  await page.click("#btn-quki-list");
  const list = page.locator("#view-list");
  await list.locator(".list-row-preview", { hasText: bodyA }).waitFor({ timeout: 5000 });
  await pressBack(page);
  assert((await visibleView(page)) === "editor", `${tag} Back from the list must return to the blank launch QuKi, got ${await visibleView(page)}`);
  assert((await editorBody(page)) === "", `${tag} the launch QuKi must still be blank`);
  assert(exitWarnings.length === 0, `${tag} Back from the list must not exit`);
  console.log(`${tag} PASS: launch -> list -> Back returns to the blank launch QuKi`);

  await pressBack(page);
  await page.waitForTimeout(200);
  assert(exitWarnings.length === 1, `${tag} Back from the blank launch QuKi must exit, got ${exitWarnings.length} exit attempts`);
  console.log(`${tag} PASS: Back from the blank launch QuKi exits`);

  await page.reload();
  await page.waitForSelector(".cm-content");
  await page.waitForFunction(() => !document.querySelector<HTMLButtonElement>("#btn-quki-list")!.disabled, undefined, { timeout: 5000 });
  exitWarnings.length = 0;
  await page.click("#btn-quki-list");
  await list.locator(".list-row-preview", { hasText: bodyA }).click({ timeout: 5000 });
  await waitForBody(page, bodyA);
  await pressBack(page);
  assert((await visibleView(page)) === "list", `${tag} Back from A must land on the list, got ${await visibleView(page)}`);
  await pressBack(page);
  await waitForBody(page, "");
  assert((await visibleView(page)) === "editor", `${tag} Back from the list must show the editor`);
  assert(exitWarnings.length === 0, `${tag} reaching the blank launch QuKi must not exit`);
  const focused = await page.evaluate(() => document.activeElement === (window as QukiWindow).qukiView.contentDOM);
  assert(focused, `${tag} the blank launch QuKi comes back ready for typing, like New`);
  const deleteDisabled = await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-delete")!.disabled);
  assert(deleteDisabled, `${tag} the blank QuKi must be unsaved (Delete greyed out), not A`);
  console.log(`${tag} PASS: launch -> list -> A -> Back -> list -> Back reloads the blank launch QuKi`);

  await pressBack(page);
  await page.waitForTimeout(200);
  assert(exitWarnings.length === 1, `${tag} Back from it then exits`);
  console.log(`${tag} PASS: and Back from it exits`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function backReturnsToABlankNewQuKi(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-back:new-blank]";
  const { page, done } = await openFreshApp(browser, url);
  const bodyA = "Back new-blank QuKi A";
  await typeQuKi(page, bodyA);
  await page.click("#btn-new-quki");
  await waitForBody(page, "");
  await page.click("#btn-new-quki");
  await page.click("#btn-new-quki");
  await page.click("#btn-quki-list");
  await page.locator("#view-list .list-row-preview", { hasText: bodyA }).waitFor({ timeout: 5000 });

  await pressBack(page);
  assert((await visibleView(page)) === "editor", `${tag} Back from the list must return to the blank QuKi, got ${await visibleView(page)}`);
  assert((await editorBody(page)) === "", `${tag} the blank QuKi started with New must come back blank`);
  const focused = await page.evaluate(() => document.activeElement === (window as QukiWindow).qukiView.contentDOM);
  assert(focused, `${tag} the blank QuKi comes back ready for typing, like New`);
  console.log(`${tag} PASS: a blank QuKi started with New and never typed into is a stop`);

  await pressBack(page);
  await waitForBody(page, bodyA);
  console.log(`${tag} PASS: pressing New again on an untyped blank QuKi added no stops; the next Back reaches A`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-back] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await backWalksQuKisAndTheListAndRestoresScroll(browser, url);
    await backSkipsSettingsTrashAndDeletedQuKis(browser, url);
    await backClosesTheHelpDialogFirst(browser, url);
    await backReturnsToABlankNewQuKi(browser, url);
    await backReturnsToTheBlankLaunchQuKiThenExits(browser, url);
    console.log("[e2e-back] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-back] FAILED:", err);
    process.exit(1);
  });
