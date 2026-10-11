import { chromium, type Browser, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

type QukiView = {
  state: { doc: { length: number }; selection: { main: { head: number } } };
  dispatch(spec: unknown): void;
  contentDOM: HTMLElement;
  coordsAtPos(pos: number): { top: number; bottom: number; left: number; right: number } | null;
};
type WindowWithQukiView = typeof window & { qukiView: QukiView };

const TAG = "[e2e-wordCount]";
const LONG_QUKI = Array.from({ length: 80 }, (_, i) => `line number ${i + 1} with some text that runs right across`).join("\n");

async function readout(page: Page): Promise<{ visible: boolean; text: string }> {
  return page.evaluate(() => {
    const el = document.querySelector<HTMLElement>(".word-count");
    return { visible: !!el && !el.hidden && el.getBoundingClientRect().height > 0, text: el?.textContent ?? "" };
  });
}

async function waitForText(page: Page, expected: string, what: string): Promise<void> {
  try {
    await page.waitForFunction((t) => document.querySelector(".word-count")?.textContent === t, expected, { timeout: 3000 });
  } catch {
    const got = await readout(page);
    throw new Error(`ASSERTION FAILED: ${what}: expected "${expected}", got "${got.text}"`);
  }
}

async function setWordCount(page: Page, on: boolean): Promise<void> {
  await page.click("#btn-settings");
  const toggle = page.locator("#view-settings .word-count-toggle");
  await toggle.waitFor({ state: "visible" });
  if ((await toggle.isChecked()) !== on) await toggle.click();
  await page.click("#view-settings .back-btn");
  await page.waitForTimeout(400);
}

async function setDoc(page: Page, text: string): Promise<void> {
  await page.evaluate((text) => {
    const view = (window as WindowWithQukiView).qukiView;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: text.length }, scrollIntoView: true });
  }, text);
  await page.waitForTimeout(300);
}

interface Placement {
  readout: DOMRect;
  host: DOMRect;
  toolbarTop: number | null;
  caret: { top: number; bottom: number; left: number; right: number } | null;
}

async function placement(page: Page): Promise<Placement> {
  return page.evaluate(() => {
    const view = (window as WindowWithQukiView).qukiView;
    const toolbar = document.querySelector<HTMLElement>(".formatting-toolbar")!;
    const toolbarBox = toolbar.getBoundingClientRect();
    return {
      readout: document.querySelector(".word-count")!.getBoundingClientRect().toJSON() as DOMRect,
      host: document.querySelector("#editor-host")!.getBoundingClientRect().toJSON() as DOMRect,
      toolbarTop: toolbarBox.height > 0 ? toolbarBox.top : null,
      caret: view.coordsAtPos(view.state.selection.main.head),
    };
  });
}

