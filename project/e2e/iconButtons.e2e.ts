import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type Browser, type Locator, type Page } from "playwright";
import { createServer as createViteServer } from "vite";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectDir = path.join(__dirname, "..");
const distDir = path.join(projectDir, "dist");

const CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".map": "application/json; charset=utf-8",
};

function serveDist(): Promise<{ server: http.Server; url: string }> {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(distDir)) {
      reject(new Error(`dist/ not found at ${distDir} - run "npm run build" first`));
      return;
    }
    const server = http.createServer((req, res) => {
      const reqPath = (req.url ?? "/").split("?")[0]!;
      const filePath = path.join(distDir, reqPath === "/" ? "index.html" : reqPath);
      if (!filePath.startsWith(distDir)) {
        res.writeHead(403).end();
        return;
      }
      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(404).end();
          return;
        }
        res.writeHead(200, { "content-type": CONTENT_TYPES[path.extname(filePath)] ?? "application/octet-stream" });
        res.end(data);
      });
    });
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (address === null || typeof address === "string") {
        reject(new Error("failed to bind server"));
        return;
      }
      resolve({ server, url: `http://127.0.0.1:${address.port}` });
    });
  });
}

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
}

interface ButtonFacts {
  ariaLabel: string | null;
  title: string;
  text: string;
  svgCount: number;
  svgAriaHidden: string | null;
  borderWidths: string[];
  width: number;
  height: number;
}

async function facts(button: Locator): Promise<ButtonFacts> {
  return button.evaluate((el) => {
    const style = getComputedStyle(el);
    const svg = el.querySelector("svg");
    const rect = el.getBoundingClientRect();
    return {
      ariaLabel: el.getAttribute("aria-label"),
      title: (el as HTMLElement).title,
      text: (el.textContent ?? "").trim(),
      svgCount: el.querySelectorAll("svg").length,
      svgAriaHidden: svg?.getAttribute("aria-hidden") ?? null,
      borderWidths: [style.borderTopWidth, style.borderRightWidth, style.borderBottomWidth, style.borderLeftWidth],
      width: rect.width,
      height: rect.height,
    };
  });
}

async function assertIconButton(button: Locator, name: string, expectedLabel?: string): Promise<ButtonFacts> {
  const f = await facts(button);
  assert(f.svgCount === 1, `${name}: expected exactly one <svg>, got ${f.svgCount}`);
  assert(f.svgAriaHidden === "true", `${name}: the icon must be aria-hidden, got ${String(f.svgAriaHidden)}`);
  assert(f.ariaLabel !== null && f.ariaLabel.length > 0, `${name}: must carry an aria-label`);
  if (expectedLabel !== undefined) assert(f.ariaLabel === expectedLabel, `${name}: aria-label should be "${expectedLabel}", got "${f.ariaLabel}"`);
  assert(f.text === "", `${name}: must not contain any text glyph, got "${f.text}"`);
  assert(f.borderWidths.every((w) => w === "0px"), `${name}: must have no border, got ${f.borderWidths.join("/")}`);
  return f;
}

interface WordButtonLook {
  text: string;
  svgCount: number;
  borderWidths: string[];
  padding: string;
  fontSize: string;
  borderRadius: string;
  cursor: string;
  width: number;
  height: number;
}

