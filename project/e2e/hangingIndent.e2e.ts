import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type BrowserContext, type Page } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.join(__dirname, "..", "dist");
const shotsDir = process.env.QUKI_E2E_SHOTS;

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

function near(a: number, b: number, tolerance = 0.5): boolean {
  return Math.abs(a - b) <= tolerance;
}

type WindowWithQukiView = typeof window & {
  qukiView: {
    state: { doc: { toString(): string; length: number } };
    dispatch: (spec: unknown) => void;
    focus: () => void;
  };
};

async function setDocAndSelection(page: Page, text: string, anchor: number, head = anchor): Promise<void> {
  await page.evaluate(
    ({ text, anchor, head }) => {
      const view = (window as WindowWithQukiView).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor, head } });
    },
    { text, anchor, head },
  );
  await settle(page);
}

async function setSelection(page: Page, anchor: number): Promise<void> {
  await page.evaluate((anchor) => {
    (window as WindowWithQukiView).qukiView.dispatch({ selection: { anchor } });
  }, anchor);
  await settle(page);
}

async function focusEditor(page: Page): Promise<void> {
  await page.evaluate(() => (window as WindowWithQukiView).qukiView.focus());
}

async function settle(page: Page): Promise<void> {
  await page.waitForTimeout(200);
}

async function lineText(page: Page, needle: string): Promise<string> {
  return page.evaluate(
    (needle) => [...document.querySelectorAll(".cm-line")].find((l) => l.textContent?.includes(needle))?.textContent ?? "",
    needle,
  );
}

async function toggleMode(page: Page): Promise<void> {
  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await settle(page);
}

async function openFreshPage(context: BrowserContext, url: string): Promise<Page> {
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  return page;
}

interface Row {
  top: number;
  left: number;
}

interface HangGeometry {
  /** Visual rows top to bottom, each with the left edge of its leftmost non-blank character. */
  rows: Row[];
  /** Left edge of the character at `prefixLength`, the first character of the item's text. */
  textStartLeft: number;
  /** Left edge of every character of the prefix, in order. */
  prefixLefts: number[];
  /** Left edge of the line's content box (where a row starting at the margin would begin). */
  contentLeft: number;
  hangClass: boolean;
  markerWidgets: number;
}

/**
 * Measures the rendered line containing `needle` character by character.
 * `prefixLength` is how many source characters precede the item's text.
 */
async function hangGeometry(page: Page, needle: string, prefixLengthOrAuto: number | "auto"): Promise<HangGeometry> {
  return page.evaluate(
    ({ needle, prefixLengthOrAuto }) => {
      const line = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent?.includes(needle));
      if (!line) throw new Error("no line containing " + needle);
      const prefixLength =
        prefixLengthOrAuto === "auto"
          ? (/^[ 	]*(?:-(?: \[[ xX]\])? |[*+] |\d+\. )/.exec(line.textContent ?? "")?.[0].length ?? 0)
          : prefixLengthOrAuto;
      const rowLeft = new Map<number, number>();
      const prefixLefts: number[] = [];
      let textStartLeft = Number.NaN;
      let index = 0;
      const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const text = node.textContent ?? "";
        if (node.parentElement?.closest(".cm-quki-marker")) continue;
        for (let i = 0; i < text.length; i++, index++) {
          const range = document.createRange();
          range.setStart(node, i);
          range.setEnd(node, i + 1);
          const rect = range.getBoundingClientRect();
          if (index < prefixLength) prefixLefts.push(rect.left);
          if (index === prefixLength) textStartLeft = rect.left;
          if (text[i] === " " || text[i] === "\t" || rect.width === 0) continue;
          const top = Math.round(rect.top);
          const known = rowLeft.get(top);
          if (known === undefined || rect.left < known) rowLeft.set(top, rect.left);
        }
      }
      const style = getComputedStyle(line);
      return {
        rows: [...rowLeft.entries()].sort((a, b) => a[0] - b[0]).map(([top, left]) => ({ top, left })),
        textStartLeft,
        prefixLefts,
        contentLeft: line.getBoundingClientRect().left + Number.parseFloat(style.paddingLeft),
        hangClass: line.classList.contains("cm-quki-hang"),
        markerWidgets: line.querySelectorAll(".cm-quki-marker").length,
      };
    },
    { needle, prefixLengthOrAuto },
  );
}

const WRAP = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua";

// Scott's screenshot: the deeply indented line is not a list item to the
// parser, so it stays raw; the two collapsed bullets follow it.
const SCREENSHOT_LINE = "        - jdjd djdid rhe rndjdu ejwu heyie jehehe dhejeb dhej";
const SCREENSHOT_DOC = `- blah\n${SCREENSHOT_LINE}\n- jdjd\n- `;

async function shot(page: Page, name: string): Promise<void> {
  if (!shotsDir) return;
  fs.mkdirSync(shotsDir, { recursive: true });
  await page.screenshot({ path: path.join(shotsDir, `${name}.png`), clip: { x: 0, y: 0, width: 400, height: 420 } });
}

