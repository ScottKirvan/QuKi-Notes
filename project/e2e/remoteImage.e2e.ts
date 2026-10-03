import { chromium, type Page, type Route } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

// 1x1 transparent PNG, well-formed bytes so the browser's own image decoder
// actually has something real to decode - proof the widget's <img> genuinely
// renders decoded pixel data, not just that an <img> tag exists (same bytes
// imagePaste.e2e.ts uses for the same reason).
const ONE_PX_PNG_BASE64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
const ONE_PX_PNG_BYTES = Buffer.from(ONE_PX_PNG_BASE64, "base64");

async function setDocAndCaret(page: Page, text: string, caret: number): Promise<void> {
  await page.evaluate(
    ({ text, caret }) => {
      const view = (window as unknown as { qukiView: { state: { doc: { length: number } }; dispatch: (spec: unknown) => void } }).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: caret } });
    },
    { text, caret },
  );
  await page.waitForTimeout(150);
}

async function moveCaretTo(page: Page, pos: number): Promise<void> {
  await page.evaluate((pos) => {
    (window as unknown as { qukiView: { dispatch: (spec: unknown) => void } }).qukiView.dispatch({ selection: { anchor: pos } });
  }, pos);
  await page.waitForTimeout(150);
}

async function waitForImageSettled(page: Page): Promise<{ src: string; complete: boolean; naturalWidth: number; broken: boolean } | null> {
  await page.waitForFunction(() => document.querySelector(".cm-quki-image") !== null, { timeout: 5000 });
  await page.waitForFunction(
    () => {
      const img = document.querySelector<HTMLImageElement>(".cm-quki-image");
      return img !== null && (img.src !== "" || img.classList.contains("cm-quki-image-broken"));
    },
    { timeout: 5000 },
  );
  await page.waitForFunction(
    () => {
      const img = document.querySelector<HTMLImageElement>(".cm-quki-image");
      return img !== null && (img.complete || img.classList.contains("cm-quki-image-broken"));
    },
    { timeout: 5000 },
  );
  return page.evaluate(() => {
    const img = document.querySelector<HTMLImageElement>(".cm-quki-image");
    if (!img) return null;
    return { src: img.src, complete: img.complete, naturalWidth: img.naturalWidth, broken: img.classList.contains("cm-quki-image-broken") };
  });
}

async function waitForBrokenImage(page: Page): Promise<void> {
  await page.waitForFunction(
    () => document.querySelector(".cm-quki-image.cm-quki-image-broken") !== null,
    { timeout: 5000 },
  );
}

