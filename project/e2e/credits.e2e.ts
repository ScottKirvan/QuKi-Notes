import * as fs from "node:fs";
import * as path from "node:path";

import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type QukiWindow = typeof window & { qukiSystemBack: () => Promise<void> };

const ABOUT = ".about-dialog";
const CREDITS = ".credits-dialog";
const VIEWPORT = ".credits-viewport";
const TRACK = ".credits-track";
const screenshotDir = process.env["QUKI_E2E_SCREENSHOTS"];

const EXPECTED_FOOTER = [
  { key: "whats-new", label: "What's new", href: "https://github.com/ScottKirvan/QuKi-Notes/releases" },
  { key: "credits", label: "Credits", href: null },
  { key: "privacy", label: "Privacy", href: "https://www.scottkirvan.com/QuKi-Notes/privacy" },
  { key: "github", label: "GitHub", href: "https://github.com/ScottKirvan/QuKi-Notes" },
];

async function openAbout(page: Page): Promise<void> {
  await page.click("#btn-help");
  await page.locator(ABOUT).waitFor({ state: "visible" });
}

async function openCredits(page: Page): Promise<void> {
  await page.locator('.about-footer-icon[data-footer="credits"]').click();
  await page.locator(CREDITS).waitFor({ state: "visible" });
}

async function rollingState(page: Page): Promise<{ animations: number; rolling: boolean; isStatic: boolean }> {
  return page.evaluate(
    ([track, viewport]) => ({
      animations: document.querySelector(track!)!.getAnimations().length,
      rolling: document.querySelector(viewport!)!.classList.contains("is-rolling"),
      isStatic: document.querySelector(viewport!)!.classList.contains("is-static"),
    }),
    [TRACK, VIEWPORT],
  );
}

async function assertRolling(page: Page, what: string): Promise<void> {
  await page.waitForFunction((track) => document.querySelector(track)!.getAnimations().length === 1, TRACK, { timeout: 2000 }).catch(() => undefined);
  const state = await rollingState(page);
  assert(state.animations === 1 && state.rolling && !state.isStatic, `${what}: the credits must be rolling, got ${JSON.stringify(state)}`);
}

async function assertStopped(page: Page, what: string): Promise<void> {
  await page.waitForFunction((track) => document.querySelector(track)!.getAnimations().length === 0, TRACK, { timeout: 2000 }).catch(() => undefined);
  const state = await rollingState(page);
  assert(state.animations === 0 && !state.rolling && state.isStatic, `${what}: the roll must have stopped, got ${JSON.stringify(state)}`);
}

async function trackTop(page: Page): Promise<number> {
  return page.evaluate((track) => document.querySelector(track)!.getBoundingClientRect().top, TRACK);
}

async function scrollable(page: Page): Promise<{ scrollHeight: number; clientHeight: number; overflowY: string }> {
  return page.evaluate((viewport) => {
    const el = document.querySelector(viewport)!;
    return { scrollHeight: el.scrollHeight, clientHeight: el.clientHeight, overflowY: getComputedStyle(el).overflowY };
  }, VIEWPORT);
}

async function scrollTop(page: Page): Promise<number> {
  return page.evaluate((viewport) => document.querySelector(viewport)!.scrollTop, VIEWPORT);
}

async function stopsRolling(page: Page, tag: string, how: string, act: () => Promise<void>): Promise<void> {
  await openAbout(page);
  await openCredits(page);
  await assertRolling(page, `${tag} before ${how}`);
  await act();
  await assertStopped(page, `${tag} after ${how}`);
  const box = await scrollable(page);
  assert(box.overflowY === "auto" && box.scrollHeight > box.clientHeight, `${tag} after ${how}: the stopped list must scroll, got ${JSON.stringify(box)}`);
  await page.keyboard.press("Escape");
  await page.keyboard.press("Escape");
  await page.locator(ABOUT).waitFor({ state: "hidden" });
  console.log(`${tag} PASS: ${how} stops the roll and leaves a scrollable list`);
}

