import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type Page } from "playwright";

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

// Every assertion below reads the toast right after triggering an action, so
// a still-visible toast left over from an earlier step (e.g. seeding's own
// "QuKi moved to Trash.") must never still be showing when that happens -
// otherwise waitForSelector(".toast:not([hidden])") resolves instantly
// against the stale one instead of waiting for the new message.
async function waitForToastHidden(page: Page): Promise<void> {
  await page.waitForFunction(() => document.querySelector(".toast")?.hasAttribute("hidden") !== false, { timeout: 6000 });
}

async function seedTrashedQuKi(page: Page, marker: string): Promise<void> {
  await page.click(".cm-content");
  await page.keyboard.press("Control+A");
  await page.keyboard.type(marker);
  await page.waitForTimeout(2500); // 2s auto-save debounce + margin

  await page.click("#btn-quki-list");
  const row = page.locator(".list-row").filter({ has: page.locator(".list-row-preview", { hasText: marker }) });
  await row.first().waitFor({ timeout: 5000 });
  await page.waitForTimeout(300); // let the row settle before computing its box, matching iconButtons.e2e.ts's own swipe scenario

  // BEHAVIOR_SPEC.md §5: swiping a list row deletes it (to Trash) with no
  // confirmation - the same gesture iconButtons.e2e.ts already relies on.
  const box = await row.first().boundingBox();
  assert(box !== null, `row for "${marker}" has no box`);
  const y = box.y + box.height / 2;
  const startX = box.x + box.width - 10;
  await page.mouse.move(startX, y);
  await page.mouse.down();
  for (let i = 1; i <= 12; i++) await page.mouse.move(startX - (box.width * 0.8 * i) / 12, y, { steps: 1 });
  await page.mouse.up();
  await page.waitForSelector(".toast:not([hidden])");
  await page.waitForTimeout(300);

  await page.click("#view-list .back-btn");
  await page.waitForSelector("#view-editor:not([hidden])");
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-trash-errors] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    const context = await browser.newContext();
    const page = await context.newPage();

    // Installed before any app code runs, so a rejection surfacing as an
    // unhandled promise rejection anywhere during this scenario - not just
    // from the trash actions under test - is caught.
    await page.addInitScript(() => {
      (window as unknown as { __unhandledRejections: string[] }).__unhandledRejections = [];
      window.addEventListener("unhandledrejection", (e) => {
        (window as unknown as { __unhandledRejections: string[] }).__unhandledRejections.push(String(e.reason));
      });
    });

    await page.goto(url);
    await page.waitForSelector(".cm-content");

    const markerA = `E2E trash-error A ${Date.now()}`;
    const markerB = `E2E trash-error B ${Date.now()}`;
    await seedTrashedQuKi(page, markerA);
    await seedTrashedQuKi(page, markerB);

    // Both seeded QuKis are now in Trash and none remain active, so the
    // #btn-quki-list app-bar button is disabled (main.ts's
    // refreshQuKisButton) - Settings is reached from the editor's own
    // Settings button instead, exactly as a user with an empty list would.
    await page.click("#btn-settings");
    await page.click(".trash-btn");
    const trash = page.locator("#view-trash");
    await trash.locator(".list-row").nth(1).waitFor({ timeout: 5000 });
    assert((await trash.locator(".list-row").count()) === 2, "both trashed QuKis should be listed in Trash before the failure scenarios run");
    await waitForToastHidden(page); // clears seeding's own "QuKi moved to Trash." toast before the failure scenarios below look for their own

    // Forces every backend removeEntry (restore's cleanup rename, permanent
    // delete, and empty-trash's per-item delete all go through it -
    // core/src/opfsBackend.ts) to fail from here on, reproducing a real
    // permission-denied/disk-full class of failure. Installed only now, after
    // the setup writes above (creating and trashing both QuKis) already
    // succeeded - the same "break it only for the action under test" shape
    // persistence.e2e.ts's own load-failure scenario uses.
    await page.evaluate(() => {
      Object.defineProperty(FileSystemDirectoryHandle.prototype, "removeEntry", {
        configurable: true,
        value: () => {
          throw new DOMException("simulated permission-denied removeEntry", "NotAllowedError");
        },
      });
    });

    // --- Restore, forced to fail ---
    await trash.locator(".list-row").first().locator(".list-row-content").click();
    await page.waitForSelector(".confirm-dialog");
    const restoreTitle = await page.textContent(".confirm-title");
    assert(restoreTitle === "Restore note?", `expected the restore confirmation, got "${restoreTitle}"`);
    await page.click(".confirm-confirm");

    const restoreToast = await page.waitForSelector(".toast:not([hidden])", { timeout: 5000 }).then((el) => el.textContent());
    assert(!!restoreToast && /could not restore/i.test(restoreToast), `a failed restore must surface a visible "could not restore" message, got: "${restoreToast}"`);
    assert(await trash.isVisible(), "a failed restore must leave the user on the Trash screen, not navigate away as if it had succeeded");
    console.log(`[e2e-trash-errors] PASS: a rejected restore() surfaced a visible message instead of vanishing: "${restoreToast}"`);
    // Waits for the toast's own auto-dismiss timer (screens/toast.ts) to
    // clear, so the next scenario's waitForSelector(".toast:not([hidden])")
    // can't resolve instantly against this leftover toast before its own
    // message has actually replaced it.
    await waitForToastHidden(page);

    // --- Permanent delete (swipe -> confirm), forced to fail ---
    await trash.locator(".list-row").first().waitFor();
    const delBox = await trash.locator(".list-row").first().boundingBox();
    assert(delBox !== null, "trash row has no box");
    const delY = delBox.y + delBox.height / 2;
    const delStartX = delBox.x + delBox.width - 10;
    await page.mouse.move(delStartX, delY);
    await page.mouse.down();
    for (let i = 1; i <= 12; i++) await page.mouse.move(delStartX - (delBox.width * 0.8 * i) / 12, delY, { steps: 1 });
    await page.mouse.up();
    await page.waitForSelector(".confirm-dialog");
    const deleteTitle = await page.textContent(".confirm-title");
    assert(deleteTitle === "Delete forever?", `expected the permanent-delete confirmation, got "${deleteTitle}"`);
    await page.click(".confirm-confirm");

    const deleteToast = await page.waitForSelector(".toast:not([hidden])", { timeout: 5000 }).then((el) => el.textContent());
    assert(!!deleteToast && /could not delete/i.test(deleteToast), `a failed permanent delete must surface a visible "could not delete" message, got: "${deleteToast}"`);
    assert((await trash.locator(".list-row").count()) === 2, "a failed permanent delete must leave the QuKi in Trash, not disappear as if it had actually been deleted");
    console.log(`[e2e-trash-errors] PASS: a rejected permanentlyDelete() surfaced a visible message and left the row in place: "${deleteToast}"`);
    await waitForToastHidden(page);

    // --- Empty Trash, forced to fail ---
    await trash.locator(".empty-trash-btn").click();
    await page.waitForSelector(".confirm-dialog");
    const emptyTitle = await page.textContent(".confirm-title");
    assert(emptyTitle === "Empty Trash?", `expected the Empty Trash confirmation, got "${emptyTitle}"`);
    await page.click(".confirm-confirm");

    const emptyToast = await page.waitForSelector(".toast:not([hidden])", { timeout: 5000 }).then((el) => el.textContent());
    assert(!!emptyToast && /could not empty trash/i.test(emptyToast), `a failed Empty Trash must surface a visible "could not empty Trash" message, got: "${emptyToast}"`);
    assert((await trash.locator(".list-row").count()) === 2, "a failed Empty Trash must leave the QuKis in Trash, not disappear as if it had actually emptied");
    console.log(`[e2e-trash-errors] PASS: a rejected emptyTrash() surfaced a visible message and left both rows in place: "${emptyToast}"`);

    // --- None of the three failures should have leaked as an unhandled
    // promise rejection - the exact bug this fix closes. ---
    const rejections = await page.evaluate(() => (window as unknown as { __unhandledRejections: string[] }).__unhandledRejections);
    assert(rejections.length === 0, `no trash action should leave an unhandled promise rejection, but got: ${JSON.stringify(rejections)}`);
    console.log("[e2e-trash-errors] PASS: none of the three forced failures leaked as an unhandled promise rejection");

    await context.close();
    console.log("[e2e-trash-errors] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((err: unknown) => {
  console.error("[e2e-trash-errors] FAILED:", err);
  process.exit(1);
});
