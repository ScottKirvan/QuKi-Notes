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
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".webmanifest": "application/manifest+json",
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
  console.log(`[e2e-pwa] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    // --- Manifest sanity: the fields Chrome's installability check actually
    // reads (name, an icon >=192px, an icon >=512px, start_url, a
    // standalone-family display mode). ---
    const manifestPage = await browser.newPage();
    await manifestPage.goto(url);
    const manifest = await manifestPage.evaluate(async () => {
      const link = document.querySelector<HTMLLinkElement>('link[rel="manifest"]');
      if (!link) return null;
      const res = await fetch(link.href);
      return res.json();
    });
    assert(manifest !== null, "index.html should link a web app manifest");
    assert(manifest.name === "QuKi Notes", `manifest name should be "QuKi Notes", got: ${JSON.stringify(manifest.name)}`);
    assert(manifest.display === "standalone", `manifest display should be "standalone", got: ${JSON.stringify(manifest.display)}`);
    assert(typeof manifest.start_url === "string" && manifest.start_url.length > 0, "manifest should have a start_url");
    const icons: Array<{ sizes: string }> = manifest.icons ?? [];
    assert(icons.some((i) => i.sizes === "192x192"), "manifest should list a 192x192 icon");
    assert(icons.some((i) => i.sizes === "512x512"), "manifest should list a 512x512 icon");
    console.log("[e2e-pwa] PASS: manifest has name/display/start_url and 192px + 512px icons");
    await manifestPage.close();

    // --- Scenario: load once online (installs the service worker and lets
    // it precache the app shell), confirm it actually activates and takes
    // control, then go fully offline and reload - the real proof this
    // requirement asks for, not just that a manifest exists. ---
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    const swState = await page.evaluate(async () => {
      const registration = await navigator.serviceWorker.ready;
      const worker = registration.active;
      if (worker && worker.state !== "activated") {
        await new Promise<void>((resolve) => {
          worker.addEventListener("statechange", () => {
            if (worker.state === "activated") resolve();
          });
          // In case it already flipped between the check above and the listener attach.
          if (worker.state === "activated") resolve();
        });
      }
      return {
        active: registration.active?.state ?? null,
        scriptURL: registration.active?.scriptURL ?? null,
      };
    });
    assert(swState.active === "activated", `service worker should be activated before going offline, got state: ${swState.active}`);
    assert(!!swState.scriptURL && swState.scriptURL.endsWith("/sw.js"), `service worker should be sw.js, got: ${swState.scriptURL}`);
    console.log("[e2e-pwa] PASS: service worker registered and activated");

    const marker = `E2E offline proof ${Date.now()}`;
    await page.click(".cm-content");
    await page.keyboard.press("Control+A");
    await page.keyboard.type(marker);
    // 2s auto-save debounce + margin, so the marker is on disk (OPFS) before
    // the reload below - offline reload must recover it from local storage,
    // not from a network response.
    await page.waitForTimeout(2500);

    // --- Go offline: block all real network traffic at the browser level.
    // Any response the service worker serves from its Cache Storage never
    // reaches this layer, so a successful reload here is proof the precache
    // - not the network - answered every request. ---
    await context.setOffline(true);
    await page.reload();

    await page.waitForSelector(".cm-content", { timeout: 10_000 });
    console.log("[e2e-pwa] PASS: app shell loaded from cache with the network fully offline");

    const offlineHiddenAttr = await page.getAttribute("#save-status", "hidden");
    assert(offlineHiddenAttr !== null, `no error banner should appear on a clean offline reload, but #save-status is visible: "${await page.textContent("#save-status")}"`);

    // BEHAVIOR_SPEC.md §4: "a blank canvas on launch" - the reload itself
    // must not reopen the pre-offline content. What this scenario actually
    // proves is that the earlier save really landed in OPFS and survives a
    // fully offline reload; checked here via the QuKi list's per-row
    // preview (a real read off local storage, no network involved) rather
    // than via what the editor shows on open.
    const bodyRightAfterOfflineReload = await page.evaluate(
      () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
    );
    assert(
      bodyRightAfterOfflineReload === "",
      `the editor should be blank on reload per BEHAVIOR_SPEC.md §4, got: ${bodyRightAfterOfflineReload}`,
    );

    await page.click("#btn-quki-list");
    await page.locator(".list-row-preview", { hasText: marker }).waitFor({ timeout: 5000 });
    console.log("[e2e-pwa] PASS: previously-saved content survived an offline reload (OPFS, no network involved), visible in the QuKi list");

    await page.click("#view-list .back-btn");
    await page.waitForSelector("#view-editor:not([hidden])");

    // The editor must still be a live, working editor while offline - not
    // just a static cached shell. OPFS is local storage, not a network
    // resource, so typing and auto-saving must keep working with the
    // network down.
    const offlineMarker = `still editable while offline ${Date.now()}`;
    await page.click(".cm-content");
    await page.keyboard.press("Control+A");
    await page.keyboard.type(offlineMarker);
    await page.waitForTimeout(2500);

    const offlineEditHiddenAttr = await page.getAttribute("#save-status", "hidden");
    assert(
      offlineEditHiddenAttr !== null,
      `editing and auto-saving while offline should not surface an error banner, got: "${await page.textContent("#save-status")}"`,
    );

    await page.reload();
    await page.waitForSelector(".cm-content", { timeout: 10_000 });
    const bodyAfterSecondOfflineReload = await page.evaluate(
      () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
    );
    assert(
      bodyAfterSecondOfflineReload === "",
      `the editor should be blank on reload per BEHAVIOR_SPEC.md §4, got: ${bodyAfterSecondOfflineReload}`,
    );

    await page.click("#btn-quki-list");
    await page.locator(".list-row-preview", { hasText: offlineMarker }).waitFor({ timeout: 5000 });
    console.log("[e2e-pwa] PASS: the editor stayed fully functional (typed, auto-saved, retrievable from the list) with the network offline throughout");

    await page.click("#view-list .back-btn");
    await page.waitForSelector("#view-editor:not([hidden])");

    await context.setOffline(false);
    await context.close();

    // --- Confirm the app is still a perfectly normal online page: a fresh
    // context (its own empty OPFS and no installed service worker yet)
    // should load exactly like before this task touched anything. ---
    const onlineContext = await browser.newContext();
    const onlinePage = await onlineContext.newPage();
    await onlinePage.goto(url);
    await onlinePage.waitForSelector(".cm-content");
    await onlinePage.click(".cm-content");
    await onlinePage.keyboard.press("Control+A");
    await onlinePage.keyboard.type("still a normal online page");
    const onlineBody = await onlinePage.evaluate(
      () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
    );
    assert(onlineBody.includes("still a normal online page"), "the app should still work as an ordinary online page");
    console.log("[e2e-pwa] PASS: the app still functions as a normal online page");
    await onlineContext.close();
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => {
    console.log("[e2e-pwa] ALL SCENARIOS PASSED");
    process.exit(0);
  })
  .catch((err: unknown) => {
    console.error("[e2e-pwa] FAILED:", err);
    process.exit(1);
  });