async function assertWordButton(
  button: Locator,
  name: string,
  expected: { text: string; padding: string; fontSize: string | null; borderRadius: string; width: number; height: number },
): Promise<void> {
  const look: WordButtonLook = await button.evaluate((el) => {
    const style = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return {
      text: (el.textContent ?? "").trim(),
      svgCount: el.querySelectorAll("svg").length,
      borderWidths: [style.borderTopWidth, style.borderRightWidth, style.borderBottomWidth, style.borderLeftWidth],
      padding: style.padding,
      fontSize: style.fontSize,
      borderRadius: style.borderTopLeftRadius,
      cursor: style.cursor,
      width: rect.width,
      height: rect.height,
    };
  });
  assert(look.text === expected.text, `${name}: must read "${expected.text}", got "${look.text}"`);
  assert(look.svgCount === 0, `${name}: must stay a word button with no icon, found ${look.svgCount} <svg>`);
  assert(look.borderWidths.every((w) => w === "1px"), `${name}: must keep its 1px border, got ${look.borderWidths.join("/")}`);
  assert(look.padding === expected.padding, `${name}: padding should be ${expected.padding}, got ${look.padding}`);
  if (expected.fontSize !== null) assert(look.fontSize === expected.fontSize, `${name}: font-size should be ${expected.fontSize}, got ${look.fontSize}`);
  assert(look.borderRadius === expected.borderRadius, `${name}: border-radius should be ${expected.borderRadius}, got ${look.borderRadius}`);
  assert(look.cursor === "pointer", `${name}: cursor should be pointer, got ${look.cursor}`);
  assert(Math.abs(look.width - expected.width) <= 2 && Math.abs(look.height - expected.height) <= 2, `${name}: size should be about ${expected.width}x${expected.height}, got ${look.width}x${look.height}`);
}

async function assertSwipeBackground(row: Locator, name: string): Promise<void> {
  const bg = row.locator(".list-row-swipe-bg");
  const info = await bg.evaluate((el) => {
    const svg = el.querySelector("svg");
    return {
      text: (el.textContent ?? "").trim(),
      svgCount: el.querySelectorAll("svg").length,
      ariaHidden: el.getAttribute("aria-hidden"),
      svgAriaHidden: svg?.getAttribute("aria-hidden") ?? null,
      stroke: svg ? getComputedStyle(svg).stroke : "",
      color: getComputedStyle(el).color,
    };
  });
  assert(info.svgCount === 1, `${name}: swipe background must hold one <svg>, got ${info.svgCount}`);
  assert(info.text === "", `${name}: swipe background must not hold the emoji/text, got "${info.text}"`);
  assert(info.ariaHidden === "true" && info.svgAriaHidden === "true", `${name}: swipe background icon must be aria-hidden`);
  assert(info.stroke === info.color, `${name}: icon stroke (${info.stroke}) must follow the surrounding text colour (${info.color}) via currentColor`);
}

async function assertMidSwipeIconVisible(page: Page, row: Locator, name: string): Promise<void> {
  const box = await row.boundingBox();
  assert(box !== null, `${name}: row has no box`);
  const y = box.y + box.height / 2;
  const startX = box.x + box.width - 10;
  await page.mouse.move(startX, y);
  await page.mouse.down();
  for (let i = 1; i <= 8; i++) {
    await page.mouse.move(startX - (box.width * 0.3 * i) / 8, y, { steps: 1 });
    await page.waitForTimeout(20);
  }
  await page.waitForTimeout(400);
  const geometry = await row.evaluate((el) => {
    const content = el.querySelector(".list-row-content")!.getBoundingClientRect();
    const svg = el.querySelector(".list-row-swipe-bg svg")!.getBoundingClientRect();
    const rowRect = el.getBoundingClientRect();
    return { contentRight: content.right, svgLeft: svg.left, svgRight: svg.right, svgWidth: svg.width, svgHeight: svg.height, svgMidY: svg.top + svg.height / 2, rowMidY: rowRect.top + rowRect.height / 2, rowRight: rowRect.right };
  });
  await page.mouse.up();
  await page.waitForTimeout(400);
  assert(geometry.svgLeft >= geometry.contentRight - 1, `${name}: mid-swipe the icon must sit in the revealed strip (icon left ${geometry.svgLeft}, row content right edge ${geometry.contentRight})`);
  assert(geometry.svgRight <= geometry.rowRight, `${name}: icon must stay inside the row`);
  assert(geometry.svgWidth === 20 && geometry.svgHeight === 20, `${name}: icon should be 20x20, got ${geometry.svgWidth}x${geometry.svgHeight}`);
  assert(Math.abs(geometry.svgMidY - geometry.rowMidY) < 1, `${name}: icon must be vertically centred in the row`);
}

