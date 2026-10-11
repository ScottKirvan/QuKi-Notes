import { chromium, type Page } from "playwright";
import { assert, serveDist } from "./serveDist.ts";

type WindowWithQukiView = typeof window & {
  qukiView: {
    state: { doc: { toString(): string; length: number } };
    dispatch: (spec: unknown) => void;
    focus: () => void;
    contentDOM: HTMLElement;
  };
};

const WEB_HTML =
  '<meta charset="utf-8"><h2 style="font-family:Arial">Shopping</h2><p><span style="color:#333">Buy <b>milk</b> and <a href="https://example.com/eggs">eggs</a></span></p><ul><li>one<ul><li>two</li></ul></li></ul>';
const WEB_PLAIN = "Shopping\n\nBuy milk and eggs\n\none\ntwo";
const WEB_MARKDOWN = "## Shopping\n\nBuy **milk** and [eggs](https://example.com/eggs)\n\n- one\n\t- two";

async function setDocAndCaret(page: Page, text: string, anchor: number, head = anchor): Promise<void> {
  await page.evaluate(
    ({ text, anchor, head }) => {
      const view = (window as WindowWithQukiView).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor, head } });
      view.focus();
    },
    { text, anchor, head },
  );
  await page.waitForTimeout(100);
}

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

async function dispatchPaste(page: Page, data: Record<string, string>): Promise<void> {
  await page.evaluate((data) => {
    const transfer = new DataTransfer();
    for (const [type, value] of Object.entries(data)) transfer.setData(type, value);
    (window as WindowWithQukiView).qukiView.contentDOM.dispatchEvent(
      new ClipboardEvent("paste", { clipboardData: transfer, bubbles: true, cancelable: true }),
    );
  }, data);
  await page.waitForTimeout(100);
}

async function writeClipboard(page: Page, data: Record<string, string>): Promise<void> {
  await page.evaluate(async (data) => {
    const item: Record<string, Blob> = {};
    for (const [type, value] of Object.entries(data)) item[type] = new Blob([value], { type });
    await navigator.clipboard.write([new ClipboardItem(item)]);
  }, data);
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext();
    await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: url });
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    await setDocAndCaret(page, "before\n", 7);
    await dispatchPaste(page, { "text/html": WEB_HTML, "text/plain": WEB_PLAIN });
    let body = await editorBody(page);
    assert(body === `before\n${WEB_MARKDOWN}`, `a paste carrying HTML should insert it as markdown at the caret, got ${JSON.stringify(body)}`);
    console.log("[e2e-htmlPaste] PASS: a paste event with text/html and text/plain inserts the HTML as markdown");

    await setDocAndCaret(page, "ab", 1);
    await dispatchPaste(page, { "text/plain": "- [ ] *x*\n\tsecond" });
    body = await editorBody(page);
    assert(body === "a- [ ] *x*\n\tsecondb", `a plain-text paste should insert the text unchanged, got ${JSON.stringify(body)}`);
    console.log("[e2e-htmlPaste] PASS: a plain-text paste inserts its text unchanged");

    const editorMarkdown = "- item with **bold**\n\t- nested";
    await setDocAndCaret(page, "", 0);
    await dispatchPaste(page, {
      "text/html": '<div style="white-space:pre"><div><span style="color:#569cd6">- </span><span>item with **bold**</span></div><div><span>\t- nested</span></div></div>',
      "text/plain": editorMarkdown,
    });
    body = await editorBody(page);
    assert(body === editorMarkdown, `markdown copied from a code editor should insert as its plain text, got ${JSON.stringify(body)}`);
    console.log("[e2e-htmlPaste] PASS: HTML that only wraps markdown source pastes as the plain text");

    await writeClipboard(page, { "text/html": WEB_HTML, "text/plain": WEB_PLAIN });
    await setDocAndCaret(page, "", 0);
    await page.keyboard.press("Control+V");
    await page.waitForTimeout(200);
    body = await editorBody(page);
    assert(body === WEB_MARKDOWN, `Ctrl+V of copied web content should insert markdown, got ${JSON.stringify(body)}`);
    console.log("[e2e-htmlPaste] PASS: Ctrl+V of copied web content inserts markdown");

    await setDocAndCaret(page, "", 0);
    await page.keyboard.press("Control+Shift+V");
    await page.waitForTimeout(200);
    body = await editorBody(page);
    assert(body === WEB_PLAIN, `Ctrl+Shift+V should insert the plain text, got ${JSON.stringify(body)}`);
    console.log("[e2e-htmlPaste] PASS: Ctrl+Shift+V pastes as plain text");

    await setDocAndCaret(page, "", 0);
    await page.evaluate(() => {
      (window as WindowWithQukiView).qukiView.contentDOM.dispatchEvent(
        new KeyboardEvent("keydown", { key: "V", code: "KeyV", metaKey: true, shiftKey: true, bubbles: true, cancelable: true }),
      );
    });
    await page.waitForFunction(() => (window as WindowWithQukiView).qukiView.state.doc.length > 0, { timeout: 3000 });
    body = await editorBody(page);
    assert(body === WEB_PLAIN, `Cmd+Shift+V that fires no paste event should still insert the plain text, got ${JSON.stringify(body)}`);
    console.log("[e2e-htmlPaste] PASS: Cmd+Shift+V with no native paste event reads and inserts the plain text");

    await writeClipboard(page, {
      "text/html": '<a href="https://example.com/">https://example.com/</a>',
      "text/plain": "https://example.com/",
    });
    await setDocAndCaret(page, "see docs here", 4, 8);
    await page.keyboard.press("Control+V");
    await page.waitForTimeout(200);
    body = await editorBody(page);
    assert(body === "see [docs](https://example.com/) here", `pasting a URL over selected text should still make a link, got ${JSON.stringify(body)}`);
    console.log("[e2e-htmlPaste] PASS: pasting a copied link over selected text still makes a markdown link");
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
