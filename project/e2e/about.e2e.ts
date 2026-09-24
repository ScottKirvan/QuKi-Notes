import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type Browser, type Page } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectDir = path.join(__dirname, "..");
const distDir = path.join(projectDir, "dist");

const CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".png": "image/png",
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

function git(...args: string[]): string {
  return execFileSync("git", args, { cwd: projectDir, encoding: "utf-8" }).trim();
}

const expectedVersion = (JSON.parse(fs.readFileSync(path.join(projectDir, "package.json"), "utf-8")) as { version: string }).version;
const expectedCommit = git("rev-parse", "--short=7", "HEAD");
const expectedBranch = git("branch", "--show-current");
const expectedDirty = git("status", "--porcelain", "--untracked-files=no") !== "";

const DIALOG = "[role=dialog]";
const screenshotDir = process.env["QUKI_E2E_SCREENSHOTS"];

async function activeElementDescription(page: Page): Promise<string> {
  return page.evaluate(() => {
    const el = document.activeElement;
    return el === null ? "null" : `${el.tagName.toLowerCase()}${el.id ? `#${el.id}` : ""}${el.className ? `.${String(el.className).split(" ").join(".")}` : ""}`;
  });
}

async function assertDialogHidden(page: Page, name: string): Promise<void> {
  const visible = await page.locator(DIALOG).isVisible();
  assert(!visible, `${name}: the About dialog must be closed`);
}

async function openAbout(page: Page): Promise<void> {
  await page.click("#btn-help");
  await page.locator(DIALOG).waitFor({ state: "visible" });
}

async function assertFocusReturnedToHelp(page: Page, name: string): Promise<void> {
  const active = await activeElementDescription(page);
  assert(active.startsWith("button#btn-help"), `${name}: focus must return to the Help button, got ${active}`);
}