async function assertHoverAndFocusFeedback(page: Page, button: Locator, name: string): Promise<void> {
  await page.mouse.move(0, 0);
  const restingBg = await button.evaluate((el) => getComputedStyle(el).backgroundColor);
  await button.hover();
  const hoverBg = await button.evaluate((el) => getComputedStyle(el).backgroundColor);
  assert(hoverBg !== restingBg, `${name}: hovering must tint the background (resting ${restingBg}, hover ${hoverBg})`);
  await page.mouse.move(0, 0);
}

async function assertKeyboardFocusRing(page: Page, buttonSelector: string, name: string): Promise<void> {
  // A key press first, so Chromium treats the programmatic focus as keyboard-driven (:focus-visible).
  await page.keyboard.press("Shift");
  await page.evaluate((selector) => document.querySelector<HTMLElement>(selector)!.focus(), buttonSelector);
  const ring = await page.evaluate((selector) => {
    const el = document.querySelector<HTMLElement>(selector)!;
    const style = getComputedStyle(el);
    return { focusVisible: el.matches(":focus-visible"), outlineStyle: style.outlineStyle, outlineWidth: style.outlineWidth };
  }, buttonSelector);
  assert(ring.focusVisible, `${name}: expected keyboard focus to match :focus-visible`);
  assert(ring.outlineStyle === "solid" && ring.outlineWidth === "2px", `${name}: keyboard focus must show a 2px outline, got ${ring.outlineStyle} ${ring.outlineWidth}`);
}

const OLD_BACK_SIZE = { width: 35.8, height: 31 };
const OLD_HEADER_ACTION_HEIGHT = 31;

