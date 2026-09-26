import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, devices, type CDPSession, type Locator, type Page } from "playwright";

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

async function typeIntoEditor(page: Page, text: string): Promise<void> {
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(text);
}

/**
 * Views slide in over a 200ms CSS transition (src/navigation.ts). A raw
 * `boundingBox()` read taken mid-slide gives coordinates the row won't be
 * at by the time the touch/mouse gesture actually reaches it - unlike
 * Playwright's own `.click()`, raw pointer/touch dispatch doesn't wait for
 * the target to stop moving. Polls until two reads agree before trusting it.
 */
async function waitForStableBox(row: Locator): Promise<{ x: number; y: number; width: number; height: number }> {
  let previous = await row.boundingBox();
  for (let i = 0; i < 20; i++) {
    await new Promise((r) => setTimeout(r, 30));
    const current = await row.boundingBox();
    if (previous && current && previous.x === current.x && previous.y === current.y && current.width > 0) {
      return current;
    }
    previous = current;
  }
  throw new Error("waitForStableBox: row position never stabilized (still animating?)");
}

/**
 * Drives a real, trusted touch gesture via the CDP Input domain - the same
 * mechanism Chromium's own touch emulation and Playwright's own
 * `touchscreen.tap()` use under the hood. This produces genuine
 * `pointerType: 'touch'` PointerEvents on the page, not a synthetic
 * `dispatchEvent` call - the distinction the task calls out explicitly.
 */
async function touchDragLeft(
  client: CDPSession,
  box: { x: number; y: number; width: number; height: number },
  distanceRatio: number,
  steps: number,
  stepDelayMs: number,
): Promise<void> {
  const y = box.y + box.height / 2;
  const startX = box.x + box.width - 10;
  const distance = box.width * distanceRatio;

  await client.send("Input.dispatchTouchEvent", {
    type: "touchStart",
    touchPoints: [{ x: startX, y }],
  });
  for (let i = 1; i <= steps; i++) {
    await new Promise((r) => setTimeout(r, stepDelayMs));
    const x = startX - (distance * i) / steps;
    await client.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x, y }],
    });
  }
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
}

async function touchTap(client: CDPSession, box: { x: number; y: number; width: number; height: number }): Promise<void> {
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y }] });
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
}

