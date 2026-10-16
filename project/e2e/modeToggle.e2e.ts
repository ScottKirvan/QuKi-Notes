import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type WindowWithQukiView = typeof window & {
  qukiView: { contentDOM: HTMLElement };
  editorBlurCount: number;
};

async function plainTextOn(page: Page): Promise<boolean> {
  return (await page.getAttribute("#btn-mode-toggle", "aria-pressed")) === "true";
}

/**
 * The mode button's icon: the markdown mark (its 208x128 viewBox), Lucide's
 * code-xml (its slash), or whatever else, by its markup.
 */
async function modeIcon(page: Page): Promise<string> {
  return page.evaluate(() => {
    const svgs = document.querySelectorAll("#btn-mode-toggle svg");
    if (svgs.length !== 1) return `${svgs.length} svgs`;
    const svg = svgs[0];
    if (svg.getAttribute("viewBox") === "0 0 208 128") return "markdown";
    if (svg.querySelector('path[d="m14.5 4-5 16"]')) return "code";
    return svg.outerHTML;
  });
}

async function editorHasFocus(page: Page): Promise<boolean> {
  return page.evaluate(() => document.activeElement === (window as WindowWithQukiView).qukiView.contentDOM);
}

async function toolbarVisible(page: Page): Promise<boolean> {
  return page.locator(".formatting-toolbar").isVisible();
}

/**
 * Counts every blur of the editor from now on. On Android the soft keyboard
 * goes away the moment the editor loses focus, even if it is refocused
 * straight after, so a tap must never blur the editor at all.
 */
async function startCountingEditorBlurs(page: Page): Promise<void> {
  await page.evaluate(() => {
    const w = window as WindowWithQukiView;
    w.editorBlurCount = 0;
    w.qukiView.contentDOM.addEventListener("blur", () => (w.editorBlurCount += 1));
  });
}

async function editorBlurCount(page: Page): Promise<number> {
  return page.evaluate(() => (window as WindowWithQukiView).editorBlurCount);
}

async function openEditor(browser: Browser, url: string): Promise<{ page: Page; done: () => Promise<void> }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  return {
    page,
    done: async () => {
      assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
      await context.close();
    },
  };
}

async function whileEditingItTogglesWithoutLeavingTheEditor(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-mode-toggle:editing]";
  const { page, done } = await openEditor(browser, url);
  await page.click(".cm-content");
  await page.keyboard.type("Some text");
  assert(await toolbarVisible(page), `${tag} precondition: editing, so the toolbar is up`);
  assert(!(await plainTextOn(page)), `${tag} precondition: starts in rendered mode`);
  assert((await modeIcon(page)) === "markdown", `${tag} rendered: the icon must be the markdown mark, got ${await modeIcon(page)}`);
  await startCountingEditorBlurs(page);

  await page.click("#btn-mode-toggle");
  assert(await plainTextOn(page), `${tag} a tap while editing must switch to plain text`);
  assert((await modeIcon(page)) === "code", `${tag} plain text: the icon must be the code icon, got ${await modeIcon(page)}`);
  assert((await editorBlurCount(page)) === 0, `${tag} the tap must never take focus from the editor (that drops the Android keyboard)`);
  assert(await editorHasFocus(page), `${tag} the editor must still have focus`);
  assert(await toolbarVisible(page), `${tag} still editing, so the toolbar stays up`);

  await page.click("#btn-mode-toggle");
  assert(!(await plainTextOn(page)), `${tag} a second tap while editing must switch back to rendered`);
  assert((await editorBlurCount(page)) === 0, `${tag} the second tap must not take focus from the editor either`);
  console.log(`${tag} PASS: while editing, a tap switches modes and the editor never loses focus`);
  await done();
}

async function stopEditing(page: Page): Promise<void> {
  await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
  await page.locator(".formatting-toolbar").waitFor({ state: "hidden" });
}