function fulfillPng(route: Route): Promise<void> {
  return route.fulfill({ status: 200, contentType: "image/png", body: ONE_PX_PNG_BYTES });
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-remote-image] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    // --- Scenario 1: a reachable http(s) image URL fetches and renders,
    // the same way a local media/-relative image already does. ---
    {
      const context = await browser.newContext();
      const page = await context.newPage();
      let requestCount = 0;
      await page.route("https://fake.quki-notes.test/pic.png", async (route) => {
        requestCount += 1;
        await fulfillPng(route);
      });
      await page.goto(url);
      await page.waitForSelector(".cm-content");
      await page.click(".cm-content");

      const doc = "![alt text](https://fake.quki-notes.test/pic.png)\n\nfollowing paragraph";
      // Caret starts at 0, inside the image markdown's own span - revealed
      // (raw source shown), so no widget is mounted and no fetch happens.
      await setDocAndCaret(page, doc, 0);
      assert(requestCount === 0, `expected no fetch while the image markdown is still revealed (caret on its own span), got ${requestCount}`);
      console.log("[e2e-remote-image] PASS: no fetch while the image's raw markdown is still shown (no prefetching)");

      await moveCaretTo(page, doc.length);
      const imgState = await waitForImageSettled(page);
      assert(imgState !== null, "expected a .cm-quki-image element once the caret moved off the image's span");
      assert(!imgState!.broken, `expected the remote image to resolve successfully, got broken state for src=${imgState!.src}`);
      assert(
        imgState!.src === "https://fake.quki-notes.test/pic.png",
        `expected the <img> src to be set directly to the remote URL (no fetch/blob indirection), got: ${imgState!.src}`,
      );
      assert(imgState!.complete, "expected the <img> to finish decoding");
      assert(imgState!.naturalWidth > 0, `expected decoded pixel data (naturalWidth>0), got ${imgState!.naturalWidth}`);
      assert(requestCount === 1, `expected exactly 1 network request for the image, got ${requestCount}`);
      console.log(`[e2e-remote-image] PASS: remote http(s) image URL set directly as <img src> and rendered (naturalWidth=${imgState!.naturalWidth})`);

      // --- Caching: revealing then re-collapsing the same URL must not
      // refetch over the network - the browser's own HTTP/in-memory image
      // cache serves the second load, with no app-level cache involved. ---
      await moveCaretTo(page, doc.indexOf("pic.png"));
      await page.waitForFunction(() => document.querySelector(".cm-quki-image") === null, { timeout: 5000 });
      await moveCaretTo(page, doc.length);
      await waitForImageSettled(page);
      assert(requestCount === 1, `expected the browser's own cache to serve the second load rather than refetching, got ${requestCount} requests`);
      console.log("[e2e-remote-image] PASS: re-revealing the same remote image reused the browser's own cache instead of refetching");

      await context.close();
    }

    // --- Scenario 2: a 404 response degrades to the same broken-image
    // state a failed local image read already uses. ---
    {
      const context = await browser.newContext();
      const page = await context.newPage();
      await page.route("https://fake.quki-notes.test/missing.png", async (route) => {
        await route.fulfill({ status: 404, contentType: "text/plain", body: "not found" });
      });
      await page.goto(url);
      await page.waitForSelector(".cm-content");
      await page.click(".cm-content");
      const doc = "![alt](https://fake.quki-notes.test/missing.png)\n\nx";
      await setDocAndCaret(page, doc, doc.length);
      await waitForBrokenImage(page);
      console.log("[e2e-remote-image] PASS: a 404 response falls back to the broken-image state");
      await context.close();
    }

    // --- Scenario 3: a non-image content-type (e.g. an HTML error page
    // served with a 200) also degrades to the broken-image state. ---
    {
      const context = await browser.newContext();
      const page = await context.newPage();
      await page.route("https://fake.quki-notes.test/not-an-image.png", async (route) => {
        await route.fulfill({ status: 200, contentType: "text/html", body: "<html>nope</html>" });
      });
      await page.goto(url);
      await page.waitForSelector(".cm-content");
      await page.click(".cm-content");
      const doc = "![alt](https://fake.quki-notes.test/not-an-image.png)\n\nx";
      await setDocAndCaret(page, doc, doc.length);
      await waitForBrokenImage(page);
      console.log("[e2e-remote-image] PASS: a non-image content-type falls back to the broken-image state");
      await context.close();
    }

    // --- Scenario 4: an aborted/failed request (network error, CORS
    // block, etc.) also degrades to the broken-image state. ---
    {
      const context = await browser.newContext();
      const page = await context.newPage();
      await page.route("https://fake.quki-notes.test/blocked.png", async (route) => {
        await route.abort("failed");
      });
      await page.goto(url);
      await page.waitForSelector(".cm-content");
      await page.click(".cm-content");
      const doc = "![alt](https://fake.quki-notes.test/blocked.png)\n\nx";
      await setDocAndCaret(page, doc, doc.length);
      await waitForBrokenImage(page);
      console.log("[e2e-remote-image] PASS: an aborted/blocked request falls back to the broken-image state");
      await context.close();
    }

    // --- Scenario 5: a local media/-relative image alongside a remote one
    // in the same document - the two resolution paths coexist without
    // interfering with each other. ---
    {
      const context = await browser.newContext();
      const page = await context.newPage();
      let requestCount = 0;
      await page.route("https://fake.quki-notes.test/mixed.png", async (route) => {
        requestCount += 1;
        await fulfillPng(route);
      });
      await page.goto(url);
      await page.waitForSelector(".cm-content");
      await page.click(".cm-content");
      // A local media/ reference with nothing on OPFS behind it can't
      // resolve either, but must reach ITS OWN broken state via the local
      // path (imageResolver), not be confused for a remote URL.
      const doc = "![remote](https://fake.quki-notes.test/mixed.png)\n\n![local](media/does-not-exist.png)\n\nx";
      await setDocAndCaret(page, doc, doc.length);
      await page.waitForFunction(() => document.querySelectorAll(".cm-quki-image").length === 2, { timeout: 5000 });
      await page.waitForFunction(
        () => [...document.querySelectorAll<HTMLImageElement>(".cm-quki-image")].every((img) => img.complete || img.classList.contains("cm-quki-image-broken")),
        { timeout: 5000 },
      );
      const states = await page.evaluate(() =>
        [...document.querySelectorAll<HTMLImageElement>(".cm-quki-image")].map((img) => ({
          src: img.src,
          broken: img.classList.contains("cm-quki-image-broken"),
        })),
      );
      assert(states.length === 2, `expected 2 image widgets, got ${states.length}`);
      assert(
        !states[0]!.broken && states[0]!.src === "https://fake.quki-notes.test/mixed.png",
        `expected the remote image to resolve via its own URL, got: ${JSON.stringify(states[0])}`,
      );
      assert(states[1]!.broken, `expected the missing local image to fall back to broken, got: ${JSON.stringify(states[1])}`);
      assert(requestCount === 1, `expected exactly 1 network request for the remote image, got ${requestCount}`);
      console.log("[e2e-remote-image] PASS: a remote image and a failing local image in the same document resolve independently");
      await context.close();
    }

    console.log("[e2e-remote-image] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-remote-image] FAILED:", err);
    process.exit(1);
  });
