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

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(
    () => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString(),
  );
}

// 1x1 transparent PNG, well-formed bytes so the browser's own image decoder
// actually has something real to load - a proof that the widget's <img>
// genuinely renders decoded pixel data, not just that an <img> tag exists.
const ONE_PX_PNG_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

/**
 * Installs a second, test-only "paste" listener on the CodeMirror content
 * element (the same node createImagePastePlugin's domEventHandlers
 * listener is attached to) that independently reads the image bytes out
 * of the real DOM ClipboardEvent and stashes them on window. This is not a
 * stub or a bypass of the real code path - it observes the same real
 * event our listener handles, from a second listener on the same node, so
 * the test can assert "what the app wrote to OPFS is exactly what the
 * browser's paste event actually delivered."
 *
 * This indirection is needed because Chromium's clipboard does not
 * guarantee byte-identical image data round-trips: writing a PNG via
 * navigator.clipboard.write() and reading it back via a paste event's
 * clipboardData can yield a re-encoded PNG (confirmed empirically - a
 * 68-byte source PNG came back as 87 bytes). That re-encoding happens
 * before our paste handler ever sees the data, so it is not something our
 * code could preserve even if it wanted to; comparing OPFS content against
 * the delivered bytes (rather than the originally-clipboard-written bytes)
 * is the correct fidelity check for what this feature is responsible for.
 */
async function installPasteByteCapture(page: Page): Promise<void> {
  await page.evaluate(() => {
    (window as unknown as { __qukiCapturedPasteBytes: number[] | null }).__qukiCapturedPasteBytes = null;
    document.querySelector(".cm-content")!.addEventListener("paste", (e: Event) => {
      const dt = (e as ClipboardEvent).clipboardData;
      if (!dt) return;
      for (const item of dt.items) {
        if (item.kind === "file" && item.type.startsWith("image/")) {
          const file = item.getAsFile();
          if (file) {
            void file.arrayBuffer().then((buf) => {
              (window as unknown as { __qukiCapturedPasteBytes: number[] | null }).__qukiCapturedPasteBytes = Array.from(
                new Uint8Array(buf),
              );
            });
          }
        }
      }
    });
  });
}

async function capturedPasteBytes(page: Page): Promise<number[]> {
  return page.evaluate(() => (window as unknown as { __qukiCapturedPasteBytes: number[] | null }).__qukiCapturedPasteBytes ?? []);
}

/**
 * Writes the given base64 image bytes to the real OS/browser clipboard as
 * an image/png ClipboardItem, then presses Ctrl+V - the genuine browser
 * paste path (not a synthetic dispatchEvent), so this exercises the real
 * `paste` DOM event our createImagePastePlugin domEventHandlers listener
 * is registered for.
 */
async function pasteImageViaClipboard(page: Page, base64: string): Promise<void> {
  await page.evaluate(async (b64) => {
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const blob = new Blob([bytes], { type: "image/png" });
    const item = new ClipboardItem({ "image/png": blob });
    await navigator.clipboard.write([item]);
  }, base64);
  await page.keyboard.press("Control+V");
}

async function readOpfsMediaFileBytes(page: Page, filename: string): Promise<number[]> {
  return page.evaluate(async (name) => {
    const root = await navigator.storage.getDirectory();
    const qukiDir = await root.getDirectoryHandle("quki");
    const mediaDir = await qukiDir.getDirectoryHandle("media");
    const fileHandle = await mediaDir.getFileHandle(name);
    const file = await fileHandle.getFile();
    return Array.from(new Uint8Array(await file.arrayBuffer()));
  }, filename);
}

