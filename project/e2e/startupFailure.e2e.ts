import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.join(__dirname, "..", "dist");

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
        const ext = path.extname(filePath);
        res.writeHead(200, { "content-type": CONTENT_TYPES[ext] ?? "application/octet-stream" });
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

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-startup-failure] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    // --- Scenario: init() rejects before the editor ever mounts. Forced via
    // the app's own existing fail-fast guard (main.ts's
    // `if (!host) throw new Error("missing #editor-host")`) rather than a
    // fabricated failure - reached by making the one querySelector call for
    // that id come back null, standing in for the brief's real-world causes
    // (OPFS unavailable in a private window, an Electron IPC failure, a
    // corrupted preferences file) that this e2e harness (plain Chromium,
    // no native wrapper) has no way to reproduce directly. What's under
    // test is the `void init().catch(...)` wrapper, not which particular
    // thing failed inside init().
    const context = await browser.newContext();
    const page = await context.newPage();

    await page.addInitScript(() => {
      (window as unknown as { __unhandledRejections: string[] }).__unhandledRejections = [];
      window.addEventListener("unhandledrejection", (e) => {
        (window as unknown as { __unhandledRejections: string[] }).__unhandledRejections.push(String(e.reason));
      });

      const originalQuerySelector = Document.prototype.querySelector;
      Document.prototype.querySelector = function (this: Document, selector: string) {
        if (selector === "#editor-host") return null;
        return originalQuerySelector.call(this, selector);
      } as typeof Document.prototype.querySelector;
    });

    await page.goto(url);

    // No .cm-content ever appears - init() threw before the editor mounted.
    // Waiting on the banner directly is the actual assertion, but this
    // guards against the assertion below passing for the wrong reason (e.g.
    // a leftover banner from a previous run).
    await page.waitForFunction(() => document.querySelector("#save-status")?.hasAttribute("hidden") === false, { timeout: 5000 });

    const bannerHiddenAttr = await page.getAttribute("#save-status", "hidden");
    assert(bannerHiddenAttr === null, "a rejected init() must leave a visible (not hidden) startup-error banner");
    const bannerText = await page.textContent("#save-status");
    assert(!!bannerText && bannerText.length > 0, "the startup-error banner must carry a visible message");
    assert(/could not start/i.test(bannerText), `the banner should honestly describe a startup failure, got: "${bannerText}"`);
    console.log(`[e2e-startup-failure] PASS: a rejected init() surfaced a visible banner instead of a blank window: "${bannerText}"`);

    const cmContentCount = await page.locator(".cm-content").count();
    assert(cmContentCount === 0, "the editor must never have mounted once init() threw before reaching it");

    const rejections = await page.evaluate(() => (window as unknown as { __unhandledRejections: string[] }).__unhandledRejections);
    assert(rejections.length === 0, `the startup failure must not also leak as an unhandled promise rejection, but got: ${JSON.stringify(rejections)}`);
    console.log("[e2e-startup-failure] PASS: the startup failure did not leak as an unhandled promise rejection");

    await context.close();

    // --- Control: an ordinary launch (no fault injected) still shows the
    // real app and never shows the startup-error banner - proves the
    // scenario above is actually exercising the failure path, not something
    // that fires unconditionally on every launch. ---
    const controlContext = await browser.newContext();
    const controlPage = await controlContext.newPage();
    await controlPage.goto(url);
    await controlPage.waitForSelector(".cm-content");
    const controlBannerHidden = await controlPage.getAttribute("#save-status", "hidden");
    assert(controlBannerHidden !== null, "a clean launch must not show the startup-error banner");
    await controlContext.close();
    console.log("[e2e-startup-failure] PASS: a clean launch shows the real app and no startup-error banner");

    console.log("[e2e-startup-failure] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((err: unknown) => {
  console.error("[e2e-startup-failure] FAILED:", err);
  process.exit(1);
});
