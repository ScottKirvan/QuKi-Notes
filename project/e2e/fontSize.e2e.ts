import { chromium, type Page } from "playwright";

import { serveDist } from "./serveDist.ts";
import { WRAP, assert, assertHangs, focusEditor, hangGeometry, near, setDocAndSelection } from "./hangSupport.ts";

const TAG = "[e2e-fontSize]";

const DOC = `# Big heading\n\nplain words\n\n- ${WRAP}\n\t- nested ${WRAP}\n\n> quoted\n\nend`;

interface Sizes {
  editor: number;
  heading: number;
  caretClearance: number;
  lineHeight: number;
  listPadding: number;
  nestedPadding: number;
  markerWidth: number;
  quotePadding: number;
}

async function sizes(page: Page): Promise<Sizes> {
  return page.evaluate(() => {
    const lineWith = (needle: string): HTMLElement => {
      const line = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent?.includes(needle));
      if (!line) throw new Error(`no line containing ${needle}`);
      return line;
    };
    const px = (value: string): number => Number.parseFloat(value);
    const editor = document.querySelector<HTMLElement>(".cm-editor")!;
    const content = document.querySelector<HTMLElement>(".cm-content")!;
    const scroller = document.querySelector<HTMLElement>(".cm-scroller")!;
    return {
      editor: px(getComputedStyle(editor).fontSize),
      heading: px(getComputedStyle(document.querySelector(".cm-quki-heading-1")!).fontSize),
      caretClearance: px(scroller.style.getPropertyValue("--quki-caret-clearance")),
      lineHeight: px(getComputedStyle(content).lineHeight),
      listPadding: px(getComputedStyle(lineWith("lorem")).paddingLeft),
      nestedPadding: px(getComputedStyle(lineWith("nested")).paddingLeft),
      markerWidth: lineWith("lorem").querySelector<HTMLElement>(".cm-quki-marker")!.getBoundingClientRect().width,
      quotePadding: px(getComputedStyle(lineWith("quoted")).paddingLeft),
    };
  });
}

function assertScaledTo(s: Sizes, size: number, label: string): void {
  assert(s.editor === size, `${label}: editor text should be ${size}px, got ${s.editor}`);
  assert(near(s.heading, size * 1.6), `${label}: a level-1 heading should be 1.6x the text, got ${s.heading}`);
  assert(near(s.lineHeight, size * 1.4), `${label}: line height should be 1.4x the text, got ${s.lineHeight}`);
  assert(near(s.caretClearance, 2 * s.lineHeight, 1), `${label}: caret clearance should be two lines (${2 * s.lineHeight}), got ${s.caretClearance}`);
  assert(near(s.listPadding, 6 + 1.5 * size), `${label}: a top-level item's content should start 6px + 1.5em in, got ${s.listPadding}`);
  assert(near(s.nestedPadding, 6 + 2.5 * size), `${label}: a nested item's content should start 6px + 2.5em in, got ${s.nestedPadding}`);
  assert(near(s.markerWidth, 1.5 * size), `${label}: the marker gutter should be 1.5em, got ${s.markerWidth}`);
  assert(near(s.quotePadding, size), `${label}: a quote should be indented 1em, got ${s.quotePadding}`);
}

async function assertCollapsedItemWrapsUnderItsText(page: Page, label: string): Promise<void> {
  const g = await hangGeometry(page, "lorem", 0);
  assert(g.rows.length >= 2, `${label}: the item should wrap, got ${g.rows.length} row(s)`);
  for (const row of g.rows.slice(1)) {
    assert(near(row.left, g.rows[0]!.left), `${label}: a wrapped row starts at ${row.left}, not under the item's text at ${g.rows[0]!.left}`);
  }
}

async function chooseSize(page: Page, value: string): Promise<void> {
  await page.click("#btn-settings");
  await page.waitForSelector("#view-settings .font-size-select", { state: "visible" });
  await page.selectOption("#view-settings .font-size-select", value);
  await page.click("#view-settings .back-btn");
  await page.waitForTimeout(400);
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({ viewport: { width: 420, height: 800 } });
    const page = await context.newPage();
    const pageErrors: string[] = [];
    page.on("pageerror", (err) => pageErrors.push(String(err)));
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    await setDocAndSelection(page, DOC, DOC.length);
    assertScaledTo(await sizes(page), 16, "default");
    console.log(`${TAG} PASS: Normal is 16px and the editor's layout matches it`);

    await page.click("#btn-settings");
    const selected = await page.inputValue("#view-settings .font-size-select");
    assert(selected === "normal", `Settings should show Normal by default, got ${selected}`);
    const labels = await page.$$eval("#view-settings .font-size-select option", (options) => options.map((o) => o.textContent));
    assert(JSON.stringify(labels) === JSON.stringify(["Small", "Normal", "Large", "Extra large"]), `steps: ${JSON.stringify(labels)}`);
    await page.click("#view-settings .back-btn");
    await page.waitForTimeout(400);

    await chooseSize(page, "extra-large");
    await setDocAndSelection(page, DOC, DOC.length);
    assertScaledTo(await sizes(page), 22, "extra large");
    await assertCollapsedItemWrapsUnderItsText(page, "extra large");
    console.log(`${TAG} PASS: Extra large applies straight away and headings, lists, quotes and caret clearance scale with it`);

    const revealAt = DOC.indexOf("- lorem") + 1;
    await focusEditor(page);
    await setDocAndSelection(page, DOC, revealAt);
    await assertHangs(page, "extra large, revealed item", "lorem", "auto");
    console.log(`${TAG} PASS: a revealed item's wrapped rows hang under its text at Extra large`);

    await page.reload();
    await page.waitForSelector(".cm-content");
    await setDocAndSelection(page, DOC, DOC.length);
    assertScaledTo(await sizes(page), 22, "after reload");
    console.log(`${TAG} PASS: the chosen size persists across a reload`);

    await chooseSize(page, "small");
    await setDocAndSelection(page, DOC, DOC.length);
    assertScaledTo(await sizes(page), 14, "small");
    await assertCollapsedItemWrapsUnderItsText(page, "small");
    console.log(`${TAG} PASS: Small applies and the layout scales down with it`);

    assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
    await context.close();
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