async function mouseSwipeLeft(page: Page, row: Locator, distanceRatio: number): Promise<void> {
  const box = await waitForStableBox(row);
  const y = box.y + box.height / 2;
  const startX = box.x + box.width - 10;
  const distance = box.width * distanceRatio;
  await page.mouse.move(startX, y);
  await page.mouse.down();
  const steps = 12;
  for (let i = 1; i <= steps; i++) {
    await page.mouse.move(startX - (distance * i) / steps, y, { steps: 1 });
  }
  await page.mouse.up();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-swipe] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    // ---------------------------------------------------------------
    // Part 1: real touch input on a touch-capable device (Pixel 7).
    // ---------------------------------------------------------------
    const pixel7 = devices["Pixel 7"];
    assert(pixel7 !== undefined, "Playwright's device descriptors must include 'Pixel 7'");
    assert(pixel7.hasTouch === true, "Pixel 7 device descriptor must set hasTouch: true");

    const touchContext = await browser.newContext({ ...pixel7 });
    const page = await touchContext.newPage();
    const client = await touchContext.newCDPSession(page);
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    const list = page.locator("#view-list");
    const settings = page.locator("#view-settings");
    const trash = page.locator("#view-trash");

    const markerC = `SwipeE2E QuKi C ${Date.now()}`;
    await typeIntoEditor(page, markerC);
    await page.waitForTimeout(2500);
    console.log("[e2e-swipe] QuKi C typed and auto-saved");

    await page.click("#btn-new-quki");
    await page.waitForTimeout(100);
    const markerD = `SwipeE2E QuKi D ${Date.now()}`;
    await typeIntoEditor(page, markerD);
    await page.waitForTimeout(2500);
    console.log("[e2e-swipe] QuKi D typed and auto-saved");

    await page.click("#btn-quki-list");
    await list.locator(".list-row").first().waitFor({ timeout: 5000 });
    let rows = await list.locator(".list-row").count();
    assert(rows === 2, `expected 2 rows in the list, got ${rows}`);

    // --- Short touch drag (under both the distance and velocity
    // thresholds) snaps back and does NOT delete. ---
    const rowD = list.locator(".list-row", { hasText: "SwipeE2E QuKi D" });
    const rowDBoxBefore = await waitForStableBox(rowD);
    await touchDragLeft(client, rowDBoxBefore, 0.15, 15, 40);
    await page.waitForTimeout(300); // let the snap-back transition finish
    rows = await list.locator(".list-row").count();
    assert(rows === 2, `a short touch drag must NOT delete the row - expected 2 rows still, got ${rows}`);
    const rowDContent = rowD.locator(".list-row-content");
    const transformAfterSnapBack = await rowDContent.evaluate((el) => getComputedStyle(el).transform);
    assert(
      transformAfterSnapBack === "none" || transformAfterSnapBack === "matrix(1, 0, 0, 1, 0, 0)",
      `row should have snapped back to its resting transform, got: "${transformAfterSnapBack}"`,
    );
    console.log("[e2e-swipe] PASS (touch): short drag under threshold snapped back, row D still present");

    // --- Real touch tap still opens the row in the editor (must not be
    // broken by the new gesture handling). ---
    await touchTap(client, rowDBoxBefore);
    await page.waitForSelector(".cm-content");
    const bodyAfterTap = await page.evaluate(
      () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
    );
    assert(bodyAfterTap.includes("SwipeE2E QuKi D"), `expected tap to open QuKi D into the editor, got: "${bodyAfterTap}"`);
    console.log("[e2e-swipe] PASS (touch): tapping a row (not dragging) opened it in the editor");

    // --- Real touch swipe past the commit threshold deletes it
    // immediately, no confirmation (BEHAVIOR_SPEC.md §5). ---
    await page.click("#btn-quki-list");
    await list.locator(".list-row").first().waitFor({ timeout: 5000 });
    const rowDAgain = list.locator(".list-row", { hasText: "SwipeE2E QuKi D" });
    const rowDBox2 = await waitForStableBox(rowDAgain);
    await touchDragLeft(client, rowDBox2, 0.7, 12, 15);
    const toastText = await page.waitForSelector(".toast:not([hidden])").then((el) => el.textContent());
    assert(toastText === "QuKi moved to Trash.", `expected the immediate no-confirmation toast, got: "${toastText}"`);
    await page.waitForFunction(() => document.querySelectorAll("#view-list .list-row").length === 1, { timeout: 5000 });
    rows = await list.locator(".list-row").count();
    assert(rows === 1, `expected QuKi D gone after the delete swipe, got ${rows} rows left`);
    console.log("[e2e-swipe] PASS (touch): swipe past threshold deleted the list row immediately, no confirmation, correct toast");

    // --- Same gesture in Trash requires confirmation before it actually
    // deletes (BEHAVIOR_SPEC.md §6). ---
    await list.locator(".settings-btn").click();
    await settings.locator(".trash-btn").waitFor();
    await settings.locator(".trash-btn").click();
    await trash.locator(".list-row").first().waitFor({ timeout: 5000 });
    let trashRows = await trash.locator(".list-row").count();
    assert(trashRows === 1, `expected 1 row in Trash, got ${trashRows}`);

    const trashRowD = trash.locator(".list-row", { hasText: "SwipeE2E QuKi D" });
    const trashRowDBox = await waitForStableBox(trashRowD);
    await touchDragLeft(client, trashRowDBox, 0.7, 12, 15);
    await page.waitForSelector(".confirm-dialog");
    const confirmTitle = await page.textContent(".confirm-title");
    assert(confirmTitle === "Delete forever?", `expected the permanent-delete confirmation after the swipe, got: "${confirmTitle}"`);
    // Trash rows must still be present - the swipe alone must not have deleted anything yet.
    trashRows = await trash.locator(".list-row").count();
    assert(trashRows === 1, `swiping in Trash must not delete before confirmation - expected 1 row, got ${trashRows}`);
    console.log("[e2e-swipe] PASS (touch): Trash swipe opened the confirmation dialog without deleting yet");

    await page.click(".confirm-confirm");
    await page.waitForSelector("#view-trash .empty-state", { timeout: 5000 });
    trashRows = await trash.locator(".list-row").count();
    assert(trashRows === 0, `expected Trash empty after confirming the permanent delete, got ${trashRows} rows`);
    console.log("[e2e-swipe] PASS (touch): confirming after the swipe permanently deleted the QuKi");

    await touchContext.close();

    // ---------------------------------------------------------------
    // Part 2: mouse drag on a normal (non-touch) desktop context -
    // Pointer Events should cover this too; verify rather than assume.
    // ---------------------------------------------------------------
    const desktopContext = await browser.newContext();
    const desktopPage = await desktopContext.newPage();
    await desktopPage.goto(url);
    await desktopPage.waitForSelector(".cm-content");

    const desktopList = desktopPage.locator("#view-list");

    const markerE = `SwipeE2E QuKi E ${Date.now()}`;
    await typeIntoEditor(desktopPage, markerE);
    await desktopPage.waitForTimeout(2500);

    await desktopPage.click("#btn-quki-list");
    await desktopList.locator(".list-row").first().waitFor({ timeout: 5000 });
    let desktopRows = await desktopList.locator(".list-row").count();
    assert(desktopRows === 1, `expected 1 row in the desktop-context list, got ${desktopRows}`);

    const rowE = desktopList.locator(".list-row", { hasText: "SwipeE2E QuKi E" });
    await mouseSwipeLeft(desktopPage, rowE, 0.7);
    const desktopToastText = await desktopPage.waitForSelector(".toast:not([hidden])").then((el) => el.textContent());
    assert(desktopToastText === "QuKi moved to Trash.", `expected the delete toast from a mouse drag, got: "${desktopToastText}"`);
    await desktopPage.waitForFunction(() => document.querySelectorAll("#view-list .list-row").length === 0, { timeout: 5000 });
    console.log("[e2e-swipe] PASS (mouse): mouse drag past threshold on a desktop context deleted the row via the same code path");

    // --- Plain mouse click on a row still opens it (tap-to-open unbroken
    // by the swipe handling) - verified with a fresh QuKi. Still on the
    // list view at this point, so New QuKi comes from the list's own
    // ".new-btn", not the editor app bar's (hidden) "#btn-new-quki". ---
    await desktopList.locator(".new-btn").click();
    await desktopPage.waitForSelector(".cm-content");
    await desktopPage.waitForTimeout(100);
    const markerF = `SwipeE2E QuKi F ${Date.now()}`;
    await typeIntoEditor(desktopPage, markerF);
    await desktopPage.waitForTimeout(2500);
    await desktopPage.click("#btn-quki-list");
    await desktopList.locator(".list-row").first().waitFor({ timeout: 5000 });
    await desktopList.locator(".list-row-preview", { hasText: "SwipeE2E QuKi F" }).click();
    await desktopPage.waitForSelector(".cm-content");
    const bodyAfterClick = await desktopPage.evaluate(
      () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
    );
    assert(bodyAfterClick.includes("SwipeE2E QuKi F"), `expected a plain click to open QuKi F, got: "${bodyAfterClick}"`);
    console.log("[e2e-swipe] PASS (mouse): plain click (no drag) still opens a row in the editor");

    await desktopContext.close();

    console.log("[e2e-swipe] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-swipe] FAILED:", err);
    process.exit(1);
  });