/**
 * The raw line must (a) wrap, (b) start every wrapped row under its first
 * text character, (c) leave its first row exactly where plain-text mode
 * (undecorated source) puts it.
 */
async function assertHangs(page: Page, label: string, needle: string, prefixLength: number | "auto"): Promise<HangGeometry> {
  const hung = await hangGeometry(page, needle, prefixLength);
  assert(hung.hangClass, `${label}: the raw line should be marked to hang`);
  assert(hung.markerWidgets === 0, `${label}: a raw line has no marker widget`);
  assert(hung.rows.length >= 2, `${label}: the line should wrap at this width, got ${hung.rows.length} row(s)`);
  for (const row of hung.rows.slice(1)) {
    assert(near(row.left, hung.textStartLeft), `${label}: a wrapped row starts at ${row.left}, not under the text at ${hung.textStartLeft}`);
  }
  assert(hung.textStartLeft > hung.contentLeft + 1, `${label}: the text start (${hung.textStartLeft}) should be right of the margin (${hung.contentLeft})`);

  await toggleMode(page);
  const raw = await hangGeometry(page, needle, prefixLength);
  await toggleMode(page);
  assert(!raw.hangClass, `${label}: plain-text mode adds no hang mark`);
  assert(near(raw.rows[1]?.left ?? Number.NaN, raw.contentLeft), `${label}: plain-text mode leaves its wrapped rows at the margin`);
  assert(raw.prefixLefts.length === hung.prefixLefts.length, `${label}: prefix length mismatch`);
  hung.prefixLefts.forEach((left, i) => {
    assert(near(left, raw.prefixLefts[i]!), `${label}: prefix character ${i} moved from ${raw.prefixLefts[i]} to ${left}`);
  });
  assert(near(hung.textStartLeft, raw.textStartLeft), `${label}: the text start moved from ${raw.textStartLeft} to ${hung.textStartLeft}`);
  return hung;
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-hangingIndent] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) {
      const context = await browser.newContext({ viewport: { width: 400, height: 900 }, colorScheme: scheme });
      const page = await openFreshPage(context, url);
      await setDocAndSelection(page, SCREENSHOT_DOC, SCREENSHOT_DOC.length);
      await assertHangs(page, `screenshot document (${scheme})`, "jdjd djdid", 10);
      await shot(page, `screenshot-doc-${scheme}`);
      await context.close();
    }
    console.log("[e2e-hangingIndent] PASS: the screenshot document's unrecognised deep line hangs its wrapped rows under the text, in light and dark");

    const context = await browser.newContext({ viewport: { width: 400, height: 900 } });
    const page = await openFreshPage(context, url);

    const doc = [
      "plain reference paragraph",
      "",
      `- alpha ${WRAP}`,
      `\t- bravo ${WRAP}`,
      "",
      `1. delta ${WRAP}`,
      ...Array.from({ length: 9 }, (_, i) => `1. filler${i}`),
      `10. foxtrot ${WRAP}`,
      "",
      `- [ ] golf ${WRAP}`,
      `\t- [x] hotel ${WRAP}`,
      "",
      `* star ${WRAP}`,
      `+ plus ${WRAP}`,
      "",
      "trailing plain paragraph",
    ].join("\n");
    const at = (text: string): number => doc.indexOf(text);

    const revealed: [string, string, number, number][] = [
      ["top-level bullet", "alpha", at("- alpha") + 1, 2],
      ["nested bullet with a tab", "bravo", at("\t- bravo") + 2, 3],
      ["ordered item", "delta", at("1. delta") + 1, 3],
      ["two-digit ordered item", "foxtrot", at("10. foxtrot") + 1, 4],
      ["task", "golf", at("- [ ] golf") + 1, 6],
      ["nested checked task with a tab", "hotel", at("\t- [x] hotel") + 3, 7],
      ["star bullet", "star", at("* star") + 1, 2],
      ["plus bullet", "plus", at("+ plus") + 1, 2],
    ];
    for (const [label, needle, caret, prefixLength] of revealed) {
      await setDocAndSelection(page, doc, caret);
      await assertHangs(page, `revealed ${label}`, needle, prefixLength);
    }
    console.log("[e2e-hangingIndent] PASS: a revealed item (bullet, nested, ordered, two-digit, task, nested task) hangs under its text and its first row does not move");

    await setDocAndSelection(page, doc, doc.length);
    for (const needle of ["alpha", "bravo", "delta", "foxtrot", "golf", "hotel", "star", "plus"]) {
      const g = await hangGeometry(page, needle, 0);
      assert(!g.hangClass && g.markerWidgets === 1, `collapsed ${needle}: keeps its marker widget and is not marked to hang`);
      for (const row of g.rows.slice(1)) {
        assert(near(row.left, g.rows[0]!.left), `collapsed ${needle}: wrapped rows still hang under the content`);
      }
    }
    console.log("[e2e-hangingIndent] PASS: collapsed items keep their own hang and are not also marked");

    // Tab characters anywhere in the leading whitespace, on a line the parser leaves raw.
    const tabDoc = `- top\n\t\t\t- tabbed ${WRAP}\n  \t  - mixed ${WRAP}\n`;
    await setDocAndSelection(page, tabDoc, tabDoc.length);
    await assertHangs(page, "line indented with tabs", "tabbed", 5);
    await assertHangs(page, "line indented with spaces and a tab", "mixed", 7);
    console.log("[e2e-hangingIndent] PASS: tabs in the leading whitespace do not disturb the first row or the wrapped rows");

    // Typing and caret movement.
    await setDocAndSelection(page, SCREENSHOT_DOC, SCREENSHOT_DOC.lastIndexOf("dhej") + 4);
    await focusEditor(page);
    await page.keyboard.type(" and more words that keep going and going");
    await settle(page);
    assert((await lineText(page, "jdjd djdid")).endsWith("dhej and more words that keep going and going"), "the typed text should be in the line, got " + JSON.stringify(await lineText(page, "jdjd djdid")));
    await assertHangs(page, "after typing into the deep line", "jdjd djdid", 10);
    await setSelection(page, SCREENSHOT_DOC.indexOf("- jdjd djdid"));
    await page.keyboard.press("Backspace");
    await settle(page);
    await page.keyboard.press("Backspace");
    await settle(page);
    const shortened = await lineText(page, "jdjd djdid");
    assert(/^ *- jdjd/.test(shortened) && shortened.indexOf("-") < 8, `Backspace should have removed leading whitespace, got ${JSON.stringify(shortened.slice(0, 12))}`);
    await assertHangs(page, "after deleting leading whitespace", "jdjd djdid", "auto");
    await page.keyboard.type("  ");
    await settle(page);
    await assertHangs(page, "after re-typing leading whitespace", "jdjd djdid", "auto");
    console.log("[e2e-hangingIndent] PASS: typing and deleting keep every wrapped row under the text");

    await setDocAndSelection(page, doc, at("- alpha") + 10);
    await focusEditor(page);
    const collapsedFirst = await hangGeometry(page, "alpha", 0);
    assert(!collapsedFirst.hangClass, "caret in the item's text leaves it collapsed");
    await page.keyboard.press("Home");
    await settle(page);
    await assertHangs(page, "caret moved into the marker with Home", "alpha", 2);
    await page.keyboard.press("End");
    await settle(page);
    const collapsedAgain = await hangGeometry(page, "alpha", 0);
    assert(!collapsedAgain.hangClass && collapsedAgain.markerWidgets === 1, "End collapses the item again");
    assert(near(collapsedAgain.rows[0]!.left, collapsedFirst.rows[0]!.left) && collapsedAgain.rows.length === collapsedFirst.rows.length, "the collapsed layout returns exactly as it was");
    console.log("[e2e-hangingIndent] PASS: moving the caret into and out of a marker switches between the raw hang and the collapsed layout");

    // Resize and rotation.
    await setDocAndSelection(page, SCREENSHOT_DOC, SCREENSHOT_DOC.length);
    let wrappedWidths = 0;
    for (const [width, height] of [[320, 700], [700, 400], [400, 900], [900, 500]] as const) {
      await page.setViewportSize({ width, height });
      await settle(page);
      const g = await hangGeometry(page, "jdjd djdid", 10);
      if (g.rows.length < 2) continue;
      wrappedWidths += 1;
      for (const row of g.rows.slice(1)) {
        assert(near(row.left, g.textStartLeft), `at ${width}x${height} a wrapped row starts at ${row.left}, not at ${g.textStartLeft}`);
      }
    }
    assert(wrappedWidths >= 2, `the line should wrap at two or more of the tested sizes, wrapped at ${wrappedWidths}`);
    await page.setViewportSize({ width: 400, height: 900 });
    await settle(page);
    console.log("[e2e-hangingIndent] PASS: the hang follows window resize and rotation");

    // Any font, not just the default one.
    const fonts = [
      "monospace",
      "Georgia, 'Times New Roman', serif",
      "'Comic Sans MS', 'Trebuchet MS', sans-serif",
    ];
    const seenTextStarts = new Set<number>();
    for (const family of fonts) {
      await page.addStyleTag({ content: `.cm-content { font-family: ${family} !important; font-size: 19px !important; }` });
      await settle(page);
      await setDocAndSelection(page, SCREENSHOT_DOC, SCREENSHOT_DOC.length);
      const inFont = await assertHangs(page, `font ${family}`, "jdjd djdid", 10);
      seenTextStarts.add(Math.round(inFont.textStartLeft));
      await setDocAndSelection(page, tabDoc, tabDoc.length);
      await assertHangs(page, `font ${family} with tabs`, "tabbed", 5);
      await setDocAndSelection(page, doc, at("- alpha") + 1);
      await assertHangs(page, `font ${family} revealed item`, "alpha", 2);
    }
    assert(seenTextStarts.size >= 2, `the fonts should place the text start at different offsets, got ${[...seenTextStarts]}`);
    console.log("[e2e-hangingIndent] PASS: monospace, serif and proportional fonts all align exactly");

    await context.close();
    console.log("[e2e-hangingIndent] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-hangingIndent] FAILED:", err);
    process.exit(1);
  });
