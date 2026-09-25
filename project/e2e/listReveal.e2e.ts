import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type BrowserContext, type CDPSession, type Locator, type Page } from "playwright";

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

type WindowWithQukiView = typeof window & {
  qukiView: {
    state: {
      doc: { toString(): string; length: number };
      selection: { main: { anchor: number; head: number } };
    };
    dispatch: (spec: unknown) => void;
    focus: () => void;
    hasFocus: boolean;
    contentDOM: HTMLElement;
    scrollDOM: HTMLElement;
    lineBlockAt: (pos: number) => { top: number };
  };
};

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

async function editorSelection(page: Page): Promise<{ anchor: number; head: number }> {
  return page.evaluate(() => {
    const { anchor, head } = (window as WindowWithQukiView).qukiView.state.selection.main;
    return { anchor, head };
  });
}

async function scrollTop(page: Page): Promise<number> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.scrollDOM.scrollTop);
}

async function editorHasFocus(page: Page): Promise<boolean> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.hasFocus);
}

async function setDocAndSelection(page: Page, text: string, anchor: number, head = anchor): Promise<void> {
  await page.evaluate(
    ({ text, anchor, head }) => {
      const view = (window as WindowWithQukiView).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor, head } });
    },
    { text, anchor, head },
  );
}

async function focusEditor(page: Page): Promise<void> {
  await page.evaluate(() => (window as WindowWithQukiView).qukiView.focus());
}

async function blurEditor(page: Page): Promise<void> {
  await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
}

/**
 * Scrolls the target task line into view and waits for the scroller to stop
 * moving. CodeMirror estimates the height of lines it has not rendered yet,
 * so one scrollTop assignment can land short of the line; retry until the
 * checkbox is actually rendered, then return the settled scrollTop.
 */
async function scrollTargetIntoView(page: Page, offset: number = TARGET_OFFSET): Promise<number> {
  for (let attempt = 0; attempt < 15; attempt++) {
    await page.evaluate((offset) => {
      const view = (window as WindowWithQukiView).qukiView;
      view.scrollDOM.scrollTop = view.lineBlockAt(offset).top - 120;
    }, offset);
    await page.waitForTimeout(150);
    if ((await page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox").count()) !== 1) continue;
    let previous = await scrollTop(page);
    for (let settle = 0; settle < 10; settle++) {
      await page.waitForTimeout(100);
      const current = await scrollTop(page);
      if (current === previous) return current;
      previous = current;
    }
  }
  throw new Error("scrollTargetIntoView: the target checkbox never rendered in the viewport");
}

async function stableBox(target: Locator): Promise<{ x: number; y: number; width: number; height: number }> {
  let previous = await target.boundingBox();
  for (let i = 0; i < 20; i++) {
    await new Promise((r) => setTimeout(r, 30));
    const current = await target.boundingBox();
    if (previous && current && previous.x === current.x && previous.y === current.y && current.width > 0) {
      return current;
    }
    previous = current;
  }
  throw new Error("stableBox: element position never stabilized");
}

async function touchTap(client: CDPSession, box: { x: number; y: number; width: number; height: number }): Promise<void> {
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y }] });
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
}

const FILLER = Array.from({ length: 60 }, (_, i) => `filler line ${i + 1}`).join("\n");
// The task sits far enough down that the scroller has to be scrolled to reach
// it, so a toggle that scrolled the view would change scrollTop.
const TARGET_DOC = `${FILLER}\n\n- [ ] target task\n- [x] done task\n\n${FILLER}`;
const TARGET_OFFSET = TARGET_DOC.indexOf("- [ ] target task");
const CARET_ELSEWHERE = TARGET_DOC.indexOf("filler line 30") + 6;

// The same target one and two levels deep, so a tap has to find its marker
// past leading whitespace that is hidden while collapsed.
const NESTED_DOC = `${FILLER}\n\n- parent\n\t- [ ] target task\n\t\t- [x] done task\n\n${FILLER}`;
const NESTED_OFFSET = NESTED_DOC.indexOf("\t- [ ] target task");

