import * as fs from "node:fs";
import * as path from "node:path";

import { chromium, type Browser, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

type Scheme = "light" | "dark";

const BUTTONS = ["Bold", "Italic", "Strikethrough", "Inline code", "Heading", "Unordered list", "Ordered list", "Task list"] as const;
type Label = (typeof BUTTONS)[number];

// Set to a folder to also save a screenshot of each scenario's last step.
const SHOT_DIR = process.env["QUKI_E2E_SHOT_DIR"];

function button(page: Page, label: string) {
  return page.locator(`.formatting-toolbar .toolbar-btn[aria-label="${label}"]`);
}

async function pressed(page: Page): Promise<Label[]> {
  const out: Label[] = [];
  for (const label of BUTTONS) {
    const value = await button(page, label).getAttribute("aria-pressed");
    assert(value === "true" || value === "false", `"${label}" must expose aria-pressed true/false, got ${String(value)}`);
    if (value === "true") out.push(label);
  }
  return out;
}

async function expectPressed(page: Page, tag: string, what: string, expected: Label[]): Promise<void> {
  const actual = await pressed(page);
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${tag} ${what}: expected pressed ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
  );
  console.log(`${tag} PASS: ${what} -> ${expected.length === 0 ? "nothing pressed" : expected.join(", ")}`);
}

async function body(page: Page): Promise<string> {
  return page.evaluate(() => (window as unknown as { qukiView: { state: { doc: { toString(): string } } } }).qukiView.state.doc.toString());
}

async function replaceAllWith(page: Page, text: string): Promise<void> {
  await page.keyboard.press("Control+A");
  await page.keyboard.press("Delete");
  await page.keyboard.type(text);
}

async function runScenario(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-toolbarActiveFormat:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 800 } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await clickFirstLine(page);

  await expectPressed(page, tag, "an empty QuKi", []);

  // Inline formats follow the caret.
  await page.keyboard.type("plain **bold _both_** end");
  await expectPressed(page, tag, "caret after the last word, outside any span", []);
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await expectPressed(page, tag, "caret just after the closing **", []);
  await page.keyboard.press("ArrowLeft");
  await expectPressed(page, tag, "caret between the closing markers", []);
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await expectPressed(page, tag, "caret inside bold-and-italic text", ["Bold", "Italic"]);
  for (let i = 0; i < 6; i++) await page.keyboard.press("ArrowLeft");
  await expectPressed(page, tag, "caret inside bold text, before the italic span", ["Bold"]);
  await page.keyboard.press("Home");
  await expectPressed(page, tag, "caret at the start of the line", []);

  // The state follows edits too, not only caret moves.
  await page.keyboard.press("End");
  await page.keyboard.type(" `x");
  await expectPressed(page, tag, "typing an unclosed backtick", []);
  await page.keyboard.type("`");
  await expectPressed(page, tag, "closing the backtick (caret after the code span)", []);
  await page.keyboard.press("ArrowLeft");
  await expectPressed(page, tag, "caret just inside the closing backtick", ["Inline code"]);

  // Line formats.
  await replaceAllWith(page, "- item");
  await expectPressed(page, tag, "a bullet line", ["Unordered list"]);
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");
  await page.keyboard.type("1. one");
  await expectPressed(page, tag, "an ordered line", ["Ordered list"]);
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");
  await page.keyboard.type("- [ ] todo");
  await expectPressed(page, tag, "a task line", ["Task list"]);
  await page.keyboard.press("Enter");
  await page.keyboard.press("Enter");
  await page.keyboard.type("# Title with ~~gone~~");
  await expectPressed(page, tag, "a heading line", ["Heading"]);
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await expectPressed(page, tag, "strikethrough inside a heading", ["Strikethrough", "Heading"]);
  await page.keyboard.press("ArrowUp");
  await expectPressed(page, tag, "moving up onto the task line", ["Task list"]);

  // Pressed look: distinct from unpressed in both schemes.
  const look = await page.evaluate(() => {
    const style = (label: string) => {
      const el = document.querySelector<HTMLElement>(`.toolbar-btn[aria-label="${label}"]`)!;
      const s = getComputedStyle(el);
      return { colour: s.color, background: s.backgroundColor, shadow: s.boxShadow };
    };
    return { on: style("Task list"), off: style("Bold") };
  });
  assert(look.on.colour !== look.off.colour && look.on.background !== look.off.background, `${tag} the pressed look must differ from the unpressed one: ${JSON.stringify(look)}`);
  assert(look.on.shadow !== "none" && look.off.shadow === "none", `${tag} the pressed button carries an underline, others do not: ${JSON.stringify(look)}`);
  console.log(`${tag} PASS: pressed look differs (${look.on.colour} on ${look.on.background} vs ${look.off.colour})`);

  // Tapping a button still formats, keeps focus in the editor, and the new state shows.
  await replaceAllWith(page, "word");
  await button(page, "Bold").click();
  assert((await body(page)) === "word****", `${tag} Bold with no selection must insert the pair, got "${await body(page)}"`);
  assert(await page.evaluate(() => document.activeElement?.classList.contains("cm-content") ?? false), `${tag} a toolbar tap must leave the editor focused`);
  await expectPressed(page, tag, "after tapping Bold with no selection (caret between the new markers)", ["Bold"]);
  await page.keyboard.type("hi");
  assert((await body(page)) === "word**hi**", `${tag} typing after Bold must land inside the markers, got "${await body(page)}"`);
  await button(page, "Unordered list").click();
  assert((await body(page)) === "- word**hi**", `${tag} the list button must still prefix the line, got "${await body(page)}"`);
  await expectPressed(page, tag, "after tapping the list button", ["Bold", "Unordered list"]);
  await button(page, "Unordered list").click();
  assert((await body(page)) === "word**hi**", `${tag} tapping the pressed list button must remove the marker, got "${await body(page)}"`);
  await expectPressed(page, tag, "after tapping the list button off again", ["Bold"]);

  // Plain-text mode keeps the buttons working on the same text, so the state still follows the markdown.
  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await page.waitForTimeout(250);
  await replaceAllWith(page, "- a **b**");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await page.keyboard.press("ArrowLeft");
  await expectPressed(page, tag, "plain-text mode, caret inside bold on a bullet line", ["Bold", "Unordered list"]);

  if (SHOT_DIR) {
    fs.mkdirSync(SHOT_DIR, { recursive: true });
    await page.screenshot({ path: path.join(SHOT_DIR, `toolbar-active-${scheme}.png`) });
    await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
    await page.waitForTimeout(250);
    await replaceAllWith(page, "# Heading with **bold _and italic_** text\n- [ ] a task");
    await page.keyboard.press("ArrowUp");
    await page.keyboard.press("End");
    for (let i = 0; i < 9; i++) await page.keyboard.press("ArrowLeft");
    await page.screenshot({ path: path.join(SHOT_DIR, `toolbar-active-${scheme}-nested.png`) });
  }

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-toolbarActiveFormat] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) await runScenario(browser, url, scheme);
    console.log("[e2e-toolbarActiveFormat] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-toolbarActiveFormat] FAILED:", err);
    process.exit(1);
  });
