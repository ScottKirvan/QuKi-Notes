import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type Locator, type Page } from "playwright";

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
 * at by the time the mouse actually arrives there - unlike Playwright's
 * own `.click()`, `page.mouse` doesn't wait for the target to stop moving.
 * Polls until two reads agree before trusting the box.
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
 * Drives the real swipe-to-delete gesture (src/screens/swipeToDelete.ts)
 * with mouse-pointer input: press inside the row, drag left past the
 * commit threshold, release. Playwright's page.mouse dispatches genuine
 * browser input, which the browser turns into real PointerEvents - not a
 * synthetic dispatchEvent - so this exercises the same code path a real
 * mouse drag would.
 */
async function swipeRowLeft(page: Page, row: Locator): Promise<void> {
  const box = await waitForStableBox(row);
  const y = box.y + box.height / 2;
  const startX = box.x + box.width - 10;
  const distance = box.width * 0.7; // well past the 0.4 commit-distance-ratio threshold
  await page.mouse.move(startX, y);
  await page.mouse.down();
  const steps = 12;
  for (let i = 1; i <= steps; i++) {
    await page.mouse.move(startX - (distance * i) / steps, y, { steps: 1 });
  }
  await page.mouse.up();
}

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(
    () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
  );
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-chunk2] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    const list = page.locator("#view-list");
    const settings = page.locator("#view-settings");
    const trash = page.locator("#view-trash");

    // --- Create QuKi A and QuKi B ---
    const markerA = `Chunk2 QuKi A ${Date.now()}`;
    await typeIntoEditor(page, markerA);
    await page.waitForTimeout(2500); // 2s debounce + margin
    console.log("[e2e-chunk2] QuKi A typed and auto-saved");

    await page.click("#btn-new-quki");
    await page.waitForTimeout(100);
    assert((await editorBody(page)) === "", "New QuKi should start blank");
    assert((await page.getAttribute("#btn-delete", "disabled")) !== null, "Delete should be disabled again on a fresh, unsaved New QuKi");
    console.log("[e2e-chunk2] PASS: New QuKi reset the editor to blank and disabled Delete");

    const markerB = `Chunk2 QuKi B ${Date.now()}`;
    await typeIntoEditor(page, markerB);
    await page.waitForTimeout(2500);
    console.log("[e2e-chunk2] QuKi B typed and auto-saved");

    // --- QuKis button enabled, open the list ---
    assert((await page.getAttribute("#btn-quki-list", "disabled")) === null, "QuKis button should be enabled once QuKis exist");

    await page.click("#btn-quki-list");
    await list.locator(".list-row").first().waitFor({ timeout: 5000 });
    let rows = await list.locator(".list-row").count();
    assert(rows === 2, `expected 2 rows in the list, got ${rows}`);
    console.log(`[e2e-chunk2] PASS: list shows ${rows} rows after creating two QuKis`);

    await page.waitForFunction(() => {
      const previews = Array.from(document.querySelectorAll("#view-list .list-row-preview"));
      return previews.every((p) => p.textContent !== "…" && (p.textContent?.length ?? 0) > 0);
    });
    const previewTexts = await list.locator(".list-row-preview").allTextContents();
    assert(previewTexts.some((t) => t.includes("Chunk2 QuKi B")), `expected a preview with QuKi B's text, got: ${JSON.stringify(previewTexts)}`);
    assert(previewTexts.some((t) => t.includes("Chunk2 QuKi A")), `expected a preview with QuKi A's text, got: ${JSON.stringify(previewTexts)}`);
    console.log(`[e2e-chunk2] PASS: row previews rendered: ${JSON.stringify(previewTexts)}`);

    // --- Search filters on every keystroke ---
    await list.locator(".search-input").fill("QuKi A");
    await page.waitForFunction(() => document.querySelectorAll("#view-list .list-row").length === 1);
    rows = await list.locator(".list-row").count();
    assert(rows === 1, `search for "QuKi A" should leave exactly 1 row, got ${rows}`);
    console.log("[e2e-chunk2] PASS: search filtered to 1 matching row");

    await list.locator(".search-input").fill("definitely-no-such-content-xyz");
    await list.locator(".empty-state").waitFor();
    const noResultsText = await list.locator(".empty-state").textContent();
    assert(!!noResultsText && noResultsText.includes("No results for"), `expected a no-results message, got: "${noResultsText}"`);
    console.log(`[e2e-chunk2] PASS: no-results empty state shown: "${noResultsText}"`);

    await list.locator(".search-input").fill("");
    await page.waitForFunction(() => document.querySelectorAll("#view-list .list-row").length === 2);

    // --- Open QuKi A from the list ---
    await list.locator(".list-row-preview", { hasText: "Chunk2 QuKi A" }).click();
    await page.waitForSelector(".cm-content");
    const bodyAfterOpen = await editorBody(page);
    assert(bodyAfterOpen.includes("Chunk2 QuKi A"), `expected QuKi A's content after opening, got: "${bodyAfterOpen}"`);
    console.log("[e2e-chunk2] PASS: opening a list row loaded that QuKi into the editor");

    // --- Delete the now-open QuKi A from the editor's own Delete button ---
    assert((await page.getAttribute("#btn-delete", "disabled")) === null, "Delete should be enabled for a QuKi that has been saved");

    await page.click("#btn-delete");
    const toastText = await page.waitForSelector(".toast:not([hidden])").then((el) => el.textContent());
    assert(toastText === "QuKi moved to Trash.", `expected exact toast copy, got: "${toastText}"`);
    console.log(`[e2e-chunk2] PASS: delete showed toast "${toastText}"`);

    const bodyAfterDelete = await editorBody(page);
    assert(bodyAfterDelete === "", `editor should be blank immediately after deleting the open QuKi, got: "${bodyAfterDelete}"`);

    // --- Confirm it disappeared from the list ---
    await page.click("#btn-quki-list");
    await page.waitForFunction(() => document.querySelectorAll("#view-list .list-row").length === 1, { timeout: 5000 });
    rows = await list.locator(".list-row").count();
    assert(rows === 1, `expected 1 row left in the list after deleting QuKi A, got ${rows}`);
    console.log("[e2e-chunk2] PASS: deleted QuKi disappeared from the list");

    // --- Settings -> Trash: confirm the deleted QuKi is there ---
    await list.locator(".settings-btn").click();
    await settings.locator(".trash-btn").waitFor();
    await settings.locator(".trash-btn").click();
    await trash.locator(".list-row").first().waitFor({ timeout: 5000 });
    let trashRows = await trash.locator(".list-row").count();
    assert(trashRows === 1, `expected 1 row in Trash, got ${trashRows}`);
    console.log("[e2e-chunk2] PASS: deleted QuKi appears in Trash");

    // --- Restore it ---
    await trash.locator(".list-row").first().click();
    await page.waitForSelector(".confirm-dialog");
    const confirmTitle = await page.textContent(".confirm-title");
    assert(confirmTitle === "Restore note?", `expected exact restore confirmation copy, got: "${confirmTitle}"`);
    await page.click(".confirm-confirm");

    // Restoring closes Trash back to Settings per spec.
    await settings.locator(".trash-btn").waitFor();
    console.log("[e2e-chunk2] PASS: restore returned to Settings");

    // Settings here was opened from the List (a "plain push" per
    // BEHAVIOR_SPEC.md §2), so popping it returns to the List, not the
    // editor - confirm the restored QuKi is back without re-opening the list.
    await settings.locator(".back-btn").click();
    await page.waitForFunction(() => document.querySelectorAll("#view-list .list-row").length === 2, { timeout: 5000 });
    rows = await list.locator(".list-row").count();
    assert(rows === 2, `expected the restored QuKi back in the list (2 rows), got ${rows}`);
    console.log("[e2e-chunk2] PASS: restored QuKi is back in the list (Settings popped back to the List that opened it)");

    // --- Delete QuKi B via the list row's swipe-to-delete gesture
    // (BEHAVIOR_SPEC.md §5: "Swiping right-to-left deletes it... no
    // confirmation"), exercised separately from the editor's own Delete
    // button already covered above for QuKi A ---
    //
    // The shared toast element may still be inside QuKi A's own 1.5s
    // window from the editor-delete step above (this script runs far
    // faster than a human would) - wait for it to clear first, the same
    // guard the clipboard-toast check below already relies on, so the
    // upcoming toast check can't accidentally match a stale one and race
    // ahead of the swipe's own (animated, and therefore slightly slower)
    // commit.
    await page.waitForSelector(".toast[hidden]", { timeout: 3000 }).catch(() => {});

    const rowB = list.locator(".list-row", { hasText: "Chunk2 QuKi B" });
    await swipeRowLeft(page, rowB);
    const toastText2 = await page.waitForSelector(".toast:not([hidden])").then((el) => el.textContent());
    assert(toastText2 === "QuKi moved to Trash.", `expected exact toast copy on row swipe delete, got: "${toastText2}"`);
    console.log("[e2e-chunk2] PASS: list row swipe-to-delete moved QuKi B to Trash with the expected toast, no confirmation");

    // Only QuKi B is in Trash at this point - A was already restored above.
    await list.locator(".settings-btn").click();
    await settings.locator(".trash-btn").click();
    await page.waitForFunction(() => document.querySelectorAll("#view-trash .list-row").length === 1, { timeout: 5000 });

    // BEHAVIOR_SPEC.md §6: "Swipe → confirmation, then permanent deletion"
    // - unlike the list, Trash's swipe leads to a confirmation dialog
    // rather than deleting immediately.
    const trashRowB = trash.locator(".list-row", { hasText: "Chunk2 QuKi B" });
    await swipeRowLeft(page, trashRowB);
    await page.waitForSelector(".confirm-dialog");
    const permTitle = await page.textContent(".confirm-title");
    assert(permTitle === "Delete forever?", `expected the permanent-delete confirmation after swiping, got: "${permTitle}"`);
    await page.click(".confirm-confirm");

    await page.waitForSelector("#view-trash .empty-state", { timeout: 5000 });
    trashRows = await trash.locator(".list-row").count();
    assert(trashRows === 0, `expected Trash to be empty after permanent delete, got ${trashRows} rows`);
    const trashEmptyText = await trash.locator(".empty-state").textContent();
    assert(trashEmptyText === "No notes in Trash.", `expected exact Trash empty-state copy, got: "${trashEmptyText}"`);
    console.log("[e2e-chunk2] PASS: permanently deleted QuKi B is gone from Trash, empty-state copy correct");

    // --- Settings: version tap copies to clipboard ---
    // The single shared toast element is reused across the whole session -
    // an earlier "QuKi moved to Trash." toast may still be within its own
    // 1.5s window from the fast row-delete steps above, so wait for it to
    // clear before triggering (and looking for) a new one.
    await page.waitForSelector(".toast[hidden]", { timeout: 3000 }).catch(() => {});
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    await trash.locator(".back-btn").click(); // Trash -> Settings
    await settings.locator(".version-btn").waitFor();
    const versionLabel = await settings.locator(".version-btn").textContent();
    await settings.locator(".version-btn").click();
    await page.waitForFunction(() => document.querySelector(".toast")?.textContent === "Copied to clipboard.");
    const clipboardToast = await page.textContent(".toast");
    assert(clipboardToast === "Copied to clipboard.", `expected exact clipboard toast copy, got: "${clipboardToast}"`);
    const clipboardContent = await page.evaluate(() => navigator.clipboard.readText());
    assert(
      !!versionLabel && versionLabel.includes(clipboardContent),
      `clipboard content "${clipboardContent}" should match the displayed version "${versionLabel}"`,
    );
    console.log(`[e2e-chunk2] PASS: tapping the version copied "${clipboardContent}" to the clipboard`);

    // --- Empty states: verify copy on a fresh, empty context ---
    const emptyContext = await browser.newContext();
    const emptyPage = await emptyContext.newPage();
    await emptyPage.goto(url);
    await emptyPage.waitForSelector(".cm-content");
    assert((await emptyPage.getAttribute("#btn-quki-list", "disabled")) !== null, "QuKis button should be disabled with no QuKis yet");
    console.log("[e2e-chunk2] PASS: QuKis button disabled with no QuKis");
    await emptyContext.close();

    console.log("[e2e-chunk2] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-chunk2] FAILED:", err);
    process.exit(1);
  });