async function runScenario(browser: Browser, url: string, scheme: "light" | "dark"): Promise<void> {
  const tag = `[e2e-about:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 700 } });
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const page = await context.newPage();
  const consoleErrors: string[] = [];
  page.on("pageerror", (err) => consoleErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  const help = page.locator("#btn-help");
  assert(await help.isEnabled(), "the Help button must be enabled");
  assert((await help.getAttribute("aria-label")) === "Help", "the Help button keeps its Help label");
  await assertDialogHidden(page, "before opening");
  console.log(`${tag} PASS: Help button is enabled and the About dialog starts closed`);

  await openAbout(page);
  const dialog = page.locator(DIALOG);

  assert((await dialog.getAttribute("aria-modal")) === "true", "dialog must be aria-modal");
  const labelledBy = await dialog.getAttribute("aria-labelledby");
  assert(labelledBy !== null, "dialog must be labelled via aria-labelledby");
  const accessibleName = await page.locator(`#${labelledBy}`).textContent();
  assert(accessibleName === "QuKi Notes", `dialog's accessible name should be "QuKi Notes", got "${accessibleName}"`);
  const focusInside = await dialog.evaluate((el) => el.contains(document.activeElement));
  assert(focusInside, `focus must move into the dialog on open, got ${await activeElementDescription(page)}`);
  console.log(`${tag} PASS: dialog has role=dialog, aria-modal, a name of "QuKi Notes", and takes focus`);

  const icon = dialog.locator("img.about-icon");
  const iconFacts = await icon.evaluate((el) => {
    const img = el as HTMLImageElement;
    return { loaded: img.complete && img.naturalWidth > 0, alt: img.getAttribute("alt"), width: img.getBoundingClientRect().width };
  });
  assert(iconFacts.loaded, "the app icon must load");
  assert(iconFacts.alt === "", "the app icon is decorative next to the name and must have empty alt");
  assert(iconFacts.width === 64, `the app icon should render at 64px, got ${iconFacts.width}`);

  const versionText = await dialog.locator(".about-version").textContent();
  assert(versionText === `Version ${expectedVersion}`, `dialog must show "Version ${expectedVersion}", got "${versionText}"`);
  const buildText = (await dialog.locator(".about-build").textContent()) ?? "";
  const buildParts = buildText.split(" · ");
  if (expectedBranch !== "") {
    assert(buildParts[0] === expectedBranch, `dialog's branch must be "${expectedBranch}", got "${buildParts[0]}" in "${buildText}"`);
  }
  assert(/^\d{4}-\d\d-\d\d \d\d:\d\d UTC$/.test(buildParts[1] ?? ""), `build time must look like "YYYY-MM-DD HH:MM UTC", got "${buildParts[1]}"`);
  assert(buildParts.length === 2, `dialog must show only branch and build time (no commit hash, no uncommitted-changes flag), got "${buildText}"`);
  const timeHeight = await dialog.locator(".about-build-part", { hasText: " UTC" }).first().evaluate((el) => el.getBoundingClientRect().height);
  assert(timeHeight < 20, `the build time must not be split across lines, its box is ${timeHeight}px tall`);
  console.log(`${tag} PASS: dialog shows "${versionText}" and build "${buildText}"`);

  const colors = await dialog.evaluate((el) => {
    const probe = document.createElement("div");
    probe.style.background = "var(--modal-background)";
    probe.style.color = "var(--text-normal)";
    document.body.appendChild(probe);
    const probeStyle = getComputedStyle(probe);
    const result = {
      dialogBg: getComputedStyle(el).backgroundColor,
      dialogColor: getComputedStyle(el).color,
      surface: probeStyle.backgroundColor,
      text: probeStyle.color,
    };
    probe.remove();
    return result;
  });
  assert(colors.dialogBg === colors.surface && colors.dialogColor === colors.text, `dialog must use the --modal-background/--text-normal variables, got ${JSON.stringify(colors)}`);
  const surfaceChannels = (colors.surface.match(/\d+/g) ?? []).slice(0, 3).map(Number);
  const surfaceIsDark = surfaceChannels.every((c) => c < 64);
  assert(surfaceIsDark === (scheme === "dark"), `in ${scheme} mode the dialog surface ${colors.surface} must be ${scheme === "dark" ? "dark" : "light"}`);
  console.log(`${tag} PASS: dialog uses the theme tokens (${colors.surface} on ${colors.text})`);

  if (screenshotDir !== undefined) {
    fs.mkdirSync(screenshotDir, { recursive: true });
    await page.screenshot({ path: path.join(screenshotDir, `about-${scheme}.png`) });
  }

  await page.evaluate(() => navigator.clipboard.writeText("sentinel"));
  await dialog.locator(".about-copy").click();
  await page.waitForSelector(".toast:not([hidden])");
  const toastText = await page.textContent(".toast");
  assert(toastText === "Copied to clipboard.", `expected the usual copy toast, got "${toastText}"`);
  const clipboard = await page.evaluate(() => navigator.clipboard.readText());
  const expectedCopy = `QuKi Notes ${expectedVersion} (branch ${expectedBranch === "" ? "unknown" : expectedBranch}`;
  assert(clipboard.startsWith(expectedCopy), `clipboard must hold the full build string starting "${expectedCopy}", got "${clipboard}"`);
  assert(clipboard.endsWith(")"), `clipboard build string must be closed, got "${clipboard}"`);
  assert(!clipboard.includes("commit "), `clipboard must not include the commit hash, got "${clipboard}"`);
  assert(!clipboard.includes("uncommitted changes"), `clipboard must not include the uncommitted-changes flag, got "${clipboard}"`);
  const toastOnTop = await page.evaluate(() => {
    const toast = document.querySelector(".toast")!.getBoundingClientRect();
    const hit = document.elementFromPoint(toast.left + toast.width / 2, toast.top + toast.height / 2);
    return hit?.closest(".toast") !== null && hit?.closest(".toast") !== undefined;
  });
  assert(toastOnTop, "the copy toast must render above the dialog's backdrop, not under it");
  assert(await dialog.isVisible(), "copying must leave the dialog open");
  if (screenshotDir !== undefined) await page.screenshot({ path: path.join(screenshotDir, `about-${scheme}-copied.png`) });
  console.log(`${tag} PASS: tapping the version/build copied "${clipboard}" and toasted above the backdrop`);

  const expectedLinkRows: Array<{ row: string; title: string; description: string; label: string; url: string; accent: boolean }> = [
    { row: "docs", title: "Documentation", description: "Official guide and setup instructions.", label: "Visit", url: "https://www.scottkirvan.com/QuKi-Notes/", accent: true },
    { row: "discord", title: "Discord", description: "Chat with other QuKi-Notes users and get support.", label: "Join", url: "https://discord.gg/TN6XJSNK5Y", accent: false },
    { row: "github", title: "GitHub", description: "Source code, issues, and release notes.", label: "View", url: "https://github.com/ScottKirvan/QuKi-Notes", accent: false },
    { row: "kofi", title: "Buy me a coffee", description: "Show your love. Support QuKi-Notes and the author.", label: "Give", url: "https://ko-fi.com/ScottKirvan", accent: false },
  ];
  for (const expected of expectedLinkRows) {
    const row = dialog.locator(`.about-link-row:has(.about-link-btn[data-row="${expected.row}"])`);
    const title = await row.locator(".about-link-title").textContent();
    assert(title === expected.title, `${expected.row} link row title should be "${expected.title}", got "${title}"`);
    const description = await row.locator(".about-link-desc").textContent();
    assert(description === expected.description, `${expected.row} link row description should be "${expected.description}", got "${description}"`);
    const link = row.locator(".about-link-btn");
    const label = await link.textContent();
    assert(label === expected.label, `${expected.row} link button label should be "${expected.label}", got "${label}"`);
    const href = await link.getAttribute("href");
    assert(href === expected.url, `${expected.row} link href should be "${expected.url}", got "${href}"`);
    assert((await link.getAttribute("target")) === "_blank", `${expected.row} link must open externally (target=_blank)`);
    assert((await link.getAttribute("rel")) === "noopener noreferrer", `${expected.row} link must have rel="noopener noreferrer"`);
    const hasAccent = (await link.getAttribute("class"))?.includes("accent") ?? false;
    assert(hasAccent === expected.accent, `${expected.row} link's accent styling should be ${expected.accent}, got ${hasAccent}`);
    const iconChildCount = await row.locator(".about-link-icon").evaluate((el) => el.children.length + (el.textContent?.trim() ? 1 : 0));
    assert(iconChildCount > 0, `${expected.row} link row must render an icon`);
  }
  console.log(`${tag} PASS: all four Help-dialog link rows render with the expected title, description, label, url and styling`);

  await dialog.locator(".about-copy").focus();
  const focusOrder: string[] = [await activeElementDescription(page)];
  for (const key of ["Tab", "Tab", "Tab", "Tab", "Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab", "Shift+Tab"]) {
    await page.keyboard.press(key);
    focusOrder.push(await activeElementDescription(page));
  }
  const expectedOrder = [
    "button.about-copy",
    "a.about-link-btn.accent",
    "a.about-link-btn",
    "a.about-link-btn",
    "a.about-link-btn",
    "button.about-close",
    "a.about-link-btn",
    "a.about-link-btn",
    "a.about-link-btn",
    "a.about-link-btn.accent",
    "button.about-copy",
  ];
  assert(JSON.stringify(focusOrder) === JSON.stringify(expectedOrder), `Tab must cycle copy -> the 4 link buttons -> close -> back, Shift+Tab reverses it, inside the dialog; got ${focusOrder.join(" -> ")}`);
  console.log(`${tag} PASS: keyboard focus stays trapped in the dialog, cycling through all 4 link buttons (${focusOrder.join(" -> ")})`);

  await dialog.locator(".about-close").click();
  await assertDialogHidden(page, "after Close");
  await assertFocusReturnedToHelp(page, "after Close");
  console.log(`${tag} PASS: Close closes the dialog and returns focus to Help`);

  await openAbout(page);
  await page.keyboard.press("Escape");
  await assertDialogHidden(page, "after Escape");
  await assertFocusReturnedToHelp(page, "after Escape");
  console.log(`${tag} PASS: Escape closes the dialog and returns focus to Help`);

  await openAbout(page);
  await dialog.locator(".about-name").click();
  assert(await dialog.isVisible(), "tapping inside the dialog must not close it");
  await page.mouse.click(5, 5);
  await assertDialogHidden(page, "after tapping outside");
  await assertFocusReturnedToHelp(page, "after tapping outside");
  console.log(`${tag} PASS: tapping outside closes the dialog (tapping inside does not) and returns focus to Help`);

  await openAbout(page);
  await page.keyboard.press("Escape");
  await page.keyboard.press("Escape");
  await assertDialogHidden(page, "after a second Escape");
  await help.click();
  assert(await dialog.isVisible(), "the dialog must reopen after being closed");
  await page.keyboard.press("Escape");
  console.log(`${tag} PASS: the dialog reopens cleanly after every way of closing it`);

  assert(consoleErrors.length === 0, `page errors: ${consoleErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-about] serving dist/ at ${url}; expecting version ${expectedVersion}, commit ${expectedCommit}, branch "${expectedBranch}", dirty ${expectedDirty}`);
  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) {
      await runScenario(browser, url, scheme);
    }
    console.log("[e2e-about] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-about] FAILED:", err);
    process.exit(1);
  });
