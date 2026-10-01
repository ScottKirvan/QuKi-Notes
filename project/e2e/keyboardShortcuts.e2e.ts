import { chromium, type Browser } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

/**
 * BEHAVIOR_SPEC.md §4/§5: "Keyboard shortcuts — Windows and Linux only.
 * Ctrl+T sends. Ctrl+N creates a new QuKi." main.ts gates this on
 * window.electronPlatform, which is normally only set by Electron's preload
 * script (electron/src/preload.ts). Forced here via an init script instead
 * of actually launching Electron - matching main.ts's own runtime check,
 * which is a plain global read with no other Electron dependency - so this
 * runs against the ordinary chromium/dist build the rest of this suite
 * already uses.
 */
async function runPlatformGatedScenario(browser: Browser, url: string, platform: "win32" | "linux"): Promise<void> {
  const tag = `[e2e-keyboard-shortcuts:${platform}]`;
  const context = await browser.newContext();
  await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: url });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.addInitScript((forcedPlatform) => {
    (window as unknown as { electronPlatform: string }).electronPlatform = forcedPlatform;
  }, platform);

  await page.goto(url);
  await page.waitForSelector(".cm-content");

  const marker = `keyboard-shortcut send ${platform} ${Date.now()}`;
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(marker);

  await page.keyboard.press("Control+T");
  await page.waitForSelector(".toast:not([hidden])");
  const toastText = await page.textContent(".toast");
  assert(!!toastText && /copied to clipboard/i.test(toastText), `${tag} Ctrl+T should send (copy to clipboard), toast said: "${toastText}"`);
  const clipboardText = await page.evaluate(() => navigator.clipboard.readText());
  assert(clipboardText === marker, `${tag} Ctrl+T should have copied the live editor content, got: "${clipboardText}"`);
  console.log(`${tag} PASS: Ctrl+T sent the current QuKi`);

  await page.keyboard.press("Control+N");
  await page.waitForFunction(
    () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString() === "",
  );
  console.log(`${tag} PASS: Ctrl+N started a new, blank QuKi`);

  assert(pageErrors.length === 0, `${tag} page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

/**
 * On every other platform (web/PWA with no forced electronPlatform, i.e.
 * the ordinary build) these shortcuts must NOT fire - Ctrl+T/Ctrl+N stay
 * whatever the browser itself does with them, matching sendBtn's own gate.
 */
async function runUngatedScenario(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-keyboard-shortcuts:ungated]";
  const context = await browser.newContext();
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  const marker = `ungated marker ${Date.now()}`;
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(marker);

  await page.keyboard.press("Control+N");
  await page.waitForTimeout(300);
  const docAfter = await page.evaluate(
    () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
  );
  assert(docAfter === marker, `${tag} Ctrl+N must not start a new QuKi when electronPlatform is unset, doc was: "${docAfter}"`);
  console.log(`${tag} PASS: Ctrl+N is a no-op without a forced win32/linux electronPlatform`);

  assert(pageErrors.length === 0, `${tag} page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-keyboard-shortcuts] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await runPlatformGatedScenario(browser, url, "win32");
    await runPlatformGatedScenario(browser, url, "linux");
    await runUngatedScenario(browser, url);
    console.log("[e2e-keyboard-shortcuts] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-keyboard-shortcuts] FAILED:", err);
    process.exit(1);
  });