const WRAP = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua";
const LAYOUT_DOC = [
  "plain reference paragraph",
  "",
  `- alpha ${WRAP}`,
  `\t- bravo ${WRAP}`,
  `\t\t- charlie ${WRAP}`,
  "",
  `1. delta ${WRAP}`,
  `\t1. echo ${WRAP}`,
  "",
  ...Array.from({ length: 9 }, (_, i) => `1. filler${i}`),
  `1. foxtrot ${WRAP}`,
  "",
  `- [ ] golf ${WRAP}`,
  `\t- [x] hotel ${WRAP}`,
  `\t\t- [ ] india ${WRAP}`,
  "",
  "> juliet quoted",
  "",
  "trailing plain paragraph",
].join("\n");

interface LineGeometry {
  /** Left edge of the first visual row's text (after any marker widget). */
  firstRowLeft: number;
  /** Left edge of every later visual row's text. */
  laterRowLefts: number[];
  markerLeft: number | null;
  markerRight: number | null;
  paddingLeft: number;
  textIndent: string;
  text: string;
}

/**
 * Measures where each visual row of the line containing `needle` starts. Rows
 * are found by grouping the line's non-widget characters by their top edge.
 */
async function lineGeometry(page: Page, needle: string): Promise<LineGeometry> {
  return page.evaluate((needle) => {
    const line = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent?.includes(needle));
    if (!line) throw new Error("no line containing " + needle);
    const marker = line.querySelector<HTMLElement>(".cm-quki-marker");
    const rows = new Map<number, number>();
    const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (marker?.contains(node)) continue;
      const text = node.textContent ?? "";
      for (let i = 0; i < text.length; i++) {
        if (text[i] === " " || text[i] === "\t") continue;
        const range = document.createRange();
        range.setStart(node, i);
        range.setEnd(node, i + 1);
        const rect = range.getBoundingClientRect();
        if (rect.width === 0) continue;
        const top = Math.round(rect.top);
        const known = rows.get(top);
        if (known === undefined || rect.left < known) rows.set(top, rect.left);
      }
    }
    const lefts = [...rows.entries()].sort((a, b) => a[0] - b[0]).map(([, left]) => left);
    const style = getComputedStyle(line);
    const markerRect = marker?.getBoundingClientRect();
    return {
      firstRowLeft: lefts[0]!,
      laterRowLefts: lefts.slice(1),
      markerLeft: markerRect ? markerRect.left : null,
      markerRight: markerRect ? markerRect.right : null,
      paddingLeft: Number.parseFloat(style.paddingLeft),
      textIndent: style.textIndent,
      text: line.textContent ?? "",
    };
  }, needle);
}

function near(a: number, b: number, tolerance = 0.5): boolean {
  return Math.abs(a - b) <= tolerance;
}