async function mainScenario(browser: Browser, url: string): Promise<void> {
  const context = await browser.newContext({ viewport: { width: 400, height: 600 } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  assert(!(await readout(page)).visible, "the count is off by default");
  console.log(`${TAG} PASS: off by default`);

  await setWordCount(page, true);
  assert((await readout(page)).visible, "turning it on in Settings shows the count");
  await waitForText(page, "0 words · 0 characters", "a blank QuKi");
  console.log(`${TAG} PASS: turning it on in Settings shows it straight away`);

  await clickFirstLine(page);
  await page.keyboard.type("hello world");
  await waitForText(page, "2 words · 11 characters", "after typing");
  await page.keyboard.press("Enter");
  await page.keyboard.type("- **bold** item");
  await waitForText(page, "4 words · 27 characters", "after typing a list item");
  console.log(`${TAG} PASS: the count updates live while typing, markers count as characters but not words`);

  let p = await placement(page);
  assert(p.toolbarTop !== null, "the toolbar shows while editing");
  assert(Math.abs(p.readout.bottom - (p.toolbarTop - 4)) <= 1, `in edit mode the count sits just above the toolbar: bottom ${p.readout.bottom}, toolbar top ${p.toolbarTop}`);
  assert(p.readout.right <= p.host.right - 7 && p.readout.right >= p.host.right - 30, `the count sits at the right edge: ${p.readout.right} vs ${p.host.right}`);
  console.log(`${TAG} PASS: in edit mode it sits in the lower right, just above the toolbar`);

  await setDoc(page, LONG_QUKI);
  await page.keyboard.type(" more");
  await page.waitForTimeout(300);
  p = await placement(page);
  assert(p.caret !== null, "the caret is on screen");
  assert(p.caret.bottom <= p.readout.top, `the caret (bottom ${p.caret.bottom}) must stay above the count (top ${p.readout.top}) while typing at the end of a long QuKi`);
  console.log(`${TAG} PASS: typing at the bottom of a long QuKi keeps the caret clear of the count`);

  await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
  await page.locator(".formatting-toolbar").waitFor({ state: "hidden" });
  await page.waitForTimeout(200);
  p = await placement(page);
  assert((await readout(page)).visible, "the count still shows in reading mode");
  assert(Math.abs(p.readout.bottom - (p.host.bottom - 4)) <= 1, `in reading mode the count drops to the bottom edge: bottom ${p.readout.bottom}, editor bottom ${p.host.bottom}`);
  console.log(`${TAG} PASS: in reading mode it shows at the bottom right`);

  await page.reload();
  await page.waitForSelector(".cm-content");
  await page.waitForTimeout(300);
  assert((await readout(page)).visible, "the setting persists across a reload");
  await setWordCount(page, false);
  assert(!(await readout(page)).visible, "turning it off hides the count");
  await page.reload();
  await page.waitForSelector(".cm-content");
  await page.waitForTimeout(300);
  assert(!(await readout(page)).visible, "off persists across a reload");
  console.log(`${TAG} PASS: on and off persist across reloads`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

function luminance(rgb: string): number {
  const [r, g, b] = (rgb.match(/[\d.]+/g) ?? []).map(Number);
  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
}

async function colourScenario(browser: Browser, url: string, scheme: "dark" | "light"): Promise<void> {
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 400, height: 600 } });
  await context.addInitScript(() => localStorage.setItem("quki.settings.showWordCount", "true"));
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForSelector(".word-count");
  const colours = await page.evaluate(() => {
    const el = document.querySelector<HTMLElement>(".word-count")!;
    const body = getComputedStyle(document.body);
    const resolve = (name: string): string => {
      const probe = document.createElement("div");
      probe.style.color = `var(${name})`;
      document.body.appendChild(probe);
      const value = getComputedStyle(probe).color;
      probe.remove();
      return value;
    };
    return {
      background: getComputedStyle(el).backgroundColor,
      color: getComputedStyle(el).color,
      editorBackground: body.backgroundColor,
      expectedBackground: resolve("--background-primary-alt"),
      expectedColor: resolve("--text-muted"),
    };
  });
  assert(colours.background === colours.expectedBackground, `${scheme}: background comes from --background-primary-alt (${colours.background} vs ${colours.expectedBackground})`);
  assert(colours.color === colours.expectedColor, `${scheme}: text comes from --text-muted (${colours.color} vs ${colours.expectedColor})`);
  assert(colours.background !== colours.editorBackground, `${scheme}: the count's background stands apart from the editor's`);
  const light = luminance(colours.color) > luminance(colours.background);
  assert(scheme === "dark" ? light : !light, `${scheme}: expected ${scheme === "dark" ? "light text on a dark" : "dark text on a light"} background, got ${colours.color} on ${colours.background}`);
  console.log(`${TAG} PASS: ${scheme} mode shows ${scheme === "dark" ? "light text on a dark" : "dark text on a light"} background from the theme`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    await mainScenario(browser, url);
    await colourScenario(browser, url, "dark");
    await colourScenario(browser, url, "light");
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