async function runWebScenario(browser: Browser, url: string, scheme: "light" | "dark"): Promise<void> {
  const tag = `[e2e-icons:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 700 } });
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  const list = page.locator("#view-list");
  const settings = page.locator("#view-settings");
  const trash = page.locator("#view-trash");

  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(`IconE2E QuKi ${scheme} ${Date.now()}`);
  await page.waitForTimeout(2500);

  // --- Editor: app bar and formatting toolbar ---
  const appBarButtons = page.locator("#view-editor .app-bar-btn");
  const appBarCount = await appBarButtons.count();
  assert(appBarCount === 7, `expected 7 app bar buttons, got ${appBarCount}`);
  for (let i = 0; i < appBarCount; i++) {
    const f = await assertIconButton(appBarButtons.nth(i), `app bar button ${i}`);
    assert(f.width >= 32 && f.height >= 32, `app bar button ${i} must stay at least 32x32, got ${f.width}x${f.height}`);
  }
  const toolbarButtons = page.locator("#view-editor .toolbar-btn");
  const toolbarCount = await toolbarButtons.count();
  assert(toolbarCount === 10, `expected 10 toolbar buttons, got ${toolbarCount}`);
  for (let i = 0; i < toolbarCount; i++) {
    const f = await assertIconButton(toolbarButtons.nth(i), `toolbar button ${i}`);
    assert(f.width >= 28 && f.height >= 28, `toolbar button ${i} must stay at least 28x28, got ${f.width}x${f.height}`);
  }
  await assertHoverAndFocusFeedback(page, toolbarButtons.nth(0), "toolbar Bold button");
  await assertHoverAndFocusFeedback(page, page.locator("#btn-settings"), "editor app bar Settings button");
  await assertKeyboardFocusRing(page, "#btn-settings", "editor app bar Settings button");
  console.log(`${tag} PASS: editor app bar (7) and formatting toolbar (10) buttons are icon-only SVG, labelled, borderless, with hover tint`);

  // --- List screen ---
  await page.click("#btn-quki-list");
  await list.locator(".list-row").first().waitFor({ timeout: 5000 });
  await page.waitForTimeout(300);
  const listBack = await assertIconButton(list.locator(".back-btn"), "list back button", "Back to editor");
  const listNew = await assertIconButton(list.locator(".new-btn"), "list New button", "New");
  const listSettings = await assertIconButton(list.locator(".settings-btn"), "list Settings button", "Settings");
  for (const [name, f] of [["list back", listBack], ["list New", listNew], ["list Settings", listSettings]] as const) {
    assert(f.height >= OLD_HEADER_ACTION_HEIGHT, `${name} must not be shorter than the old ${OLD_HEADER_ACTION_HEIGHT}px, got ${f.height}`);
  }
  assert(listBack.width >= OLD_BACK_SIZE.width, `list back button must not be narrower than the old ${OLD_BACK_SIZE.width}px, got ${listBack.width}`);
  const listTitles = await list.locator(".back-btn, .new-btn, .settings-btn").evaluateAll((els) => els.map((el) => (el as HTMLElement).title));
  assert(listTitles.join("|") === "Back to editor|New|Settings", `list buttons must carry tooltips matching their labels, got ${listTitles.join("|")}`);
  await assertHoverAndFocusFeedback(page, list.locator(".back-btn"), "list back button");
  await assertKeyboardFocusRing(page, "#view-list .back-btn", "list back button");
  await assertSwipeBackground(list.locator(".list-row").first(), "list row");
  await assertMidSwipeIconVisible(page, list.locator(".list-row").first(), "list row");
  console.log(`${tag} PASS: list header back/New/Settings are icon-only SVG, labelled, borderless, focusable; swipe background holds a currentColor SVG, visible mid-swipe`);

  // --- New (list header) still creates a fresh QuKi in the editor ---
  await list.locator(".new-btn").click();
  await page.waitForSelector(".cm-content");
  await page.waitForFunction(() => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString() === "");
  console.log(`${tag} PASS: the icon New button still starts a blank QuKi`);

  // --- Back returns to the editor ---
  await page.click("#btn-quki-list");
  await list.locator(".list-row").first().waitFor({ timeout: 5000 });
  await list.locator(".back-btn").click();
  await page.waitForFunction(() => !document.querySelector<HTMLElement>("#view-editor")!.hidden);
  console.log(`${tag} PASS: list back button returns to the editor`);

  // --- Settings screen + back ---
  await page.click("#btn-quki-list");
  await list.locator(".list-row").first().waitFor({ timeout: 5000 });
  await list.locator(".settings-btn").click();
  await settings.locator(".trash-btn").waitFor();
  await page.waitForTimeout(300);
  const settingsBack = await assertIconButton(settings.locator(".back-btn"), "settings back button", "Back");
  assert(settingsBack.width >= OLD_BACK_SIZE.width && settingsBack.height >= OLD_BACK_SIZE.height, `settings back must not shrink, got ${settingsBack.width}x${settingsBack.height}`);
  await assertKeyboardFocusRing(page, "#view-settings .back-btn", "settings back button");

  // --- Trash screen: put one QuKi in Trash via the list swipe, then look at it ---
  await settings.locator(".back-btn").click();
  await list.locator(".list-row").first().waitFor({ timeout: 5000 });
  await page.waitForTimeout(300);
  const row = list.locator(".list-row").first();
  const box = await row.boundingBox();
  assert(box !== null, "row has no box");
  const y = box.y + box.height / 2;
  const startX = box.x + box.width - 10;
  await page.mouse.move(startX, y);
  await page.mouse.down();
  for (let i = 1; i <= 12; i++) await page.mouse.move(startX - (box.width * 0.8 * i) / 12, y, { steps: 1 });
  await page.mouse.up();
  const toastText = await page.waitForSelector(".toast:not([hidden])").then((el) => el.textContent());
  assert(toastText === "QuKi moved to Trash.", `swipe-to-delete must still work with the icon background, toast was "${toastText}"`);
  console.log(`${tag} PASS: swipe-to-delete still deletes the row and shows the Trash toast`);

  await list.locator(".settings-btn").click();
  await settings.locator(".trash-btn").click();
  await trash.locator(".list-row").first().waitFor({ timeout: 5000 });
  await page.waitForTimeout(300);
  const trashBack = await assertIconButton(trash.locator(".back-btn"), "trash back button", "Back to Settings");
  assert(trashBack.width >= OLD_BACK_SIZE.width && trashBack.height >= OLD_BACK_SIZE.height, `trash back must not shrink, got ${trashBack.width}x${trashBack.height}`);
  await assertWordButton(trash.locator(".empty-trash-btn"), "Empty Trash button", {
    text: "Empty Trash",
    padding: "6px 12px",
    fontSize: "13px",
    borderRadius: "6px",
    width: 95.4,
    height: 31,
  });
  await assertSwipeBackground(trash.locator(".list-row").first(), "trash row");
  await assertMidSwipeIconVisible(page, trash.locator(".list-row").first(), "trash row");
  console.log(`${tag} PASS: trash back button and the trash row swipe background are icon-only SVG, labelled, borderless; Empty Trash is still the bordered word button`);

  // --- Empty Trash still asks first: cancel keeps the row, confirm empties ---
  await trash.locator(".empty-trash-btn").click();
  await page.waitForSelector(".confirm-dialog");
  const confirmTitle = await page.textContent(".confirm-title");
  assert(confirmTitle === "Empty Trash?", `Empty Trash must still ask for confirmation, got "${confirmTitle}"`);
  await page.click(".confirm-cancel");
  await page.waitForFunction(() => document.querySelector<HTMLElement>(".confirm-overlay")!.hidden);
  assert((await trash.locator(".list-row").count()) === 1, "cancelling Empty Trash must keep the row");
  await trash.locator(".empty-trash-btn").click();
  await page.waitForSelector(".confirm-dialog");
  await page.click(".confirm-confirm");
  await trash.locator(".empty-state").waitFor({ timeout: 5000 });
  console.log(`${tag} PASS: Empty Trash still confirms; cancel keeps the row, confirm empties Trash`);

  // --- Back buttons navigate: Trash -> Settings -> List ---
  await trash.locator(".back-btn").click();
  await settings.locator(".trash-btn").waitFor();
  assert(await settings.isVisible(), "trash back button must return to Settings");
  await settings.locator(".back-btn").click();
  await list.locator(".search-input").waitFor();
  assert(await list.isVisible(), "settings back button must return to the list");
  console.log(`${tag} PASS: trash back -> Settings, settings back -> list`);

  await context.close();
}

async function runOverlayScenario(browser: Browser, devUrl: string, scheme: "light" | "dark"): Promise<void> {
  const tag = `[e2e-icons:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 700 } });
  const page = await context.newPage();
  await page.goto(devUrl);
  await page.waitForSelector(".cm-content");

  // The Electron setup screen and the Android permission screen only exist
  // inside their platform wrappers, so the real view modules are driven
  // directly through the dev server rather than through the app's own boot.
  await page.evaluate(async () => {
    const setupModule = await import("/src/screens/setupView.ts");
    const permissionModule = await import("/src/screens/androidPermissionView.ts");
    const host = document.querySelector("#overlay-host")!;
    const w = window as unknown as Record<string, unknown>;
    w.__cancelResult = "pending";
    w.__grantClicks = 0;
    const api = { getState: async () => ({}), chooseFilesystem: async () => null, chooseAppStorage: async () => "x", quit: async () => {} };
    const setupView = setupModule.createSetupView(host as HTMLElement, api as never);
    w.__setupView = setupView;
    w.__permissionView = permissionModule.createAndroidPermissionView(host as HTMLElement, () => {
      (w.__grantClicks as number)++;
    });
    void setupView.show({ cancelable: false });
  });

  const cancel = page.locator(".setup-cancel-btn");
  assert(!(await cancel.isVisible()), "the setup cancel button must stay hidden on first launch (cancelable: false)");
  await page.evaluate(() => {
    const w = window as unknown as { __setupView: { show(o: { cancelable: boolean }): Promise<string | null> }; __cancelResult: unknown };
    void w.__setupView.show({ cancelable: true }).then((result) => {
      w.__cancelResult = result;
    });
  });
  assert(await cancel.isVisible(), "the setup cancel button must show when cancelable");
  const cancelFacts = await assertIconButton(cancel, "setup cancel button", "Cancel");
  assert(cancelFacts.width >= OLD_BACK_SIZE.width && cancelFacts.height >= OLD_BACK_SIZE.height, `setup cancel must not shrink, got ${cancelFacts.width}x${cancelFacts.height}`);
  const overlap = await page.evaluate(() => {
    const c = document.querySelector(".setup-cancel-btn")!.getBoundingClientRect();
    const t = document.querySelector(".setup-title")!.getBoundingClientRect();
    return c.bottom > t.top && c.top < t.bottom && c.right > t.left && c.left < t.right;
  });
  assert(!overlap, "the borderless cancel icon must not sit on top of the setup title");
  await cancel.click();
  const cancelResult = await page.evaluate(() => (window as unknown as { __cancelResult: unknown }).__cancelResult);
  assert(cancelResult === null, `cancel must still resolve the setup screen with null, got ${String(cancelResult)}`);
  console.log(`${tag} PASS: setup cancel is an icon-only SVG, labelled, borderless, clear of the title, and still cancels`);

  await page.evaluate(() => (window as unknown as { __permissionView: { render(s: string): void } }).__permissionView.render("needs-permission"));
  const grant = page.locator(".android-permission-btn");
  await assertWordButton(grant, "Grant access button", {
    text: "Grant access",
    padding: "12px 20px",
    fontSize: null,
    borderRadius: "8px",
    width: 130.4,
    height: 47,
  });
  const copy = await page.locator(".android-permission-panel").evaluate((el) => ({
    title: el.querySelector("h1")!.textContent,
    body: (el.querySelector(".android-permission-body")!.textContent ?? "").replace(/\s+/g, " ").trim(),
  }));
  assert(copy.title === "QuKi Notes needs access to your files", `permission title copy changed: "${copy.title}"`);
  assert(
    copy.body === `To save your QuKis as files in your device's Documents folder, QuKi Notes needs "Allow management of all files" permission. Grant it on the next screen, then switch back to QuKi Notes.`,
    `permission body copy changed: "${copy.body}"`,
  );
  await grant.click();
  const clicks = await page.evaluate(() => (window as unknown as { __grantClicks: number }).__grantClicks);
  assert(clicks === 1, `Grant access must still trigger the request flow once, got ${clicks}`);
  await page.evaluate(() => (window as unknown as { __permissionView: { render(s: string): void } }).__permissionView.render("waiting-for-settings"));
  assert(await grant.isDisabled(), "Grant access must be disabled while waiting for Settings");
  console.log(`${tag} PASS: Grant access is still the bordered word button, copy unchanged, still triggers the request and disables while waiting`);

  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-icons] serving dist/ at ${url}`);
  const vite = await createViteServer({ root: projectDir, logLevel: "silent", server: { host: "127.0.0.1", port: 0 } });
  await vite.listen();
  const viteAddress = vite.httpServer?.address();
  assert(viteAddress !== null && viteAddress !== undefined && typeof viteAddress !== "string", "vite dev server failed to bind");
  const devUrl = `http://127.0.0.1:${viteAddress.port}`;

  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) {
      await runWebScenario(browser, url, scheme);
      await runOverlayScenario(browser, devUrl, scheme);
    }
    console.log("[e2e-icons] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
    await vite.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-icons] FAILED:", err);
    process.exit(1);
  });
