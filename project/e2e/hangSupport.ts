import * as fs from "node:fs";
import * as path from "node:path";

import type { Page } from "playwright";

const shotsDir = process.env.QUKI_E2E_SHOTS;

export interface HangSession {
  page: Page;
  resize(width: number, height: number): Promise<void>;
  close(): Promise<void>;
}

export interface HangEnvironment {
  name: string;
  open(scheme: "light" | "dark", width: number, height: number): Promise<HangSession>;
  /** Throws unless the engine under test is the one this environment claims to be. Returns a description for the log. */
  assertEngine(page: Page): Promise<string>;
}

export function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
}

export function near(a: number, b: number, tolerance = 0.5): boolean {
  return Math.abs(a - b) <= tolerance;
}

type WindowWithQukiView = typeof window & {
  qukiView: {
    state: { doc: { toString(): string; length: number } };
    dispatch: (spec: unknown) => void;
    focus: () => void;
  };
};

export async function settle(page: Page): Promise<void> {
  await page.waitForTimeout(200);
}

export async function setDocAndSelection(page: Page, text: string, anchor: number, head = anchor): Promise<void> {
  await page.evaluate(
    ({ text, anchor, head }) => {
      const view = (window as WindowWithQukiView).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor, head } });
    },
    { text, anchor, head },
  );
  await settle(page);
}

export async function setSelection(page: Page, anchor: number): Promise<void> {
  await page.evaluate((anchor) => {
    (window as WindowWithQukiView).qukiView.dispatch({ selection: { anchor } });
  }, anchor);
  await settle(page);
}

export async function focusEditor(page: Page): Promise<void> {
  await page.evaluate(() => (window as WindowWithQukiView).qukiView.focus());
}

export async function lineText(page: Page, needle: string): Promise<string> {
  return page.evaluate(
    (needle) => [...document.querySelectorAll(".cm-line")].find((l) => l.textContent?.includes(needle))?.textContent ?? "",
    needle,
  );
}

export async function toggleMode(page: Page): Promise<void> {
  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await settle(page);
}

interface Row {
  top: number;
  left: number;
}

export interface HangGeometry {
  /** Visual rows top to bottom, each with the left edge of its leftmost non-blank character. */
  rows: Row[];
  /** Left edge of the character at `prefixLength`, the first character of the item's text. */
  textStartLeft: number;
  /** Left edge of every character of the prefix, in order. */
  prefixLefts: number[];
  /** Left edge and top of every character of the line, in order. */
  charLefts: number[];
  charTops: number[];
  /** Left edge of the line's content box (where a row starting at the margin would begin). */
  contentLeft: number;
  hangClass: boolean;
  markerWidgets: number;
  /** The line's own height, and how far down the hang float reaches (0 when it has none). */
  lineHeight: number;
  floatBottom: number;
  /** Right edge of the line's content box and of its rightmost character. */
  contentRight: number;
  textRight: number;
}

/**
 * Measures the rendered line containing `needle` character by character.
 * `prefixLength` is how many source characters precede the item's text.
 */
export async function hangGeometry(page: Page, needle: string, prefixLengthOrAuto: number | "auto"): Promise<HangGeometry> {
  return page.evaluate(
    ({ needle, prefixLengthOrAuto }) => {
      const line = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent?.includes(needle));
      if (!line) throw new Error("no line containing " + needle);
      const prefixLength =
        prefixLengthOrAuto === "auto"
          ? (/^[ 	]*(?:-(?: \[[ xX]\])? |[*+] |\d+\. )/.exec(line.textContent ?? "")?.[0].length ?? 0)
          : prefixLengthOrAuto;
      const rowLeft: [number, number][] = [];
      const prefixLefts: number[] = [];
      const charLefts: number[] = [];
      const charTops: number[] = [];
      let textRight = 0;
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
          charLefts.push(rect.left);
          textRight = Math.max(textRight, rect.right);
          charTops.push(rect.top);
          if (index < prefixLength) prefixLefts.push(rect.left);
          if (index === prefixLength) textStartLeft = rect.left;
          if (text[i] === " " || text[i] === "\t" || rect.width === 0) continue;
          const row = rowLeft.find(([top]) => Math.abs(top - rect.top) < 4);
          if (!row) rowLeft.push([rect.top, rect.left]);
          else if (rect.left < row[1]) row[1] = rect.left;
        }
      }
      const style = getComputedStyle(line);
      return {
        rows: rowLeft.sort((a, b) => a[0] - b[0]).map(([top, left]) => ({ top, left })),
        textStartLeft,
        prefixLefts,
        charLefts,
        charTops,
        contentLeft: line.getBoundingClientRect().left + Number.parseFloat(style.paddingLeft),
        hangClass: line.classList.contains("cm-quki-hang"),
        markerWidgets: line.querySelectorAll(".cm-quki-marker").length,
        contentRight: line.getBoundingClientRect().right - Number.parseFloat(style.paddingRight),
        textRight,
        lineHeight: line.getBoundingClientRect().height,
        floatBottom: (Number.parseFloat(getComputedStyle(line, "::before").marginTop) || 0) + (Number.parseFloat(getComputedStyle(line, "::before").height) || 0),
      };
    },
    { needle, prefixLengthOrAuto },
  );
}