async function runScenario(browser: Browser, url: string, scheme: "light" | "dark"): Promise<void> {
  const tag = `[e2e-credits:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 360, height: 640 }, reducedMotion: "no-preference" });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  await openAbout(page);
  const about = page.locator(ABOUT);
  const footer = about.locator(".about-footer .about-footer-icon");
  assert((await footer.count()) === EXPECTED_FOOTER.length, `the footer must hold ${EXPECTED_FOOTER.length} icons, got ${await footer.count()}`);
  for (const [index, expected] of EXPECTED_FOOTER.entries()) {
    const item = footer.nth(index);
    assert((await item.getAttribute("data-footer")) === expected.key, `footer icon ${index} must be ${expected.key}`);
    assert((await item.getAttribute("aria-label")) === expected.label, `${expected.key}: aria-label must be "${expected.label}"`);
    assert((await item.getAttribute("title")) === expected.label, `${expected.key}: title must be "${expected.label}"`);
    assert((await item.locator("svg").count()) === 1, `${expected.key}: must draw one icon`);
    const box = (await item.boundingBox())!;
    assert(box.width >= 44 && box.height >= 44, `${expected.key}: touch target must be at least 44x44, got ${box.width}x${box.height}`);
    if (expected.href === null) {
      assert((await item.evaluate((el) => el.tagName)) === "BUTTON", `${expected.key} must be a button`);
    } else {
      assert((await item.getAttribute("href")) === expected.href, `${expected.key}: href must be ${expected.href}, got ${await item.getAttribute("href")}`);
      assert((await item.getAttribute("target")) === "_blank" && (await item.getAttribute("rel")) === "noopener noreferrer", `${expected.key} must open externally`);
    }
  }
  assert((await about.locator('.about-link-btn[data-row="report"]').count()) === 1, "the Report a problem row replaces the GitHub row");
  assert((await about.locator('.about-link-btn[data-row="github"]').count()) === 0, "GitHub is in the footer only, not also a link row");
  const aboutBox = (await about.boundingBox())!;
  assert(aboutBox.x >= 0 && aboutBox.x + aboutBox.width <= 360 && aboutBox.y >= 0 && aboutBox.y + aboutBox.height <= 640, `About must fit a 360x640 phone, got ${JSON.stringify(aboutBox)}`);
  console.log(`${tag} PASS: footer icons present with the right labels, hrefs and 44px targets; Report row in place of the GitHub row; About fits a phone`);
  if (screenshotDir !== undefined) {
    fs.mkdirSync(screenshotDir, { recursive: true });
    await page.screenshot({ path: path.join(screenshotDir, `about-footer-${scheme}-360.png`) });
  }

  await page.locator('.about-footer-icon[data-footer="credits"]').click();
  const credits = page.locator(CREDITS);
  await credits.waitFor({ state: "visible" });
  assert((await credits.getAttribute("aria-modal")) === "true", "Credits must be aria-modal");
  assert((await page.locator("#credits-title").textContent()) === "Credits", "Credits must be named Credits");
  const text = (await credits.textContent()) ?? "";
  for (const expected of ["Created by", "Scott Kirvan", "Inspired by", "Zibaldone", "Built with", "CodeMirror", "not affiliated with or endorsed by"]) {
    assert(text.includes(expected), `Credits must show "${expected}"`);
  }
  const links = await credits.locator("a.credits-name").evaluateAll((els) =>
    els.map((el) => ({ href: (el as HTMLAnchorElement).href, target: el.getAttribute("target"), rel: el.getAttribute("rel") })),
  );
  assert(
    links.length > 5 && links.every((l) => l.href.startsWith("https://") && l.target === "_blank" && l.rel === "noopener noreferrer"),
    `credits links must be https and open externally, got ${JSON.stringify(links)}`,
  );
  assert((await page.evaluate(() => document.activeElement?.className)) === "credits-close", "Credits takes focus on its Close button");
  await assertRolling(page, `${tag} on open`);
  await page.waitForTimeout(300);
  const topA = await trackTop(page);
  await page.waitForTimeout(1200);
  const topB = await trackTop(page);
  assert(topA - topB > 10 && topA - topB < 120, `the list must roll up steadily, moved ${topA - topB}px in 1.2s`);
  const creditsBox = (await credits.boundingBox())!;
  assert(
    creditsBox.x >= 0 && creditsBox.x + creditsBox.width <= 360 && creditsBox.y >= 0 && creditsBox.y + creditsBox.height <= 640,
    `Credits must fit a 360x640 phone, got ${JSON.stringify(creditsBox)}`,
  );
  const closeBox = (await credits.locator(".credits-close").boundingBox())!;
  assert(closeBox.height >= 44, `Credits' Close must be a 44px target, got ${closeBox.height}`);
  if (screenshotDir !== undefined) await page.screenshot({ path: path.join(screenshotDir, `credits-${scheme}-360.png`) });
  console.log(`${tag} PASS: Credits opens from the footer, lists sections, notice and external https links, rolls up, fits a phone`);

  await page.keyboard.press("Escape");
  await credits.waitFor({ state: "hidden" });
  assert(await about.isVisible(), "Escape on Credits must leave About open");
  const afterEsc = await page.evaluate(() => (document.activeElement as HTMLElement | null)?.dataset["footer"]);
  assert(afterEsc === "credits", `closing Credits returns focus to its footer button, got ${afterEsc}`);
  await page.keyboard.press("Escape");
  await about.waitFor({ state: "hidden" });
  console.log(`${tag} PASS: Escape closes Credits first, then About`);

  await openAbout(page);
  await openCredits(page);
  await page.evaluate(() => (window as QukiWindow).qukiSystemBack());
  await credits.waitFor({ state: "hidden" });
  assert(await about.isVisible(), "system Back on Credits must leave About open");
  await page.evaluate(() => (window as QukiWindow).qukiSystemBack());
  await about.waitFor({ state: "hidden" });
  console.log(`${tag} PASS: system Back closes Credits, then About`);

  await openAbout(page);
  await openCredits(page);
  await page.mouse.click(5, 5);
  assert(!(await credits.isVisible()), "tapping the backdrop closes Credits");
  assert(await about.isVisible(), "tapping the Credits backdrop leaves About open");
  await page.keyboard.press("Escape");

  await stopsRolling(page, tag, "a wheel scroll", async () => {
    await page.mouse.move(180, 300);
    await page.mouse.wheel(0, 120);
  });
  await stopsRolling(page, tag, "a click on the list", async () => {
    await page.locator(".credits-title").first().click({ force: true });
  });
  await stopsRolling(page, tag, "ArrowDown", async () => {
    await page.keyboard.press("ArrowDown");
  });

  await openAbout(page);
  await openCredits(page);
  await page.keyboard.press("ArrowDown");
  await page.mouse.move(180, 300);
  await page.mouse.wheel(0, 200);
  await page.waitForTimeout(200);
  assert((await scrollTop(page)) > 0, `the stopped list must scroll with the wheel, scrollTop is ${await scrollTop(page)}`);
  if (screenshotDir !== undefined) await page.screenshot({ path: path.join(screenshotDir, `credits-stopped-${scheme}-360.png`) });
  await page.keyboard.press("Escape");
  await openCredits(page);
  await assertRolling(page, `${tag} on reopen`);
  assert((await scrollTop(page)) === 0, "reopening starts again from the top");
  await page.keyboard.press("Escape");
  await page.keyboard.press("Escape");
  console.log(`${tag} PASS: the stopped list scrolls, and reopening rolls again from the top`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function reducedMotion(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-credits:reduced-motion]";
  const context = await browser.newContext({ viewport: { width: 360, height: 640 }, reducedMotion: "reduce" });
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await openAbout(page);
  await openCredits(page);
  await assertStopped(page, `${tag} on open`);
  const box = await scrollable(page);
  assert(box.overflowY === "auto" && box.scrollHeight > box.clientHeight, `${tag} the list must be a plain scrollable list, got ${JSON.stringify(box)}`);
  const opacity = await page.evaluate((track) => getComputedStyle(document.querySelector(track)!).opacity, TRACK);
  assert(opacity === "1", `${tag} the list must be fully visible, opacity ${opacity}`);
  const before = await trackTop(page);
  await page.waitForTimeout(500);
  assert((await trackTop(page)) === before, `${tag} the list must not move on its own`);
  await page.mouse.move(180, 300);
  await page.mouse.wheel(0, 200);
  await page.waitForTimeout(200);
  assert((await scrollTop(page)) > 0, `${tag} the list must scroll`);
  console.log(`${tag} PASS: with reduced motion the credits never roll and are a plain scrollable list`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) await runScenario(browser, url, scheme);
    await reducedMotion(browser, url);
    console.log("[e2e-credits] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-credits] FAILED:", err);
    process.exit(1);
  });
