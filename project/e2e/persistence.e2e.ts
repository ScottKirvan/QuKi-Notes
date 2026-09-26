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
  console.log(`[e2e] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    // --- Scenario 1: type, wait for auto-save, reload, confirm persistence ---
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    const marker = `E2E persistence proof ${Date.now()}`;
    await page.click(".cm-content");
    await page.keyboard.press("Control+A");
    await page.keyboard.type(marker);

    const bodyBeforeReload = await page.evaluate(
      () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
    );
    assert(bodyBeforeReload.includes(marker), "typed text should be in the live editor before reload");
    console.log("[e2e] typed content is present in the live editor");

    // 2s debounce + margin, so the auto-save has actually landed in OPFS.
    await page.waitForTimeout(2500);

    // BEHAVIOR_SPEC.md §4: "a blank canvas on launch" - reload must not
    // reopen the pre-reload content. What this scenario actually proves is
    // that the earlier save really landed in OPFS; checked here via the
    // QuKi list's per-row preview (a real read of the file), not via what
    // the editor shows on open.
    await page.reload();
    await page.waitForSelector(".cm-content");
    const bodyAfterReload = await page.evaluate(
      () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
    );
    assert(bodyAfterReload === "", `the editor should be blank on reload per BEHAVIOR_SPEC.md §4, got: ${bodyAfterReload}`);

    await page.click("#btn-quki-list");
    await page.locator(".list-row-preview", { hasText: marker }).waitFor({ timeout: 5000 });
    console.log("[e2e] PASS: content survived a full page reload via OPFS persistence, visible in the QuKi list");

    await page.click("#view-list .back-btn");
    await page.waitForSelector("#view-editor:not([hidden])");

    // --- Scenario 2: two tabs open the SAME already-saved QuKi (the one
    // from scenario 1, opened explicitly from the list - BEHAVIOR_SPEC.md
    // §4 means there's no "reopens automatically" path to rely on here) and
    // race a save; the loser's edit surfaces a visible conflict message
    // rather than silently clobbering the winner's write.
    //
    // OPFS storage is scoped per browser *context* (profile), not just per
    // origin - a fresh browser.newContext() would give each tab its own
    // empty OPFS and no collision would ever be possible. Both tabs must
    // share the context used above so they see the same on-disk QuKi. ---
    const pageA = await context.newPage();
    const pageB = await context.newPage();

    await pageA.goto(url);
    await pageA.waitForSelector(".cm-content");
    await pageA.click("#btn-quki-list");
    await pageA.locator(".list-row-preview", { hasText: marker }).click();
    await pageA.waitForSelector(".cm-content");

    await pageB.goto(url);
    await pageB.waitForSelector(".cm-content");
    await pageB.click("#btn-quki-list");
    await pageB.locator(".list-row-preview", { hasText: marker }).click();
    await pageB.waitForSelector(".cm-content");

    await pageA.click(".cm-content");
    await pageA.keyboard.press("Control+A");
    await pageA.keyboard.type("Written from tab A");
    await pageA.waitForTimeout(2500); // let A's save land first

    await pageB.click(".cm-content");
    await pageB.keyboard.press("Control+A");
    await pageB.keyboard.type("Written from tab B, conflicting");
    await pageB.waitForTimeout(2500); // B's save should now conflict against A's write

    const statusHiddenAttr = await pageB.getAttribute("#save-status", "hidden");
    assert(statusHiddenAttr === null, "conflict banner should be visible (not hidden) on the losing tab");
    const statusText = await pageB.textContent("#save-status");
    assert(!!statusText && statusText.length > 0, "conflict banner should have a visible message");
    console.log(`[e2e] PASS: losing tab surfaced a visible conflict: "${statusText}"`);

    // The winning tab's write must not have been silently overwritten on
    // disk - checked via the list's per-row preview (a real read of the
    // file), since reload no longer reopens what was showing before it.
    await pageA.click("#btn-quki-list");
    await pageA.locator(".list-row-preview", { hasText: "Written from tab A" }).waitFor({ timeout: 5000 });
    const racePreviews = await pageA.locator(".list-row-preview").allTextContents();
    assert(
      racePreviews.some((t) => t.includes("Written from tab A")),
      `on-disk content should still be tab A's write, got previews: ${JSON.stringify(racePreviews)}`,
    );
    assert(!racePreviews.some((t) => t.includes("conflicting")), "the losing tab's conflicting edit must not have landed on disk");
    console.log("[e2e] PASS: the conflicting write from tab B never landed on disk");

    await context.close();

    // --- Scenario 3: store.save() throws (not a conflict result - an actual
    // exception), reproducing the real-world root cause: crypto.randomUUID()
    // unavailable when creating a brand-new QuKi. This must surface a
    // visible, honest "something went wrong" banner instead of vanishing as
    // an unhandled promise rejection. A fresh context gives this page an
    // empty OPFS, so its first save takes the createNew() path that calls
    // crypto.randomUUID(). ---
    const errorContext = await browser.newContext();
    const errorPage = await errorContext.newPage();
    await errorPage.addInitScript(() => {
      Object.defineProperty(window.crypto, "randomUUID", {
        configurable: true,
        value: () => {
          throw new TypeError("crypto.randomUUID is not a function");
        },
      });
    });

    await errorPage.goto(url);
    await errorPage.waitForSelector(".cm-content");
    await errorPage.click(".cm-content");
    await errorPage.keyboard.press("Control+A");
    await errorPage.keyboard.type("This save should throw, not vanish silently");

    await errorPage.waitForTimeout(2500); // 2s debounce + margin

    const errorStatusHiddenAttr = await errorPage.getAttribute("#save-status", "hidden");
    assert(errorStatusHiddenAttr === null, "save-error banner should be visible (not hidden) after a thrown save error");
    const errorStatusText = await errorPage.textContent("#save-status");
    assert(!!errorStatusText && errorStatusText.length > 0, "save-error banner should have a visible message");
    assert(
      !errorStatusText.includes("elsewhere"),
      `a thrown save error must not be mislabeled as a conflict, got: "${errorStatusText}"`,
    );
    assert(
      /unexpected error/i.test(errorStatusText),
      `save-error banner should honestly describe an unexpected error, got: "${errorStatusText}"`,
    );
    console.log(`[e2e] PASS: a thrown store.save() surfaced a visible, honest error banner: "${errorStatusText}"`);

    await errorContext.close();

    // --- Scenario 4: opening an existing QuKi from the list whose
    // store.read() throws. BEHAVIOR_SPEC.md §4's blank canvas means launch
    // itself never touches storage any more, so there is no "initial load"
    // read left to fail there - the read failure this scenario reproduces
    // now happens on the equivalent real, reachable path: main.ts's
    // openQuKiInEditor. This must surface a visible, honest banner and leave
    // the editor as it was (blank, still usable) instead of an unhandled
    // rejection.
    //
    // FileSystemFileHandle.getFile() backs both readText() and stat()
    // (project/core/src/opfsBackend.ts), and stat() is also what
    // QuKiStore.list() uses to build each row's summary - so failing
    // getFile() from page load onward would break list() itself (the QuKis
    // button would never even enable) before the scenario got anywhere near
    // openQuKiInEditor's own read. The override is installed only after the
    // QuKi is created and the list has already opened and rendered its real
    // preview (both of which depend on working list()/read() calls) - so it
    // targets exactly the read triggered by the click below, not the
    // discovery reads that had to succeed first. ---
    const loadErrorContext = await browser.newContext();
    const loadErrorPage = await loadErrorContext.newPage();
    await loadErrorPage.goto(url);
    await loadErrorPage.waitForSelector(".cm-content");
    await loadErrorPage.click(".cm-content");
    await loadErrorPage.keyboard.press("Control+A");
    await loadErrorPage.keyboard.type("seed QuKi for the open-failure scenario");
    await loadErrorPage.waitForTimeout(2500);

    // A fresh blank QuKi, so opening the seeded one back up below is a real
    // "open an existing QuKi" read, not just already-showing content.
    await loadErrorPage.click("#btn-new-quki");

    await loadErrorPage.click("#btn-quki-list");
    const seedRow = loadErrorPage.locator(".list-row-preview", { hasText: "seed QuKi for the open-failure scenario" });
    await seedRow.waitFor({ timeout: 5000 });

    await loadErrorPage.evaluate(() => {
      Object.defineProperty(FileSystemFileHandle.prototype, "getFile", {
        configurable: true,
        value: () => {
          throw new DOMException("simulated read failure", "NotReadableError");
        },
      });
    });

    await seedRow.click();
    // openQuKiInEditor's flush-then-read is async, so the click resolving
    // doesn't mean the resulting catch block has updated the DOM yet. This
    // checks the element's own "hidden" attribute directly, not Playwright's
    // notion of on-screen visibility - #save-status lives inside
    // #view-editor's markup (index.html), which the Navigator itself marks
    // hidden while the QuKi list is the active screen, regardless of
    // #save-status's own state. That's a real, pre-existing quirk (the same
    // showSaveStatus call deleteQuKi's error path uses from the list has the
    // identical issue), out of scope for this change - not something to
    // paper over here.
    await loadErrorPage.waitForFunction(
      () => document.querySelector("#save-status")?.hasAttribute("hidden") === false,
      { timeout: 5000 },
    );

    const loadErrorStatusHiddenAttr = await loadErrorPage.getAttribute("#save-status", "hidden");
    assert(loadErrorStatusHiddenAttr === null, "load-error banner should be visible (not hidden) after a thrown QuKi-open read");
    const loadErrorStatusText = await loadErrorPage.textContent("#save-status");
    assert(!!loadErrorStatusText && loadErrorStatusText.length > 0, "load-error banner should have a visible message");
    assert(
      /unexpected error/i.test(loadErrorStatusText),
      `load-error banner should honestly describe an unexpected error, got: "${loadErrorStatusText}"`,
    );
    console.log(`[e2e] PASS: a thrown QuKi-open read surfaced a visible, honest error banner: "${loadErrorStatusText}"`);

    const editorIsUsable = await loadErrorPage.evaluate(() => {
      const view = (window as unknown as { qukiView?: { state: { doc: { toString(): string } } } }).qukiView;
      return view !== undefined && view.state.doc.toString() === "";
    });
    assert(editorIsUsable, "editor should remain blank and usable after a failed QuKi-open, not be left uninitialized");
    console.log("[e2e] PASS: the editor remained blank and usable after the failed QuKi-open");

    await loadErrorContext.close();

    // --- Scenario 5: the conflict banner's "Overwrite" action is the
    // explicit, user-initiated escape hatch (STORAGE_CONTRACT.md rule 17) -
    // this reproduces a real conflict the same way scenario 2 does, then
    // clicks Overwrite and checks: the file gets the LATEST live content
    // (not whatever was live when the conflict first fired), the banner
    // clears, and a further normal edit afterwards saves cleanly rather
    // than staying stuck retrying. ---
    const overwriteContext = await browser.newContext();
    const overwriteSeedPage = await overwriteContext.newPage();
    await overwriteSeedPage.goto(url);
    await overwriteSeedPage.waitForSelector(".cm-content");
    await overwriteSeedPage.click(".cm-content");
    await overwriteSeedPage.keyboard.press("Control+A");
    await overwriteSeedPage.keyboard.type("Overwrite scenario: seed content");
    await overwriteSeedPage.waitForTimeout(2500);
    await overwriteSeedPage.close();

    const overwritePageA = await overwriteContext.newPage();
    const overwritePageB = await overwriteContext.newPage();
    await overwritePageA.goto(url);
    await overwritePageA.waitForSelector(".cm-content");
    await overwritePageA.click("#btn-quki-list");
    await overwritePageA.locator(".list-row-preview", { hasText: "Overwrite scenario: seed content" }).click();
    await overwritePageA.waitForSelector(".cm-content");

    await overwritePageB.goto(url);
    await overwritePageB.waitForSelector(".cm-content");
    await overwritePageB.click("#btn-quki-list");
    await overwritePageB.locator(".list-row-preview", { hasText: "Overwrite scenario: seed content" }).click();
    await overwritePageB.waitForSelector(".cm-content");

    await overwritePageA.click(".cm-content");
    await overwritePageA.keyboard.press("Control+A");
    await overwritePageA.keyboard.type("Overwrite scenario: written from tab A");
    await overwritePageA.waitForTimeout(2500); // let A's save land first

    await overwritePageB.click(".cm-content");
    await overwritePageB.keyboard.press("Control+A");
    await overwritePageB.keyboard.type("Overwrite scenario: tab B's first conflicting edit");
    await overwritePageB.waitForTimeout(2500); // B's save now conflicts against A's write

    const conflictHiddenAttr = await overwritePageB.getAttribute("#save-status", "hidden");
    assert(conflictHiddenAttr === null, "conflict banner should be visible before Overwrite is clicked");
    const overwriteButtonVisible = await overwritePageB.isVisible("#save-status .save-status-action");
    assert(overwriteButtonVisible, "the conflict banner should show a visible Overwrite button");
    console.log("[e2e] PASS: the conflict banner shows a visible Overwrite button");

    // More typing after the conflict banner appeared, before clicking
    // Overwrite - this later text must be what gets saved, not the text
    // that was live when the conflict first fired.
    await overwritePageB.click(".cm-content");
    await overwritePageB.keyboard.press("Control+A");
    await overwritePageB.keyboard.type("Overwrite scenario: tab B's LATER edit, typed after the conflict banner appeared");

    await overwritePageB.click("#save-status .save-status-action");
    await overwritePageB.waitForTimeout(500); // the forced write is plain async I/O, not debounced

    const afterOverwriteHiddenAttr = await overwritePageB.getAttribute("#save-status", "hidden");
    assert(afterOverwriteHiddenAttr !== null, "the conflict banner should clear once Overwrite succeeds");
    console.log("[e2e] PASS: clicking Overwrite cleared the conflict banner");

    await overwritePageA.click("#btn-quki-list");
    await overwritePageA.locator(".list-row-preview", { hasText: "tab B's LATER edit" }).waitFor({ timeout: 5000 });
    const afterOverwritePreviews = await overwritePageA.locator(".list-row-preview").allTextContents();
    assert(
      afterOverwritePreviews.some((t) => t.includes("tab B's LATER edit")),
      `on-disk content should be tab B's later edit after Overwrite, got previews: ${JSON.stringify(afterOverwritePreviews)}`,
    );
    assert(
      !afterOverwritePreviews.some((t) => t.includes("first conflicting edit")),
      "the text live when the conflict first fired must not be what Overwrite saved",
    );
    console.log("[e2e] PASS: Overwrite wrote the LATEST live content, not the content from when the conflict first fired");

    // A further normal edit afterwards must save cleanly - the baseline is
    // correctly re-established, not stuck retrying against the old conflict.
    await overwritePageB.click(".cm-content");
    await overwritePageB.keyboard.press("Control+A");
    await overwritePageB.keyboard.type("Overwrite scenario: one more normal edit after Overwrite");
    await overwritePageB.waitForTimeout(2500);

    const afterFollowUpHiddenAttr = await overwritePageB.getAttribute("#save-status", "hidden");
    assert(afterFollowUpHiddenAttr !== null, "a normal save after Overwrite should not re-trigger the conflict banner");

    await overwritePageB.click("#btn-quki-list");
    await overwritePageB.locator(".list-row-preview", { hasText: "one more normal edit after Overwrite" }).waitFor({ timeout: 5000 });
    console.log("[e2e] PASS: a further normal edit after Overwrite saves cleanly - the baseline was correctly re-established");

    await overwriteContext.close();
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => {
    console.log("[e2e] ALL SCENARIOS PASSED");
    process.exit(0);
  })
  .catch((err: unknown) => {
    console.error("[e2e] FAILED:", err);
    process.exit(1);
  });