export const WRAP = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua";

// Scott's screenshot: the deeply indented line is not a list item to the
// parser, so it stays raw; the two collapsed bullets follow it.
export const SCREENSHOT_LINE = "        - jdjd djdid rhe rndjdu ejwu heyie jehehe dhejeb dhej";
export const SCREENSHOT_DOC = `- blah\n${SCREENSHOT_LINE}\n- jdjd\n- `;

async function shot(page: Page, envName: string, name: string): Promise<void> {
  if (!shotsDir) return;
  fs.mkdirSync(shotsDir, { recursive: true });
  await page.screenshot({ path: path.join(shotsDir, `${envName}-${name}.png`), clip: { x: 0, y: 0, width: 400, height: 420 } });
}

/**
 * The raw line must (a) wrap, (b) start every wrapped row under its first
 * text character, (c) leave its first row exactly where plain-text mode
 * (undecorated source) puts it.
 */
export async function assertHangs(page: Page, label: string, needle: string, prefixLength: number | "auto"): Promise<HangGeometry> {
  const hung = await hangGeometry(page, needle, prefixLength);
  assert(hung.hangClass, `${label}: the raw line should be marked to hang`);
  assert(hung.markerWidgets === 0, `${label}: a raw line has no marker widget`);
  assert(hung.rows.length >= 2, `${label}: the line should wrap at this width, got ${hung.rows.length} row(s)`);
  for (const row of hung.rows.slice(1)) {
    assert(near(row.left, hung.textStartLeft), `${label}: a wrapped row starts at ${row.left}, not under the text at ${hung.textStartLeft}`);
  }
  assert(hung.textStartLeft > hung.contentLeft + 1, `${label}: the text start (${hung.textStartLeft}) should be right of the margin (${hung.contentLeft})`);
  // Nothing about the hang may make the line taller than its rows or reach into the next line.
  const pitch = (hung.rows[hung.rows.length - 1]!.top - hung.rows[0]!.top) / (hung.rows.length - 1);
  assert(near(hung.lineHeight, hung.rows.length * pitch, 2), `${label}: the line is ${hung.lineHeight}px tall but has ${hung.rows.length} rows of ${pitch}px`);
  assert(hung.textRight <= hung.contentRight + 0.5, `${label}: text reaches ${hung.textRight}, past the right margin at ${hung.contentRight}`);
  assert(hung.floatBottom <= hung.lineHeight + 0.5, `${label}: the hang float reaches ${hung.floatBottom}px into a line ${hung.lineHeight}px tall`);

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
  assertFirstRowUnmoved(label, hung, raw);
  return hung;
}

/** Every character on the first row, tabs in the text included, sits exactly where plain source puts it. */
function assertFirstRowUnmoved(label: string, hung: HangGeometry, raw: HangGeometry): void {
  const count = (g: HangGeometry): number => g.charTops.filter((top) => Math.abs(top - g.charTops[0]!) < 4).length;
  assert(count(hung) === count(raw), `${label}: the first row holds ${count(hung)} characters, plain source ${count(raw)}`);
  for (let i = 0; i < count(hung); i++) {
    assert(near(hung.charLefts[i]!, raw.charLefts[i]!), `${label}: first-row character ${i} moved from ${raw.charLefts[i]} to ${hung.charLefts[i]}`);
  }
}