async function openFreshPage(context: BrowserContext, url: string): Promise<Page> {
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  return page;
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-listReveal] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    // --- Rendered list, task and blockquote markers ---
    {
      const context = await browser.newContext();
      const page = await openFreshPage(context, url);

      const doc = ["intro", "", "- apple", "* pear", "", "1. one", "1. two", "1. three", "", "5. five", "1. six", "", "> quoted", "> > deeper", "", "- [ ] open", "- [x] done", "", "end"].join("\n");
      await setDocAndSelection(page, doc, doc.length);
      await page.waitForTimeout(150);

      assert((await page.locator(".cm-quki-bullet").count()) === 2, "both - and * items should render a bullet");
      const numbers = await page.locator(".cm-quki-ordered").allTextContents();
      assert(JSON.stringify(numbers) === JSON.stringify(["1.", "2.", "3.", "5.", "6."]), `ordered markers should render block-relative, got ${JSON.stringify(numbers)}`);
      assert((await editorBody(page)) === doc, "rendering the markers must not rewrite the source");
      console.log("[e2e-listReveal] PASS: bullets and block-relative ordered numbers render; source untouched");

      const boxes = page.locator(".cm-quki-checkbox");
      assert((await boxes.count()) === 2, "both task items should render a checkbox");
      assert((await boxes.nth(0).getAttribute("aria-checked")) === "false", "first checkbox should be unchecked");
      assert((await boxes.nth(1).getAttribute("aria-checked")) === "true", "second checkbox should be checked");
      assert((await boxes.nth(1).locator("polyline").count()) === 1, "checked checkbox should draw a tick");
      assert((await boxes.nth(0).locator("polyline").count()) === 0, "unchecked checkbox should not draw a tick");
      assert((await boxes.nth(0).textContent()) === "", "the checkbox is drawn, not a text glyph");
      console.log("[e2e-listReveal] PASS: task items render drawn checkboxes (checked and unchecked)");

      const decorationOf = async (text: string): Promise<string> =>
        page.evaluate((t) => {
          const el = [...document.querySelectorAll(".cm-line")].find((l) => l.textContent?.includes(t));
          const span = el?.querySelector(".cm-quki-checked-text");
          return span ? getComputedStyle(span).textDecorationLine : "none";
        }, text);
      assert((await decorationOf("done")).includes("line-through"), "checked item's content should be struck through");
      assert((await decorationOf("open")) === "none", "unchecked item's content should not be struck through");
      console.log("[e2e-listReveal] PASS: checked content is struck through, unchecked is not");

      const quoteLines = await page.locator(".cm-line.cm-quki-quote").count();
      assert(quoteLines === 2, `both quote lines should carry the quote bar, got ${quoteLines}`);
      const quotedColor = await page.evaluate(() => {
        const span = document.querySelector(".cm-quki-quote-text");
        return span ? getComputedStyle(span).color : "";
      });
      const bodyColor = await page.evaluate(() => getComputedStyle(document.body).color);
      assert(quotedColor !== "" && quotedColor !== bodyColor, `quoted content should be muted (quote ${quotedColor} vs body ${bodyColor})`);
      const lineText = await page.locator(".cm-line.cm-quki-quote").first().textContent();
      assert(lineText === "quoted", `the > marker should be hidden, got ${JSON.stringify(lineText)}`);
      console.log("[e2e-listReveal] PASS: blockquote lines hide their marker, carry a bar and mute their content");

      // Caret in the marker span reveals just that marker.
      const bulletMarkerAt = doc.indexOf("- apple");
      await setDocAndSelection(page, doc, bulletMarkerAt + 1);
      await page.waitForTimeout(100);
      assert((await page.locator(".cm-quki-bullet").count()) === 1, "caret inside a bullet's marker should reveal it (leaving one bullet)");
      const rawLine = await page.locator(".cm-line", { hasText: "apple" }).textContent();
      assert(rawLine === "- apple", `revealed marker should show as raw text, got ${JSON.stringify(rawLine)}`);
      console.log("[e2e-listReveal] PASS: caret in the marker reveals the raw marker");

      // Plain-text mode collapses and renders nothing.
      await setDocAndSelection(page, doc, doc.length);
      await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
      await page.waitForTimeout(150);
      const decorated = await page.locator(".cm-quki-marker, .cm-quki-list-line, .cm-quki-quote, .cm-quki-quote-text, .cm-quki-checked-text").count();
      assert(decorated === 0, `plain-text mode should add no list/quote decorations, found ${decorated}`);
      assert((await page.locator(".cm-line", { hasText: "quoted" }).first().textContent()) === "> quoted", "plain-text mode shows the raw > marker");
      console.log("[e2e-listReveal] PASS: plain-text mode shows raw markers and adds no decorations");

      await context.close();
    }

    // --- Layout indentation: depth, hanging wrapped rows, reveal ---
    {
      const context = await browser.newContext({ viewport: { width: 400, height: 900 } });
      const page = await openFreshPage(context, url);
      await setDocAndSelection(page, LAYOUT_DOC, LAYOUT_DOC.length);
      await page.waitForTimeout(200);

      const plain = await lineGeometry(page, "plain reference paragraph");
      const cases: [string, number][] = [
        ["alpha", 0], ["bravo", 1], ["charlie", 2],
        ["delta", 0], ["echo", 1], ["foxtrot", 0],
        ["golf", 0], ["hotel", 1], ["india", 2],
      ];
      const collapsed = new Map<string, LineGeometry>();
      for (const [needle, depth] of cases) {
        const g = await lineGeometry(page, needle);
        collapsed.set(needle, g);
        assert(g.laterRowLefts.length >= 1, `${needle}: the item should wrap onto more than one row at this width`);
        const expectedLeft = plain.firstRowLeft + 24 + 16 * depth;
        assert(near(g.firstRowLeft, expectedLeft), `${needle}: content should start ${24 + 16 * depth}px right of plain text (depth ${depth}); got ${g.firstRowLeft - plain.firstRowLeft}px`);
        for (const left of g.laterRowLefts) {
          assert(near(left, g.firstRowLeft), `${needle}: a wrapped row starts at ${left}, not under the content at ${g.firstRowLeft}`);
        }
        assert(g.markerRight !== null && near(g.markerRight, g.firstRowLeft), `${needle}: the marker's gutter should end where the content starts (${g.markerRight} vs ${g.firstRowLeft})`);
        assert(!/^\s/.test(g.text) && !g.text.includes("\t"), `${needle}: leading whitespace must not be shown, got ${JSON.stringify(g.text.slice(0, 12))}`);
      }
      console.log("[e2e-listReveal] PASS: bullets, numbers and checkboxes indent by depth and wrapped rows hang under the content at depths 0, 1 and 2");

      const twoDigit = await lineGeometry(page, "foxtrot");
      assert(twoDigit.text.startsWith("10."), `the tenth item should be numbered 10, got ${JSON.stringify(twoDigit.text.slice(0, 6))}`);
      console.log("[e2e-listReveal] PASS: a two-digit number keeps its content aligned with the wrapped rows");

      const trailing = await lineGeometry(page, "trailing plain paragraph");
      assert(near(trailing.firstRowLeft, plain.firstRowLeft) && trailing.textIndent === "0px", "a plain paragraph after a list must get no list gutter");
      const quoted = await lineGeometry(page, "juliet");
      assert(quoted.textIndent === "0px" && near(quoted.paddingLeft, 16), `a quote line keeps its own 16px indent, got padding ${quoted.paddingLeft}, text-indent ${quoted.textIndent}`);
      console.log("[e2e-listReveal] PASS: plain and quoted lines beside a list get no marker gutter");

      // Revealing a line: raw source, no layout indent, neighbours undisturbed.
      const bravoMarker = LAYOUT_DOC.indexOf("\t- bravo");
      for (const caret of [bravoMarker, bravoMarker + 1, bravoMarker + 3]) {
        await setDocAndSelection(page, LAYOUT_DOC, caret);
        await page.waitForTimeout(100);
        const revealed = await lineGeometry(page, "bravo");
        assert(revealed.text.startsWith("\t- bravo"), `caret ${caret - bravoMarker}: the revealed line should show its tab and marker raw, got ${JSON.stringify(revealed.text.slice(0, 10))}`);
        assert(!revealed.textIndent.startsWith("-") && near(revealed.paddingLeft, plain.paddingLeft), `caret ${caret - bravoMarker}: a revealed line gets no collapsed-layout indent; only its wrapped rows hang (padding ${revealed.paddingLeft}, text-indent ${revealed.textIndent})`);
        assert(revealed.markerLeft === null, `caret ${caret - bravoMarker}: a revealed line has no marker widget`);
        for (const neighbour of ["alpha", "charlie"]) {
          const g = await lineGeometry(page, neighbour);
          assert(near(g.firstRowLeft, collapsed.get(neighbour)!.firstRowLeft), `caret ${caret - bravoMarker}: ${neighbour} must not move when bravo is revealed`);
        }
      }
      console.log("[e2e-listReveal] PASS: a revealed indented line shows raw source at depth zero and moves no neighbour");

      await setDocAndSelection(page, LAYOUT_DOC, LAYOUT_DOC.length);
      await page.waitForTimeout(100);
      const collapsedAgain = await lineGeometry(page, "bravo");
      assert(near(collapsedAgain.firstRowLeft, collapsed.get("bravo")!.firstRowLeft), "moving the caret away collapses the line back to its indented layout");
      console.log("[e2e-listReveal] PASS: moving the caret away restores the indentation");

      await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
      await page.waitForTimeout(150);
      assert((await page.locator(".cm-quki-list-line, .cm-quki-marker").count()) === 0, "plain-text mode should leave every list line undecorated");
      const rawBravo = await lineGeometry(page, "bravo");
      assert(rawBravo.text.startsWith("\t- bravo") && near(rawBravo.paddingLeft, plain.paddingLeft), "plain-text mode shows the raw indented line");
      console.log("[e2e-listReveal] PASS: plain-text mode shows raw indented lines with no layout indent");

      await context.close();
    }

    // --- Tap the collapsed checkbox: mouse ---
    {
      const context = await browser.newContext();
      const page = await openFreshPage(context, url);

      await setDocAndSelection(page, TARGET_DOC, CARET_ELSEWHERE);
      await focusEditor(page);
      const scrollBefore = await scrollTargetIntoView(page);
      const selectionBefore = await editorSelection(page);
      assert(scrollBefore > 0, "the test needs the scroller scrolled away from the top");

      const target = page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox");
      await target.click();
      await page.waitForTimeout(150);

      assert((await editorBody(page)) === TARGET_DOC.replace("- [ ] target task", "- [x] target task"), "a mouse click on the collapsed checkbox should check it");
      const selectionAfter = await editorSelection(page);
      assert(JSON.stringify(selectionAfter) === JSON.stringify(selectionBefore), `cursor should be untouched: ${JSON.stringify(selectionBefore)} -> ${JSON.stringify(selectionAfter)}`);
      assert((await scrollTop(page)) === scrollBefore, `view should not scroll: ${scrollBefore} -> ${await scrollTop(page)}`);
      assert(await editorHasFocus(page), "the editor should keep the focus it had");
      console.log("[e2e-listReveal] PASS: mouse click toggles the checkbox, preserving cursor, scroll and focus");

      await page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox").click();
      await page.waitForTimeout(100);
      assert((await editorBody(page)) === TARGET_DOC, "a second click should uncheck it again (round trip)");
      console.log("[e2e-listReveal] PASS: mouse toggle round-trips exactly");

      // A selection whose head is inside the marker survives the toggle.
      const rangeAnchor = CARET_ELSEWHERE;
      const rangeHead = TARGET_OFFSET + 3; // inside the six-character marker being rewritten
      await setDocAndSelection(page, TARGET_DOC, rangeAnchor, rangeHead);
      await scrollTargetIntoView(page);
      const rangeTarget = page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox");
      await rangeTarget.click();
      await page.waitForTimeout(100);
      const rangeAfter = await editorSelection(page);
      assert(rangeAfter.anchor === rangeAnchor && rangeAfter.head === rangeHead, `a range selection whose head sits inside the marker should be preserved, got ${JSON.stringify(rangeAfter)}`);
      console.log("[e2e-listReveal] PASS: a selection head inside the rewritten marker is preserved by the toggle");

      // Reading mode: an unfocused editor stays unfocused and its cursor stays put.
      await setDocAndSelection(page, TARGET_DOC, CARET_ELSEWHERE);
      await blurEditor(page);
      await scrollTargetIntoView(page);
      const readingSelection = await editorSelection(page);
      await page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox").click();
      await page.waitForTimeout(100);
      assert((await editorBody(page)).includes("- [x] target task"), "tapping a checkbox in reading mode should still toggle it");
      assert(!(await editorHasFocus(page)), "tapping a checkbox must not pull an unfocused editor into edit mode");
      assert(JSON.stringify(await editorSelection(page)) === JSON.stringify(readingSelection), "reading-mode tap must not move the cursor");
      assert(!(await page.locator(".formatting-toolbar").isVisible()), "toolbar should stay hidden (still reading mode)");
      console.log("[e2e-listReveal] PASS: reading-mode tap toggles without focusing the editor or moving the cursor");

      // A revealed checkbox is ordinary text: no widget, and clicking its raw text does not toggle.
      await setDocAndSelection(page, TARGET_DOC, TARGET_OFFSET + 3);
      await focusEditor(page);
      await page.waitForTimeout(100);
      const revealedLine = page.locator(".cm-line", { hasText: "target task" });
      assert((await revealedLine.locator(".cm-quki-checkbox").count()) === 0, "a revealed checkbox has no interactive widget");
      assert((await revealedLine.textContent()) === "- [ ] target task", "the revealed marker shows raw source");
      await context.close();
    }

    // --- Tap an indented collapsed checkbox: mouse ---
    {
      const context = await browser.newContext();
      const page = await openFreshPage(context, url);

      await setDocAndSelection(page, NESTED_DOC, CARET_ELSEWHERE);
      await focusEditor(page);
      const scrollBefore = await scrollTargetIntoView(page, NESTED_OFFSET);
      const selectionBefore = await editorSelection(page);
      assert(scrollBefore > 0, "the test needs the scroller scrolled away from the top");

      await page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox").click();
      await page.waitForTimeout(150);
      assert((await editorBody(page)) === NESTED_DOC.replace("\t- [ ] target task", "\t- [x] target task"), "a click on an indented checkbox should check it, keeping its indentation");
      assert(JSON.stringify(await editorSelection(page)) === JSON.stringify(selectionBefore), "cursor should be untouched by a tap on an indented checkbox");
      assert((await scrollTop(page)) === scrollBefore, `view should not scroll: ${scrollBefore} -> ${await scrollTop(page)}`);
      assert(await editorHasFocus(page), "the editor should keep the focus it had");

      await page.locator(".cm-line", { hasText: "done task" }).locator(".cm-quki-checkbox").click();
      await page.waitForTimeout(100);
      assert((await editorBody(page)).includes("\t\t- [ ] done task"), "a checked checkbox two levels deep should uncheck");
      console.log("[e2e-listReveal] PASS: tapping an indented checkbox (depth 1 and 2) toggles it, preserving cursor, scroll and focus");

      await context.close();
    }

    // --- Tap the collapsed checkbox: real touch (CDP trusted touch events) ---
    {
      const context = await browser.newContext({ hasTouch: true, isMobile: true, viewport: { width: 412, height: 800 } });
      const page = await openFreshPage(context, url);
      const client = await context.newCDPSession(page);

      await setDocAndSelection(page, TARGET_DOC, CARET_ELSEWHERE);
      await focusEditor(page);
      const scrollBefore = await scrollTargetIntoView(page);
      const selectionBefore = await editorSelection(page);

      const target = page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox");
      assert((await target.count()) === 1, `target checkbox should be rendered (scrollTop=${scrollBefore})`);
      const box = await stableBox(target);
      await touchTap(client, box);
      await page.waitForTimeout(250);

      assert((await editorBody(page)) === TARGET_DOC.replace("- [ ] target task", "- [x] target task"), "a touch tap on the collapsed checkbox should check it");
      assert(JSON.stringify(await editorSelection(page)) === JSON.stringify(selectionBefore), `touch tap must not move the cursor: ${JSON.stringify(selectionBefore)} -> ${JSON.stringify(await editorSelection(page))}`);
      assert((await scrollTop(page)) === scrollBefore, `touch tap must not scroll: ${scrollBefore} -> ${await scrollTop(page)}`);
      assert(await editorHasFocus(page), "touch tap must not blur the editor");
      console.log("[e2e-listReveal] PASS: touch tap toggles the checkbox, preserving cursor, scroll and focus");

      const again = page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox");
      await touchTap(client, await stableBox(again));
      await page.waitForTimeout(250);
      assert((await editorBody(page)) === TARGET_DOC, "a second touch tap should uncheck it again");
      console.log("[e2e-listReveal] PASS: touch toggle round-trips exactly");

      await setDocAndSelection(page, TARGET_DOC, CARET_ELSEWHERE);
      await blurEditor(page);
      await scrollTargetIntoView(page);
      const readingSelection = await editorSelection(page);
      const readingTarget = page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox");
      await touchTap(client, await stableBox(readingTarget));
      await page.waitForTimeout(250);
      assert((await editorBody(page)).includes("- [x] target task"), "a touch tap in reading mode should toggle");
      assert(!(await editorHasFocus(page)), "a touch tap on a checkbox must not focus the editor (no keyboard pop-up)");
      assert(JSON.stringify(await editorSelection(page)) === JSON.stringify(readingSelection), "reading-mode touch tap must not move the cursor");
      console.log("[e2e-listReveal] PASS: reading-mode touch tap toggles without focusing the editor or moving the cursor");

      await setDocAndSelection(page, NESTED_DOC, CARET_ELSEWHERE);
      await focusEditor(page);
      const nestedScrollBefore = await scrollTargetIntoView(page, NESTED_OFFSET);
      const nestedSelectionBefore = await editorSelection(page);
      const nestedTarget = page.locator(".cm-line", { hasText: "target task" }).locator(".cm-quki-checkbox");
      await touchTap(client, await stableBox(nestedTarget));
      await page.waitForTimeout(250);
      assert((await editorBody(page)) === NESTED_DOC.replace("\t- [ ] target task", "\t- [x] target task"), "a touch tap on an indented checkbox should check it");
      assert(JSON.stringify(await editorSelection(page)) === JSON.stringify(nestedSelectionBefore), "touch tap on an indented checkbox must not move the cursor");
      assert((await scrollTop(page)) === nestedScrollBefore, `touch tap on an indented checkbox must not scroll: ${nestedScrollBefore} -> ${await scrollTop(page)}`);
      assert(await editorHasFocus(page), "touch tap on an indented checkbox must not blur the editor");
      console.log("[e2e-listReveal] PASS: touch tap on an indented checkbox toggles it, preserving cursor, scroll and focus");

      await context.close();
    }

    // --- Opening an existing QuKi lands in reading mode with no focus
    // (BEHAVIOR_SPEC.md §4) - main.ts's loadDocumentIntoEditor always resets
    // the caret to { anchor: 0 } on load, even here, so a first-line element
    // must not read that default reset position as the user genuinely
    // editing there. ---
    {
      const context = await browser.newContext();
      const page = await openFreshPage(context, url);

      await blurEditor(page);
      await setDocAndSelection(page, "# test\n\nbody text", 0);
      await page.waitForTimeout(150);

      assert(!(await editorHasFocus(page)), "opening an existing QuKi must not focus the editor");
      const headingLine = await page.locator(".cm-line", { hasText: "test" }).first().textContent();
      assert(headingLine === "test", `a first-line heading opened straight into reading mode should show collapsed ("test"), not raw markdown, got ${JSON.stringify(headingLine)}`);
      assert((await page.locator(".cm-quki-heading-1").count()) === 1, "the heading should still carry its styled heading class");
      console.log("[e2e-listReveal] PASS: a first-line heading opened straight into reading mode shows collapsed, not raw");

      // Same root cause, not heading-specific: a first-line bold run must
      // also stay collapsed rather than revealing its ** marks.
      await setDocAndSelection(page, "**bold** rest\n\nbody text", 0);
      await page.waitForTimeout(150);
      const boldLine = await page.locator(".cm-line", { hasText: "bold" }).first().textContent();
      assert(boldLine === "bold rest", `a first-line bold run opened straight into reading mode should show collapsed ("bold rest"), not raw, got ${JSON.stringify(boldLine)}`);
      console.log("[e2e-listReveal] PASS: a first-line bold run opened straight into reading mode shows collapsed, not raw (bug is not heading-specific)");

      // Genuinely focusing at that same position must still reveal
      // normally - the fix must not break real in-editor reveal at 0.
      await focusEditor(page);
      await page.waitForTimeout(150);
      const focusedLine = await page.locator(".cm-line", { hasText: "bold" }).first().textContent();
      assert(focusedLine === "**bold** rest", `focusing with the caret genuinely at position 0 should reveal the marker, got ${JSON.stringify(focusedLine)}`);
      console.log("[e2e-listReveal] PASS: focusing at that same position still reveals normally");

      await context.close();
    }

    console.log("[e2e-listReveal] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-listReveal] FAILED:", err);
    process.exit(1);
  });
