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

type WindowWithQukiView = typeof window & {
  qukiView: {
    state: {
      doc: { toString(): string; length: number };
      selection: { main: { anchor: number; head: number } };
    };
    dispatch: (spec: unknown) => void;
    focus: () => void;
    contentDOM: HTMLElement;
    coordsAtPos: (pos: number, side?: -1 | 1) => { top: number; bottom: number; left: number; right: number } | null;
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

/**
 * Sets the editor's document and selection through a real dispatched
 * transaction on the live view (the same `window.qukiView` main.ts exposes
 * for debugging) - not the suppressed programmatic-load path
 * (`loadDocumentIntoEditor`'s `suppressAutoSaveNotify`), so this is a real
 * `EditorState.selection` the toolbar buttons' own adapter
 * (toolbarAdapter.ts's `readEditorValue`) will read, just set up by the
 * test rather than by a mouse drag.
 */
async function setDocAndSelection(page: Page, text: string, anchor: number, head = anchor): Promise<void> {
  await page.evaluate(
    ({ text, anchor, head }) => {
      const view = (window as WindowWithQukiView).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor, head } });
      view.focus();
    },
    { text, anchor, head },
  );
}

function toolbarButton(page: Page, label: string) {
  return page.locator(`.formatting-toolbar .toolbar-btn[aria-label="${label}"]`);
}