async function whileReadingItSwitchesAndKeepsReading(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-mode-toggle:reading]";
  const { page, done } = await openEditor(browser, url);
  await page.click(".cm-content");
  await page.keyboard.type("Some text");
  await stopEditing(page);
  assert(!(await plainTextOn(page)), `${tag} precondition: starts in rendered mode`);
  assert((await modeIcon(page)) === "markdown", `${tag} rendered while reading: the icon must be the markdown mark, got ${await modeIcon(page)}`);

  await page.click("#btn-mode-toggle");
  assert(await plainTextOn(page), `${tag} a tap while reading must switch to plain text`);
  assert(!(await editorHasFocus(page)), `${tag} a tap while reading must not start editing`);
  assert(!(await toolbarVisible(page)), `${tag} still reading, so the toolbar stays hidden`);
  assert((await modeIcon(page)) === "code", `${tag} plain text while reading: the icon must be the code icon, got ${await modeIcon(page)}`);

  await page.click("#btn-mode-toggle");
  assert(!(await plainTextOn(page)), `${tag} a second tap while reading must switch back to rendered`);
  assert((await modeIcon(page)) === "markdown", `${tag} back to rendered while reading: the icon must be the markdown mark, got ${await modeIcon(page)}`);
  assert(!(await editorHasFocus(page)), `${tag} the second tap must not start editing either`);
  assert(!(await toolbarVisible(page)), `${tag} the toolbar stays hidden after the second tap`);
  console.log(`${tag} PASS: while reading, a tap switches modes and stays in reading mode`);
  await done();
}

const IMAGE_URL = "https://fake.quki-notes.test/tall.svg";
const TALL_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="240"><rect width="300" height="240" fill="#888"/></svg>';

function longQuKi(): string {
  const parts: string[] = [];
  for (let section = 1; section <= 12; section += 1) {
    parts.push(`# Heading ${section}`, "");
    parts.push(`Paragraph for section ${section} with **bold** and *italic* and \`code\`.`, "");
    parts.push(`![picture ${section}](${IMAGE_URL})`, "");
    parts.push(`- item one of ${section}`, `- item two of ${section}`, `  - nested item of ${section}`, "");
    parts.push(`## Sub heading ${section}`, "");
    parts.push("| a | b |", "| - | - |", `| ${section} | x |`, "");
    parts.push(`> quoted line ${section}`, "");
  }
  return parts.join("\n");
}

/**
 * The line at the top of the visible editor area and its distance from that
 * edge - what the user is looking at, wherever the scrolling happens.
 */
async function topVisibleLine(page: Page): Promise<{ line: number; offset: number }> {
  return page.evaluate(() => {
    const view = (window as unknown as { qukiView: import("@codemirror/view").EditorView }).qukiView;
    const top = view.scrollDOM.getBoundingClientRect().top;
    const content = view.contentDOM.getBoundingClientRect();
    const probeY = top;
    const pos = view.posAtCoords({ x: content.left + 4, y: probeY }, false);
    const line = view.state.doc.lineAt(pos);
    // The first line that starts below the probe, so a line partly scrolled
    // off the top (a tall image) can't be the anchor. Lines inside a table a
    // mode draws as one block don't start a block of their own.
    for (let n = line.number; n <= view.state.doc.lines; n += 1) {
      const candidate = view.state.doc.line(n);
      if (view.lineBlockAt(candidate.from).from !== candidate.from) continue;
      const coords = view.coordsAtPos(candidate.from, 1);
      if (coords && coords.top >= probeY) return { line: n, offset: coords.top - top };
    }
    throw new Error("no anchor line below the probe");
  });
}

async function lineOffset(page: Page, lineNumber: number): Promise<number> {
  return page.evaluate((n) => {
    const view = (window as unknown as { qukiView: import("@codemirror/view").EditorView }).qukiView;
    const top = view.scrollDOM.getBoundingClientRect().top;
    const coords = view.coordsAtPos(view.state.doc.line(n).from, 1);
    if (!coords) throw new Error(`line ${n} is not on screen`);
    return coords.top - top;
  }, lineNumber);
}

async function settle(page: Page): Promise<void> {
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
  await page.waitForTimeout(200);
}

