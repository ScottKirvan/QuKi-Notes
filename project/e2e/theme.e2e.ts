import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type Browser, type BrowserContext, type Page } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectDir = path.join(__dirname, "..");
const distDir = path.join(projectDir, "dist");
const referenceCss = fs.readFileSync(path.join(projectDir, "..", "notes", "dev", "reference", "GitHubDHC-theme.css"), "utf-8");

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

type Scheme = "light" | "dark";

// GitHubDHC leaves --caret-color undefined, so it has no colour to compare against.
const NOT_A_GITHUBDHC_COLOUR = ["--caret-color"];

async function themeClasses(page: Page): Promise<string[]> {
  return page.evaluate(() => [...document.body.classList].filter((c) => c === "theme-dark" || c === "theme-light"));
}

async function probeColours(page: Page, names: string[]): Promise<Record<string, string>> {
  return page.evaluate((varNames) => {
    const probe = document.createElement("div");
    document.body.appendChild(probe);
    const result: Record<string, string> = {};
    for (const name of varNames) {
      probe.style.setProperty("background-color", "");
      probe.style.setProperty("background-color", `var(${name})`);
      result[name] = getComputedStyle(probe).backgroundColor;
    }
    probe.remove();
    return result;
  }, names);
}

async function defaultLayerNames(page: Page, scheme: Scheme): Promise<string[]> {
  return page.evaluate((selector) => {
    const names = new Set<string>();
    for (const sheet of Array.from(document.styleSheets)) {
      for (const rule of Array.from(sheet.cssRules)) {
        if (rule instanceof CSSStyleRule && rule.selectorText === selector) {
          for (const property of Array.from(rule.style)) if (property.startsWith("--")) names.add(property);
        }
      }
    }
    return [...names];
  }, `body.theme-${scheme}`);
}

async function referenceColours(browser: Browser, scheme: Scheme, names: string[]): Promise<{ colours: Record<string, string>; unset: string[] }> {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    await page.setContent(`<html><head><style>${referenceCss}</style></head><body class="theme-${scheme}"></body></html>`);
    const colours = await probeColours(page, names);
    const unset = await page.evaluate((varNames) => varNames.filter((n) => getComputedStyle(document.body).getPropertyValue(n).trim() === ""), names);
    return { colours, unset };
  } finally {
    await context.close();
  }
}

async function installFirstPaintProbe(context: BrowserContext): Promise<void> {
  await context.addInitScript(() => {
    const probe: { classSetAt: number | null; firstPaintAt: number | null } = { classSetAt: null, firstPaintAt: null };
    (window as unknown as { __themeProbe: typeof probe }).__themeProbe = probe;
    new MutationObserver(() => {
      const body = document.body;
      if (probe.classSetAt === null && body && (body.classList.contains("theme-dark") || body.classList.contains("theme-light"))) {
        probe.classSetAt = performance.now();
      }
    }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) if (entry.name === "first-paint") probe.firstPaintAt = entry.startTime;
    }).observe({ type: "paint", buffered: true });
  });
}