function extractImageMarkdown(body: string): { full: string; relativePath: string } {
  const match = /!\[\]\((media\/[0-9a-f-]+\.png)\)/.exec(body);
  assert(!!match, `expected an inserted image markdown link in body, got: ${JSON.stringify(body)}`);
  return { full: match![0], relativePath: match![1]! };
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-image-paste] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    const context = await browser.newContext();
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");
    await installPasteByteCapture(page);

    // --- Scenario 1: plain text pasted into a blank editor (id: null)
    // should create a new QuKi exactly like typed text does, via the
    // existing auto-save path - no image-handling code should engage. ---
    assert((await page.getAttribute("#btn-quki-list", "disabled")) !== null, "QuKis button should start disabled with no QuKis yet");

    const textMarker = `ImagePaste text-paste marker ${Date.now()}`;
    await page.evaluate((t) => navigator.clipboard.writeText(t), textMarker);
    await page.click(".cm-content");
    await page.keyboard.press("Control+V");

    const bodyAfterTextPaste = await editorBody(page);
    assert(bodyAfterTextPaste === textMarker, `plain text paste should insert exactly the clipboard text, got: ${JSON.stringify(bodyAfterTextPaste)}`);
    console.log("[e2e-image-paste] PASS: plain text paste inserted normally, untouched by the image handler");

    await page.waitForTimeout(2500); // 2s debounce + margin for auto-save to land
    assert((await page.getAttribute("#btn-delete", "disabled")) === null, "Delete should be enabled once the pasted-text QuKi has been auto-saved");
    assert((await page.getAttribute("#btn-quki-list", "disabled")) === null, "QuKis button should be enabled once the pasted-text QuKi exists");

    await page.click("#btn-quki-list");
    const list = page.locator("#view-list");
    await list.locator(".list-row").first().waitFor({ timeout: 5000 });
    let rows = await list.locator(".list-row").count();
    assert(rows === 1, `expected exactly 1 QuKi to exist after pasting text into a blank editor, got ${rows}`);
    console.log("[e2e-image-paste] PASS: pasting plain text into a blank editor created a new QuKi via the existing auto-save path (no new code)");

    await list.locator(".back-btn").click();
    await page.waitForSelector(".cm-content");

    // --- Scenario 2: image paste into a brand-new, UNSAVED QuKi (id: null).
    // New QuKi resets to blank/unsaved first. ---
    await page.click("#btn-new-quki");
    assert((await editorBody(page)) === "", "New QuKi should start blank");
    assert((await page.getAttribute("#btn-delete", "disabled")) !== null, "Delete should be disabled on a fresh, unsaved New QuKi");

    await page.click(".cm-content");
    await page.keyboard.type("AB");
    await page.keyboard.press("ArrowLeft"); // cursor now sits between "A" and "B"

    await pasteImageViaClipboard(page, ONE_PX_PNG_BASE64);
    await page.waitForFunction(() => /!\[\]\(media\//.test((window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString()), { timeout: 5000 });

    const bodyAfterImagePasteUnsaved = await editorBody(page);
    const { full: markdownUnsaved, relativePath: relPathUnsaved } = extractImageMarkdown(bodyAfterImagePasteUnsaved);
    const expectedUnsaved = `A${markdownUnsaved}B`;
    assert(
      bodyAfterImagePasteUnsaved === expectedUnsaved,
      `image markdown should be inserted exactly at the cursor position between "A" and "B", got: ${JSON.stringify(bodyAfterImagePasteUnsaved)}`,
    );
    console.log(`[e2e-image-paste] PASS (unsaved QuKi): image markdown inserted at the correct cursor position: ${JSON.stringify(bodyAfterImagePasteUnsaved)}`);

    const filenameUnsaved = relPathUnsaved.split("/")[1]!;
    const storedBytesUnsaved = await readOpfsMediaFileBytes(page, filenameUnsaved);
    const capturedUnsaved = await capturedPasteBytes(page);
    assert(capturedUnsaved.length > 0, "test-side paste listener should have captured the pasted image's bytes");
    assert(
      storedBytesUnsaved.length === capturedUnsaved.length && storedBytesUnsaved.every((b, i) => b === capturedUnsaved[i]),
      `bytes written to OPFS media/${filenameUnsaved} should exactly match the bytes the browser's paste event actually delivered (got ${storedBytesUnsaved.length} bytes, expected ${capturedUnsaved.length})`,
    );
    console.log(`[e2e-image-paste] PASS (unsaved QuKi): media/${filenameUnsaved} on OPFS contains exactly the bytes delivered by the paste event (${storedBytesUnsaved.length} bytes)`);

    // media/ writes are not gated on the QuKi having an id yet.
    assert((await page.getAttribute("#btn-delete", "disabled")) !== null, "the QuKi is still unsaved immediately after an image paste (the markdown text itself hasn't been auto-saved yet)");

    // Move the caret away from the image's line so the reveal engine
    // collapses it into the actual ImageWidget <img> (BEHAVIOR_SPEC.md
    // reveal rule 2: caret resting immediately past the element still
    // reveals it - this is intentional, not a bug, so the test must move
    // the caret away rather than treating this as a failure).
    await page.keyboard.press("End");
    await page.keyboard.press("ArrowDown");

    await page.waitForFunction(() => document.querySelector(".cm-quki-image") !== null, { timeout: 5000 });
    // ImageWidget.toDOM() returns the <img> synchronously with no src; the
    // real blob: URL is only attached once the async OPFS read + Blob +
    // createObjectURL resolves. Wait for that to settle (or for the
    // broken-image fallback class, on failure) before reading state.
    await page.waitForFunction(
      () => {
        const img = document.querySelector<HTMLImageElement>(".cm-quki-image");
        return img !== null && (img.src !== "" || img.classList.contains("cm-quki-image-broken"));
      },
      { timeout: 5000 },
    );
    // src being non-empty doesn't mean the browser has finished decoding it
    // yet — wait for the <img> to actually complete loading before reading
    // naturalWidth, same as any real caller checking whether an image
    // rendered would have to.
    await page.waitForFunction(
      () => {
        const img = document.querySelector<HTMLImageElement>(".cm-quki-image");
        return img !== null && (img.complete || img.classList.contains("cm-quki-image-broken"));
      },
      { timeout: 5000 },
    );
    const imgState = await page.evaluate(() => {
      const img = document.querySelector<HTMLImageElement>(".cm-quki-image");
      if (!img) return null;
      return { src: img.src, complete: img.complete, naturalWidth: img.naturalWidth, alt: img.alt, broken: img.classList.contains("cm-quki-image-broken") };
    });
    assert(imgState !== null, "expected a .cm-quki-image <img> element once the caret moved off the image's line");
    console.log(`[e2e-image-paste] .cm-quki-image found: ${JSON.stringify(imgState)}`);
    assert(!imgState!.broken, `expected the image to resolve successfully, but ImageWidget fell back to its broken-image state for src=${imgState!.src}`);
    assert(imgState!.src.startsWith("blob:"), `expected the <img> src to be a resolved blob: URL (OPFS bytes via ImageWidget's imageResolver), got: ${imgState!.src}`);
    assert(imgState!.complete, `expected the <img> to finish decoding (complete=true), got complete=${imgState!.complete}`);
    assert(imgState!.naturalWidth > 0, `expected the <img> to have decoded real pixel data (naturalWidth>0), got naturalWidth=${imgState!.naturalWidth}`);
    console.log(`[e2e-image-paste] PASS (unsaved QuKi): pasted image rendered as a real <img> with decoded pixel data (naturalWidth=${imgState!.naturalWidth})`);

    // --- Blob URL lifecycle: moving the caret back onto the image's own
    // markdown text reveals it (rule 1/2's caret-inside-element case),
    // which removes the ImageWidget's decoration entirely and must run
    // ImageWidget.destroy() -> releaseImageUrl -> URL.revokeObjectURL on
    // the blob: URL captured above. A revoked blob: URL is no longer
    // fetchable, which is the observable proof the revoke actually ran
    // (not just that the code to call it exists). ---
    const blobUrlBeforeReveal = imgState!.src;
    const revealCaretPos = bodyAfterImagePasteUnsaved.indexOf(relPathUnsaved) + 1;
    await page.evaluate((pos) => {
      (window as unknown as { qukiView: { dispatch: (spec: unknown) => void } }).qukiView.dispatch({
        selection: { anchor: pos },
      });
    }, revealCaretPos);
    await page.waitForFunction(() => document.querySelector(".cm-quki-image") === null, { timeout: 5000 });
    console.log("[e2e-image-paste] caret moved onto the image's markdown — widget decoration removed (destroy() should have run)");

    const blobStillFetchable = await page.evaluate(async (url) => {
      try {
        await fetch(url);
        return true;
      } catch {
        return false;
      }
    }, blobUrlBeforeReveal);
    assert(!blobStillFetchable, `expected the blob: URL to have been revoked once its ImageWidget was destroyed, but it was still fetchable: ${blobUrlBeforeReveal}`);
    console.log(`[e2e-image-paste] PASS: blob: URL ${blobUrlBeforeReveal} was revoked (no longer fetchable) after the widget backing it was destroyed`);

    // Move the caret back off the image so it re-collapses, matching the
    // state the rest of the script (and scenario 3) expects.
    await page.keyboard.press("End");
    await page.keyboard.press("ArrowDown");
    await page.waitForFunction(() => document.querySelector(".cm-quki-image") !== null, { timeout: 5000 });

    // Let auto-save catch up so this QuKi is a real, saved QuKi before scenario 3.
    await page.waitForTimeout(2500);

    // --- Scenario 3: image paste into an EXISTING, already-saved QuKi
    // (reopen the QuKi created in Scenario 1 from the list, which was
    // saved via plain text paste). ---
    await page.click("#btn-quki-list");
    await list.locator(".list-row-preview", { hasText: "ImagePaste text-paste marker" }).click();
    await page.waitForSelector(".cm-content");
    const bodyBeforeSavedPaste = await editorBody(page);
    assert(bodyBeforeSavedPaste === textMarker, `expected to have reopened the text-paste QuKi, got: ${JSON.stringify(bodyBeforeSavedPaste)}`);
    assert((await page.getAttribute("#btn-delete", "disabled")) === null, "Delete should be enabled for this already-saved QuKi");

    await page.click(".cm-content");
    await page.keyboard.press("End"); // cursor at the end of the existing saved text
    await pasteImageViaClipboard(page, ONE_PX_PNG_BASE64);
    await page.waitForFunction(() => /!\[\]\(media\//.test((window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString()), { timeout: 5000 });

    const bodyAfterImagePasteSaved = await editorBody(page);
    const { full: markdownSaved, relativePath: relPathSaved } = extractImageMarkdown(bodyAfterImagePasteSaved);
    assert(
      bodyAfterImagePasteSaved === `${textMarker}${markdownSaved}`,
      `image markdown should be appended right after the existing saved text (cursor was at End), got: ${JSON.stringify(bodyAfterImagePasteSaved)}`,
    );
    assert(relPathSaved !== relPathUnsaved, "the second pasted image should get its own generated filename, distinct from the first");
    console.log(`[e2e-image-paste] PASS (already-saved QuKi): image markdown inserted at the correct cursor position: ${JSON.stringify(bodyAfterImagePasteSaved)}`);

    const filenameSaved = relPathSaved.split("/")[1]!;
    const storedBytesSaved = await readOpfsMediaFileBytes(page, filenameSaved);
    const capturedSaved = await capturedPasteBytes(page);
    assert(capturedSaved.length > 0, "test-side paste listener should have captured the second pasted image's bytes");
    assert(
      storedBytesSaved.length === capturedSaved.length && storedBytesSaved.every((b, i) => b === capturedSaved[i]),
      `bytes written to OPFS media/${filenameSaved} should exactly match the bytes the browser's paste event actually delivered`,
    );
    console.log(`[e2e-image-paste] PASS (already-saved QuKi): media/${filenameSaved} on OPFS contains exactly the bytes delivered by the paste event (${storedBytesSaved.length} bytes)`);

    console.log("[e2e-image-paste] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-image-paste] FAILED:", err);
    process.exit(1);
  });
