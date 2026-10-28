import { chromium, type Browser, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

type QukiWindow = typeof window & {
  qukiView: { state: { doc: { toString(): string } } };
  qukiSystemBack: () => Promise<void>;
  __visibility: DocumentVisibilityState;
};

const TAG = "[e2e-imageCleanupKeepsUnsavedLinks]";
const PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as QukiWindow).qukiView.state.doc.toString());
}

function imageLinks(text: string): string[] {
  return [...text.matchAll(/!\[\]\((media\/[^)]+)\)/g)].map((m) => m[1]!);
}

async function setVisibility(page: Page, state: DocumentVisibilityState): Promise<void> {
  await page.evaluate((state) => {
    (window as QukiWindow).__visibility = state;
    document.dispatchEvent(new Event("visibilitychange"));
  }, state);
}

async function pasteImage(page: Page): Promise<void> {
  const before = imageLinks(await editorBody(page)).length;
  await page.evaluate(async (b64) => {
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    await navigator.clipboard.write([new ClipboardItem({ "image/png": new Blob([bytes], { type: "image/png" }) })]);
  }, PNG);
  await page.keyboard.press("Control+V");
  await page.waitForFunction(
    (n) => ((window as QukiWindow).qukiView.state.doc.toString().match(/!\[\]\(media\//g) ?? []).length > n,
    before,
    { timeout: 5000 },
  );
}

async function qukiFolder(page: Page): Promise<{ md: Record<string, string>; media: string[] }> {
  return page.evaluate(async () => {
    const dir = await (await navigator.storage.getDirectory()).getDirectoryHandle("quki", { create: true });
    const md: Record<string, string> = {};
    const media: string[] = [];
    for await (const [name, handle] of (dir as unknown as { entries(): AsyncIterable<[string, FileSystemHandle]> }).entries()) {
      if (handle.kind === "file" && name.endsWith(".md")) md[name] = await (await (handle as FileSystemFileHandle).getFile()).text();
      if (handle.kind === "directory" && name === "media") {
        for await (const [file] of (handle as unknown as { entries(): AsyncIterable<[string, FileSystemHandle]> }).entries()) media.push(file);
      }
    }
    return { md, media };
  });
}

async function overwriteFileOutsideTheApp(page: Page, name: string, text: string): Promise<void> {
  await page.evaluate(
    async ([name, text]) => {
      const dir = await (await navigator.storage.getDirectory()).getDirectoryHandle("quki");
      const writable = await (await dir.getFileHandle(name)).createWritable();
      await writable.write(text);
      await writable.close();
    },
    [name, text] as const,
  );
}

async function bannerShowing(page: Page): Promise<boolean> {
  return (await page.getAttribute("#save-status", "hidden")) === null;
}

async function backToEditor(page: Page): Promise<void> {
  for (let i = 0; i < 4; i++) {
    if (await page.locator("#view-editor").isVisible()) return;
    await page.evaluate(() => (window as QukiWindow).qukiSystemBack());
    await page.waitForTimeout(300);
  }
  assert(await page.locator("#view-editor").isVisible(), "Back returns to the editor");
}

async function openingTrashDuringAConflictKeepsThePastedImage(browser: Browser, url: string): Promise<void> {
  const context = await browser.newContext({ viewport: { width: 420, height: 700 } });
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await context.addInitScript(() => {
    (window as QukiWindow).__visibility = "visible";
    Object.defineProperty(document, "visibilityState", { configurable: true, get: () => (window as QukiWindow).__visibility });
    Object.defineProperty(document, "hidden", { configurable: true, get: () => (window as QukiWindow).__visibility === "hidden" });
  });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await page.waitForFunction(() => typeof (window as QukiWindow).qukiSystemBack === "function");

  // Given a saved QuKi with one image, changed outside the app
  await clickFirstLine(page);
  await page.keyboard.type("sweep ");
  await pasteImage(page);
  await setVisibility(page, "hidden");
  await page.waitForTimeout(400);
  const [name] = Object.keys((await qukiFolder(page)).md);
  assert(name !== undefined, "the QuKi was saved when the app went out of sight");
  await overwriteFileOutsideTheApp(page, name!, "EXTERNAL\n");
  await setVisibility(page, "visible");

  // and a second image pasted while the conflict blocks saving
  await page.keyboard.press("End");
  await pasteImage(page);
  await page.waitForTimeout(2600);
  assert(await bannerShowing(page), "the conflict banner shows");
  const editorText = await editorBody(page);
  const links = imageLinks(editorText);
  assert(links.length === 2, `the editor holds two image links, got ${links.length}`);

  // When the user opens Trash (QuKi list -> Settings -> Trash) and comes back
  await page.click("#btn-quki-list");
  await page.locator("#view-list .settings-btn").click();
  await page.locator("#view-settings .trash-btn").click();
  await page.waitForSelector("#view-trash .empty-state, #view-trash .list-row");
  await page.waitForTimeout(500);
  await backToEditor(page);

  // Then every image the editor links still exists
  assert((await editorBody(page)) === editorText, "the editor text is unchanged by the Trash visit");
  const afterTrash = (await qukiFolder(page)).media;
  const missing = links.filter((link) => !afterTrash.includes(link.slice("media/".length)));
  assert(missing.length === 0, `opening Trash deleted ${missing.length} of ${links.length} image files the editor links: ${missing.join(", ")}`);
  console.log(`${TAG} PASS: opening Trash during a save conflict keeps the images the open editor links`);

  // And Overwrite saves links that all point at existing files
  await page.click("#save-status .save-status-action");
  await page.waitForTimeout(600);
  const after = await qukiFolder(page);
  assert(after.md[name!] === editorText, "Overwrite saves the editor text");
  assert(
    imageLinks(after.md[name!]!).every((link) => after.media.includes(link.slice("media/".length))),
    "every saved image link points at an existing file",
  );
  console.log(`${TAG} PASS: Overwrite saves links whose image files all exist`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    await openingTrashDuringAConflictKeepsThePastedImage(browser, url);
    console.log(`${TAG} ALL SCENARIOS PASSED`);
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error(`${TAG} FAILED:`, err);
    process.exit(1);
  });