export async function runHangScenarios(env: HangEnvironment): Promise<void> {
  const tag = `[e2e-hangingIndent:${env.name}]`;
  const loopWarnings: string[] = [];
  const watch = (page: Page): void => {
    page.on("console", (message) => {
      if (/Measure loop|failed to stabilize/.test(message.text())) loopWarnings.push(message.text());
    });
  };

  for (const scheme of ["light", "dark"] as const) {
    const session = await env.open(scheme, 400, 900);
    const { page } = session;
    watch(page);
    if (scheme === "light") console.log(`${tag} engine: ${await env.assertEngine(page)}`);
    await setDocAndSelection(page, SCREENSHOT_DOC, SCREENSHOT_DOC.length);
    await assertHangs(page, `screenshot document (${scheme})`, "jdjd djdid", 10);
    await shot(page, env.name, `screenshot-doc-${scheme}`);
    await session.close();
  }
  console.log(`${tag} PASS: the screenshot document's unrecognised deep line hangs its wrapped rows under the text, in light and dark`);

  const session = await env.open("light", 400, 900);
  const { page } = session;
  watch(page);

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
  console.log(`${tag} PASS: a revealed item (bullet, nested, ordered, two-digit, task, nested task) hangs under its text and its first row does not move`);

  await setDocAndSelection(page, doc, doc.length);
  for (const needle of ["alpha", "bravo", "delta", "foxtrot", "golf", "hotel", "star", "plus"]) {
    const g = await hangGeometry(page, needle, 0);
    assert(!g.hangClass && g.markerWidgets === 1, `collapsed ${needle}: keeps its marker widget and is not marked to hang`);
    for (const row of g.rows.slice(1)) {
      assert(near(row.left, g.rows[0]!.left), `collapsed ${needle}: wrapped rows still hang under the content`);
    }
  }
  console.log(`${tag} PASS: collapsed items keep their own hang and are not also marked`);

  // Tab characters anywhere in the leading whitespace, on a line the parser leaves raw.
  const tabDoc = `- top\n\t\t\t- tabbed ${WRAP}\n  \t  - mixed ${WRAP}\n`;
  await setDocAndSelection(page, tabDoc, tabDoc.length);
  await assertHangs(page, "line indented with tabs", "tabbed", 5);
  await assertHangs(page, "line indented with spaces and a tab", "mixed", 7);
  console.log(`${tag} PASS: tabs in the leading whitespace do not disturb the first row or the wrapped rows`);

  // A tab in the item's own text, on the first row and on a wrapped row.
  const bodyTabDoc = `- top\n\t\t- has\ttab\there ${WRAP} and\tanother ${WRAP}\n- [ ] task\twith\ttabs ${WRAP}\n`;
  await setDocAndSelection(page, bodyTabDoc, bodyTabDoc.indexOf("- [ ] task") + 1);
  await assertHangs(page, "raw line with tabs in its text", "has", 4);
  await assertHangs(page, "revealed task with tabs in its text", "task", 6);
  console.log(`${tag} PASS: tabs in the item's own text keep their exact positions on the first row`);

  // An unbroken word longer than the line must not push wrapped rows down or out.
  const longWord = "x".repeat(150);
  const longDoc = `- top\n\t\t- start ${longWord} end\n- after\n`;
  await setDocAndSelection(page, longDoc, longDoc.length);
  const long = await assertHangs(page, "line with an unbroken word", "start", 4);
  const gaps = long.rows.slice(1).map((row, i) => row.top - long.rows[i]!.top);
  assert(gaps.every((gap) => near(gap, gaps[0]!, 1.5)), `rows of the unbroken-word line should be evenly spaced, got ${gaps}`);
  console.log(`${tag} PASS: an unbroken word wraps under the text without gaps`);

  // A raw item that fits on one row is laid out exactly as plain source lays it out.
  const shortDoc = "- top\n\t- short\ttab item\n";
  await setDocAndSelection(page, shortDoc, shortDoc.indexOf("- short") + 1);
  const shortHung = await hangGeometry(page, "short", 3);
  await toggleMode(page);
  const shortRaw = await hangGeometry(page, "short", 3);
  await toggleMode(page);
  assert(shortHung.rows.length === 1 && shortRaw.rows.length === 1, "the short item should not wrap");
  assertFirstRowUnmoved("short raw item", shortHung, shortRaw);
  console.log(`${tag} PASS: a raw item that does not wrap is unmoved`);

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
  console.log(`${tag} PASS: typing and deleting keep every wrapped row under the text`);

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
  console.log(`${tag} PASS: moving the caret into and out of a marker switches between the raw hang and the collapsed layout`);

  // Resize and rotation.
  await setDocAndSelection(page, SCREENSHOT_DOC, SCREENSHOT_DOC.length);
  let wrappedWidths = 0;
  for (const [width, height] of [[320, 700], [700, 400], [400, 900], [900, 500]] as const) {
    await session.resize(width, height);
    await settle(page);
    const g = await hangGeometry(page, "jdjd djdid", 10);
    if (g.rows.length < 2) continue;
    wrappedWidths += 1;
    for (const row of g.rows.slice(1)) {
      assert(near(row.left, g.textStartLeft), `at ${width}x${height} a wrapped row starts at ${row.left}, not at ${g.textStartLeft}`);
    }
  }
  assert(wrappedWidths >= 2, `the line should wrap at two or more of the tested sizes, wrapped at ${wrappedWidths}`);
  await session.resize(400, 900);
  await settle(page);
  console.log(`${tag} PASS: the hang follows window resize and rotation`);

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
  console.log(`${tag} PASS: monospace, serif and proportional fonts all align exactly`);

  assert(loopWarnings.length === 0, `CodeMirror reported a measure loop: ${loopWarnings.join(" | ")}`);
  await session.close();
  console.log(`${tag} ALL SCENARIOS PASSED`);
}