async function scrollToLine(page: Page, lineNumber: number): Promise<void> {
  // Heights above the target are estimates until drawn, so correct from
  // where the line actually lands until it sits at the top.
  for (let attempt = 0; attempt < 5; attempt += 1) {
    await page.evaluate((n) => {
      const view = (window as unknown as { qukiView: import("@codemirror/view").EditorView }).qukiView;
      const from = view.state.doc.line(n).from;
      const coords = view.coordsAtPos(from, 1);
      if (coords) view.scrollDOM.scrollTop += coords.top - view.scrollDOM.getBoundingClientRect().top;
      else view.scrollDOM.scrollTop = view.lineBlockAt(from).top;
    }, lineNumber);
    await settle(page);
  }
  const scrolledTo = (await topVisibleLine(page)).line;
  assert(Math.abs(scrolledTo - lineNumber) <= 1, `precondition: scrolled line ${lineNumber} to the top, got line ${scrolledTo}`);
}

async function switchingKeepsTheTextInPlace(browser: Browser, url: string, editing: boolean): Promise<void> {
  const tag = `[e2e-mode-toggle:scroll-${editing ? "editing" : "reading"}]`;
  const { page, done } = await openEditor(browser, url);
  await page.route(IMAGE_URL, (route) => route.fulfill({ status: 200, contentType: "image/svg+xml", body: TALL_SVG }));
  await page.click(".cm-content");
  const text = longQuKi();
  await page.evaluate((doc) => {
    const view = (window as WindowWithQukiView & { qukiView: { dispatch: (spec: unknown) => void } }).qukiView;
    view.dispatch({ changes: { from: 0, to: 0, insert: doc }, selection: { anchor: 0 } });
  }, text);
  if (!editing) await stopEditing(page);
  await page.waitForFunction(() => {
    const imgs = [...document.querySelectorAll<HTMLImageElement>(".cm-quki-image")];
    return imgs.length > 0 && imgs.every((img) => img.complete);
  });
  await settle(page);

  const lines = text.split("\n");
  // Each starts below an image, so the switch changes the height of what is
  // above the visible area as well as inside it.
  for (const [where, lineNumber] of [
    ["near the top", lines.indexOf("- item one of 1") + 1],
    ["in the middle", lines.indexOf("- item one of 6") + 1],
    ["near the end", lines.indexOf("- item one of 11") + 1],
  ] as const) {
    await scrollToLine(page, lineNumber);
    let caretLine = 0;
    if (editing) {
      // A text line a little further down, so the caret stays on screen
      // and its line keeps its own text in both modes.
      caretLine = (await topVisibleLine(page)).line + 1;
      while (/^(\||!\[|\s*$)/.test(text.split("\n")[caretLine - 1]!)) caretLine += 1;
      await page.evaluate((n) => {
        const view = (window as unknown as { qukiView: import("@codemirror/view").EditorView }).qukiView;
        view.dispatch({ selection: { anchor: view.state.doc.line(n).to } });
      }, caretLine);
      await settle(page);
    }
    for (const direction of ["to plain text", "back to rendered"]) {
      const before = editing ? { line: caretLine, offset: await lineOffset(page, caretLine) } : await topVisibleLine(page);
      await page.click("#btn-mode-toggle");
      await settle(page);
      const after = await lineOffset(page, before.line);
      assert(
        Math.abs(after - before.offset) <= 2,
        `${tag} switching ${direction} ${where} moved line ${before.line} from ${before.offset.toFixed(1)}px to ${after.toFixed(1)}px below the top bar`,
      );
      assert((await editorHasFocus(page)) === editing, `${tag} switching ${direction} ${where} must not change editing vs. reading`);
    }
  }
  console.log(`${tag} PASS: switching both ways near the top, middle and end keeps the text where it was on screen`);
  await done();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-mode-toggle] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await whileEditingItTogglesWithoutLeavingTheEditor(browser, url);
    await whileReadingItSwitchesAndKeepsReading(browser, url);
    await switchingKeepsTheTextInPlace(browser, url, false);
    await switchingKeepsTheTextInPlace(browser, url, true);
    console.log("[e2e-mode-toggle] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-mode-toggle] FAILED:", err);
    process.exit(1);
  });