async function isToolbarVisible(page: Page): Promise<boolean> {
  return page.locator(".formatting-toolbar").isVisible();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-formattingToolbar] serving dist/ at ${url}`);

  const browser = await chromium.launch();
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    // --- A brand-new, blank QuKi takes focus (BEHAVIOR_SPEC.md §4's
    // shouldFocusOnOpen), so the toolbar should already be visible with no
    // interaction at all, and nothing has been saved yet. ---
    assert(await isToolbarVisible(page), "toolbar should be visible on a fresh, blank (unsaved) QuKi");
    assert((await page.getAttribute("#btn-delete", "disabled")) !== null, "Delete should be disabled before anything is saved");
    console.log("[e2e-formattingToolbar] PASS: toolbar shown on load for a blank new QuKi (edit mode)");

    // --- Bold on a collapsed (no) selection inserts the delimiter pair
    // with the caret placed between them, and — being a real dispatched
    // edit, not the suppressed load path — triggers auto-save. ---
    await page.click(".cm-content");
    await toolbarButton(page, "Bold").click();
    assert((await editorBody(page)) === "****", `expected "****" after Bold with no selection, got: "${await editorBody(page)}"`);
    const boldCollapsedSelection = await editorSelection(page);
    assert(
      boldCollapsedSelection.anchor === 2 && boldCollapsedSelection.head === 2,
      `expected caret between the delimiters (2,2), got: ${JSON.stringify(boldCollapsedSelection)}`,
    );
    console.log("[e2e-formattingToolbar] PASS: Bold with no selection inserted ** ** and placed the caret between them");

    await page.waitForTimeout(2500); // 2s debounce + margin
    assert((await page.getAttribute("#btn-delete", "disabled")) === null, "Delete should be enabled once the Bold press's edit has auto-saved");
    console.log("[e2e-formattingToolbar] PASS: a toolbar button press triggered a real (non-suppressed) auto-save");

    // --- Reloading loads the most-recently-modified QuKi, which — being a
    // real, already-saved QuKi rather than a blank one — does not take
    // focus (reading mode), so the toolbar should now be hidden. ---
    await page.reload();
    await page.waitForSelector(".cm-content");
    assert((await editorBody(page)) === "****", "the Bold edit should have persisted across reload (confirms the save was real, not suppressed)");
    assert(!(await isToolbarVisible(page)), "toolbar should be hidden on load for an existing (unfocused, reading-mode) QuKi");
    console.log("[e2e-formattingToolbar] PASS: toolbar hidden on load for an existing QuKi (reading mode)");

    // --- Toolbar visibility tracks editor focus/blur directly (editMode.ts's
    // tracker), not some separate listener. ---
    await page.click(".cm-content");
    assert(await isToolbarVisible(page), "toolbar should appear once the editor gains focus");
    console.log("[e2e-formattingToolbar] PASS: toolbar appears on focus");

    await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
    assert(!(await isToolbarVisible(page)), "toolbar should disappear once the editor loses focus");
    console.log("[e2e-formattingToolbar] PASS: toolbar disappears on blur");

    await page.click(".cm-content");
    assert(await isToolbarVisible(page), "toolbar should reappear once the editor regains focus");

    // --- Bold with a real, mouse-driven selection (double-click to select
    // a word) wraps the selection, rather than inserting an empty pair. ---
    await setDocAndSelection(page, "word", 0, 0);
    await page.locator(".cm-line", { hasText: "word" }).dblclick();
    const wordSelection = await editorSelection(page);
    assert(
      Math.abs(wordSelection.head - wordSelection.anchor) === 4,
      `expected the double-click to select the whole 4-character word, got: ${JSON.stringify(wordSelection)}`,
    );
    await toolbarButton(page, "Bold").click();
    assert((await editorBody(page)) === "**word**", `expected "**word**" after Bold on a real double-click word selection, got: "${await editorBody(page)}"`);
    console.log("[e2e-formattingToolbar] PASS: Bold wrapped a real mouse-driven word selection");

    // --- The remaining inline-format buttons, each with a real range
    // selection covering the whole word (set through the live view, same
    // as the toolbar's own adapter reads — not a mock). ---
    await setDocAndSelection(page, "word", 0, 4);
    await toolbarButton(page, "Italic").click();
    assert((await editorBody(page)) === "_word_", `expected "_word_" after Italic, got: "${await editorBody(page)}"`);
    console.log("[e2e-formattingToolbar] PASS: Italic wrapped the selection with _ _ (not * *)");

    await setDocAndSelection(page, "word", 0, 4);
    await toolbarButton(page, "Strikethrough").click();
    assert((await editorBody(page)) === "~~word~~", `expected "~~word~~" after Strikethrough, got: "${await editorBody(page)}"`);
    console.log("[e2e-formattingToolbar] PASS: Strikethrough wrapped the selection with ~~ ~~");

    await setDocAndSelection(page, "word", 0, 4);
    await toolbarButton(page, "Inline code").click();
    assert((await editorBody(page)) === "`word`", `expected the code-wrapped text, got: "${await editorBody(page)}"`);
    console.log("[e2e-formattingToolbar] PASS: Inline code wrapped the selection with backticks");

    // --- Heading cycles normal -> H1 -> H2 -> H3 -> normal, and the
    // button's icon changes to reflect the level (BEHAVIOR_SPEC.md: "The
    // icon tracks the current level"). The exact lucide icon isn't
    // asserted by name (it's an implementation detail of lucide's icon
    // set) - what's checked is that the rendered icon markup actually
    // changes between levels, proving the toolbar reacts to the caret's
    // line rather than showing one fixed icon. ---
    await setDocAndSelection(page, "Title", 0, 0);
    const headingIconAtNormal = await page.locator('.formatting-toolbar .toolbar-btn[aria-label="Heading"] svg').innerHTML();
    await toolbarButton(page, "Heading").click();
    assert((await editorBody(page)) === "# Title", `expected "# Title" after one Heading press, got: "${await editorBody(page)}"`);
    const headingIconAtH1 = await page.locator('.formatting-toolbar .toolbar-btn[aria-label="Heading"] svg').innerHTML();
    assert(headingIconAtH1 !== headingIconAtNormal, "the heading button's icon should change once the line becomes an H1");

    await toolbarButton(page, "Heading").click();
    assert((await editorBody(page)) === "## Title", `expected "## Title" after a second Heading press, got: "${await editorBody(page)}"`);
    const headingIconAtH2 = await page.locator('.formatting-toolbar .toolbar-btn[aria-label="Heading"] svg').innerHTML();
    assert(headingIconAtH2 !== headingIconAtH1, "the heading button's icon should change again for H2");
    console.log("[e2e-formattingToolbar] PASS: Heading cycles normal -> H1 -> H2 and its icon changes with the level");

    // --- List-toggle buttons convert in place (BEHAVIOR_SPEC.md "Toolbar
    // toggle semantics"): pressing again removes what was just added. ---
    await setDocAndSelection(page, "item", 0, 0);
    await toolbarButton(page, "Unordered list").click();
    assert((await editorBody(page)) === "- item", `expected "- item" after Unordered list, got: "${await editorBody(page)}"`);
    await toolbarButton(page, "Unordered list").click();
    assert((await editorBody(page)) === "item", `expected the marker removed on a second press, got: "${await editorBody(page)}"`);
    console.log("[e2e-formattingToolbar] PASS: Unordered list adds then removes its own marker");

    await setDocAndSelection(page, "item", 0, 0);
    await toolbarButton(page, "Ordered list").click();
    assert((await editorBody(page)) === "1. item", `expected "1. item" after Ordered list, got: "${await editorBody(page)}"`);
    console.log("[e2e-formattingToolbar] PASS: Ordered list added a numbered marker");

    await setDocAndSelection(page, "item", 0, 0);
    await toolbarButton(page, "Task list").click();
    assert((await editorBody(page)) === "- [ ] item", `expected a task marker, got: "${await editorBody(page)}"`);
    console.log("[e2e-formattingToolbar] PASS: Task list added a checkbox marker");

    // --- Indent / Dedent buttons act on the whole line and round-trip. ---
    await setDocAndSelection(page, "- item", 0, 0);
    await toolbarButton(page, "Indent").click();
    assert((await editorBody(page)) === "\t- item", `expected a leading tab before the marker, got: ${JSON.stringify(await editorBody(page))}`);
    await toolbarButton(page, "Dedent").click();
    assert((await editorBody(page)) === "- item", `expected Dedent to round-trip Indent exactly, got: ${JSON.stringify(await editorBody(page))}`);
    console.log("[e2e-formattingToolbar] PASS: Indent and Dedent buttons round-trip a list line");

    // --- Tab / Shift-Tab remain bound in the editor's own keymap, running
    // the identical indent/dedent commands the buttons use. ---
    await setDocAndSelection(page, "paragraph", 0, 0);
    await page.click(".cm-content");
    await page.keyboard.press("Tab");
    assert((await editorBody(page)) === "\tparagraph", `expected Tab to insert a leading tab, got: ${JSON.stringify(await editorBody(page))}`);
    await page.keyboard.press("Shift+Tab");
    assert((await editorBody(page)) === "paragraph", `expected Shift-Tab to remove it again, got: ${JSON.stringify(await editorBody(page))}`);
    console.log("[e2e-formattingToolbar] PASS: Tab and Shift-Tab still indent/dedent in the editor");

    // --- A caret that was visible while reading (toolbar hidden) must not
    // end up hidden behind the toolbar once it appears. The toolbar is
    // plain DOM outside CodeMirror, so becoming visible is not a
    // transaction - main.ts explicitly re-checks the caret against the
    // editor's scrollMargins facet when edit mode is entered, since nothing
    // else would trigger that recheck. This must target an ordinary line,
    // not the QuKi's actual last line: .cm-content's own bottom padding
    // (main.ts's EditorView.theme) permanently reserves space for the
    // toolbar there regardless of whether it's shown, so the true last line
    // is already safe by construction and would pass even without the fix.
    // Scrolling only partway down and tapping whatever line currently sits
    // at the bottom of the visible viewport (with plenty of the document
    // still unscrolled below it) is the realistic "tap the last line I can
    // currently see while reading" gesture, and has no such protection. ---
    await page.setViewportSize({ width: 400, height: 500 });
    const manyLines = Array.from({ length: 80 }, (_, i) => `line ${i + 1}`).join("\n");
    await setDocAndSelection(page, manyLines, 0, 0); // dispatch also focuses (edit mode)
    await page.evaluate(() => (window as WindowWithQukiView).qukiView.contentDOM.blur());
    assert(!(await isToolbarVisible(page)), "toolbar should be hidden after blur, before the scroll-margin scenario");

    await page.evaluate(() => {
      const scroller = (window as WindowWithQukiView).qukiView.contentDOM.closest(".cm-scroller") as HTMLElement;
      scroller.scrollTop = scroller.scrollHeight / 2;
    });

    const targetLine = await page.evaluate(() => {
      const scroller = (window as WindowWithQukiView).qukiView.contentDOM.closest(".cm-scroller") as HTMLElement;
      const scrollerBottom = scroller.getBoundingClientRect().bottom;
      let best: { top: number; bottom: number; left: number } | null = null;
      for (const line of Array.from(document.querySelectorAll(".cm-line"))) {
        const box = line.getBoundingClientRect();
        if (box.bottom <= scrollerBottom && (best === null || box.bottom > best.bottom)) {
          best = { top: box.top, bottom: box.bottom, left: box.left };
        }
      }
      return best;
    });
    assert(targetLine !== null, "should find a line sitting at the bottom of the current scroll position");

    // A real click, not a dispatched selection - the same gesture a user
    // would use to place the caret while reading. page.mouse.click (not a
    // locator click) so Playwright can't "helpfully" scroll the target into
    // view first - it's already visible, which is the whole point.
    await page.mouse.click(targetLine!.left + 5, (targetLine!.top + targetLine!.bottom) / 2);
    assert(await isToolbarVisible(page), "toolbar should appear once the tap focuses the editor");

    // The fix's own corrective scroll is deliberately deferred a tick past
    // the click (see main.ts's comment on this), so give it a moment to run
    // and repaint before checking.
    await page.waitForTimeout(100);

    const clearance = await page.evaluate(() => {
      const view = (window as WindowWithQukiView).qukiView;
      const coords = view.coordsAtPos(view.state.selection.main.head);
      const toolbarTop = document.querySelector(".formatting-toolbar")!.getBoundingClientRect().top;
      return coords === null ? null : toolbarTop - coords.bottom;
    });
    assert(clearance !== null, "coordsAtPos should resolve a visible caret position");
    assert(clearance! >= 0, `caret should be scrolled clear of the toolbar (gap between caret bottom and toolbar top), got ${clearance}`);
    console.log("[e2e-formattingToolbar] PASS: a caret revealed by the toolbar on focus is scrolled clear of it, not hidden behind it");

    console.log("[e2e-formattingToolbar] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-formattingToolbar] FAILED:", err);
    process.exit(1);
  });