async function runScenario(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-theme:${scheme}]`;
  const other: Scheme = scheme === "dark" ? "light" : "dark";
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 700 } });
  await installFirstPaintProbe(context);
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  const initial = await themeClasses(page);
  assert(initial.length === 1 && initial[0] === `theme-${scheme}`, `with the OS in ${scheme}, body must carry exactly theme-${scheme}, got [${initial.join(", ")}]`);
  console.log(`${tag} PASS: body carries exactly theme-${scheme}`);

  const probe = await page.evaluate(() => (window as unknown as { __themeProbe: { classSetAt: number | null; firstPaintAt: number | null } }).__themeProbe);
  assert(probe.classSetAt !== null, "the body class was never observed being set");
  assert(probe.firstPaintAt !== null, "no first-paint entry was recorded");
  assert(probe.classSetAt <= probe.firstPaintAt, `the body class must be set before first paint (class at ${probe.classSetAt}ms, first paint at ${probe.firstPaintAt}ms)`);
  console.log(`${tag} PASS: the class was set before first paint (${probe.classSetAt.toFixed(1)}ms vs ${probe.firstPaintAt.toFixed(1)}ms)`);

  await page.emulateMedia({ colorScheme: other });
  await page.waitForFunction((cls) => document.body.classList.contains(cls), `theme-${other}`);
  const swapped = await themeClasses(page);
  assert(swapped.length === 1 && swapped[0] === `theme-${other}`, `after the OS moves to ${other}, body must carry exactly theme-${other}, got [${swapped.join(", ")}]`);
  const swappedBg = (await probeColours(page, ["--background-primary"]))["--background-primary"];
  const visibleBg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  assert(visibleBg === swappedBg, `the page background must follow the swap (body ${visibleBg}, --background-primary ${swappedBg})`);
  await page.emulateMedia({ colorScheme: scheme });
  await page.waitForFunction((cls) => document.body.classList.contains(cls), `theme-${scheme}`);
  const restored = await themeClasses(page);
  assert(restored.length === 1 && restored[0] === `theme-${scheme}`, `after the OS returns to ${scheme}, body must carry exactly theme-${scheme}, got [${restored.join(", ")}]`);
  console.log(`${tag} PASS: the class follows live OS changes to ${other} and back`);

  const names = await defaultLayerNames(page, scheme);
  assert(names.length >= 20, `expected the app's default layer to declare 20+ variables on body.theme-${scheme}, found ${names.length}`);
  const app = await probeColours(page, names);
  const reference = await referenceColours(browser, scheme, names);
  const mismatches = names.filter((n) => !NOT_A_GITHUBDHC_COLOUR.includes(n) && app[n] !== reference.colours[n]).map((n) => `${n}: app ${app[n]} vs GitHubDHC ${reference.colours[n]}`);
  assert(mismatches.length === 0, `defaults must equal GitHubDHC's computed values:\n  ${mismatches.join("\n  ")}`);
  const unexpectedlyUnset = reference.unset.filter((n) => !NOT_A_GITHUBDHC_COLOUR.includes(n));
  assert(unexpectedlyUnset.length === 0, `GitHubDHC leaves these unset, so the comparison above proved nothing for them: ${unexpectedlyUnset.join(", ")}`);
  const expectedKey: Record<Scheme, Record<string, string>> = {
    dark: { "--background-primary": "rgb(1, 4, 9)", "--text-normal": "rgb(255, 255, 255)", "--text-accent": "rgb(113, 183, 255)", "--interactive-accent": "rgb(158, 167, 179)" },
    light: { "--background-primary": "rgb(255, 255, 255)", "--text-normal": "rgb(31, 35, 40)", "--text-accent": "rgb(9, 105, 218)", "--interactive-accent": "rgb(10, 114, 233)" },
  };
  for (const [name, value] of Object.entries(expectedKey[scheme])) {
    assert(app[name] === value, `${name} in ${scheme} should be ${value}, got ${app[name]}`);
  }
  const caret = (await probeColours(page, ["--caret-color", "--text-accent"]));
  assert(caret["--caret-color"] === caret["--text-accent"], `--caret-color should default to --text-accent, got ${caret["--caret-color"]} vs ${caret["--text-accent"]}`);
  console.log(`${tag} PASS: all ${names.length} default variables match GitHubDHC's computed values (${NOT_A_GITHUBDHC_COLOUR.join(", ")} is the app's own choice)`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function runNoFlashScenario(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-theme:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 700 } });
  await context.route("**/assets/*.js", (route) => {
    setTimeout(() => void route.continue(), 1500);
  });
  const page = await context.newPage();
  await page.goto(url, { waitUntil: "commit" });
  await page.waitForTimeout(700);
  const state = await page.evaluate(() => ({
    appBooted: document.querySelector(".cm-content") !== null,
    classes: [...document.body.classList].filter((c) => c === "theme-dark" || c === "theme-light"),
    background: getComputedStyle(document.body).backgroundColor,
  }));
  assert(!state.appBooted, "the app bundle should still be held back for this check");
  assert(state.classes.length === 1 && state.classes[0] === `theme-${scheme}`, `before the app bundle runs, body must already carry theme-${scheme}, got [${state.classes.join(", ")}]`);
  const expected = scheme === "dark" ? "rgb(1, 4, 9)" : "rgb(255, 255, 255)";
  assert(state.background === expected, `before the app bundle runs the page must already be ${expected}, got ${state.background}`);
  console.log(`${tag} PASS: with the app bundle held back, the page is already ${expected} with theme-${scheme}`);
  await context.close();
}

async function runNoPreferenceScenario(browser: Browser, url: string): Promise<void> {
  const context = await browser.newContext({ colorScheme: "no-preference", viewport: { width: 420, height: 700 } });
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  const classes = await themeClasses(page);
  assert(classes.length === 1 && classes[0] === "theme-light", `with no OS preference body must carry exactly theme-light, got [${classes.join(", ")}]`);
  console.log("[e2e-theme] PASS: with no OS preference body carries exactly theme-light");
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-theme] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) {
      await runScenario(browser, url, scheme);
      await runNoFlashScenario(browser, url, scheme);
    }
    await runNoPreferenceScenario(browser, url);
    console.log("[e2e-theme] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-theme] FAILED:", err);
    process.exit(1);
  });
