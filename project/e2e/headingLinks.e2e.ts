import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type WindowWithQukiView = typeof window & {
  qukiView: {
    state: { doc: { toString(): string; length: number } };
    dispatch: (spec: unknown) => void;
    focus: () => void;
  };
};

const URL_TEXT = "https://example.com";

function variants(level: number): { name: string; source: string; needle: string }[] {
  const hashes = "#".repeat(level);
  return [
    { name: "link at end", source: `${hashes} End h${level} [end link ${level}](${URL_TEXT})`, needle: `End h${level}` },
    { name: "link only", source: `${hashes} [only link ${level}](${URL_TEXT})`, needle: `only link ${level}` },
    { name: "bare URL", source: `${hashes} ${URL_TEXT}/h${level}`, needle: `${URL_TEXT}/h${level}` },
    { name: "link in middle", source: `${hashes} Mid h${level} [mid link ${level}](${URL_TEXT}) tail`, needle: `Mid h${level}` },
    { name: "link at start", source: `${hashes} [start link ${level}](${URL_TEXT}) after`, needle: `start link ${level}` },
  ];
}

interface TextRun {
  text: string;
  fontSize: string;
  fontWeight: string;
  inLink: boolean;
  inHeading: boolean;
  colour: string;
  underlined: boolean;
}

async function setDocAndCaret(page: Page, text: string, caret: number): Promise<void> {
  await page.evaluate(
    ({ text, caret }) => {
      const view = (window as WindowWithQukiView).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: caret } });
      view.focus();
    },
    { text, caret },
  );
  await page.waitForTimeout(150);
}

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

async function lineRuns(page: Page, needle: string): Promise<TextRun[]> {
  return page.evaluate((needle) => {
    const lines = [...document.querySelectorAll<HTMLElement>(".cm-content .cm-line")].filter((l) => l.textContent?.includes(needle));
    if (lines.length !== 1) throw new Error(`expected one line containing ${needle}, found ${lines.length}`);
    const runs: TextRun[] = [];
    const walker = document.createTreeWalker(lines[0]!, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      const text = node.textContent ?? "";
      if (!text.trim() || !node.parentElement) continue;
      const el = node.parentElement;
      const style = getComputedStyle(el);
      const link = el.closest<HTMLElement>(".cm-quki-link");
      runs.push({
        text,
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
        inLink: link !== null,
        inHeading: el.closest(".cm-quki-heading") !== null,
        colour: style.color,
        underlined: link !== null && getComputedStyle(link).textDecorationLine.includes("underline"),
      });
    }
    return runs;
  }, needle);
}

async function assertHeadingSizes(page: Page, tag: string, level: number): Promise<void> {
  const plain = await lineRuns(page, `Plain h${level}`);
  assert(plain.length === 1 && plain[0]!.inHeading, `${tag} the plain h${level} should be one run inside the heading mark: ${JSON.stringify(plain)}`);
  const { fontSize, fontWeight } = plain[0]!;
  const outside = (await lineRuns(page, "outside link")).find((r) => r.inLink);
  assert(outside !== undefined, `${tag} the link outside a heading should render as a link`);

  for (const variant of variants(level)) {
    const runs = await lineRuns(page, variant.needle);
    const linkRuns = runs.filter((r) => r.inLink);
    assert(linkRuns.length === 1, `${tag} h${level} ${variant.name}: expected one drawn link, got ${JSON.stringify(runs)}`);
    for (const run of runs) {
      assert(
        run.fontSize === fontSize && run.fontWeight === fontWeight && run.inHeading,
        `${tag} h${level} ${variant.name}: "${run.text}" should render like the plain h${level} (${fontSize}, weight ${fontWeight}, inside the heading), got ${run.fontSize}, weight ${run.fontWeight}, inHeading=${run.inHeading}`,
      );
    }
    const link = linkRuns[0]!;
    assert(link.underlined && link.colour === outside.colour, `${tag} h${level} ${variant.name}: the link should keep its colour ${outside.colour} and underline, got ${link.colour}, underlined=${link.underlined}`);
  }
}

async function runScenario(browser: Browser, url: string): Promise<void> {
  const tag = "[e2e-headingLinks]";
  const context = await browser.newContext({ viewport: { width: 900, height: 2400 } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  const lines: string[] = [];
  for (let level = 1; level <= 6; level++) {
    lines.push(`${"#".repeat(level)} Plain h${level}`);
    for (const variant of variants(level)) lines.push(variant.source);
  }
  lines.push("An [outside link](https://example.com) in a paragraph", "", "last line");
  const doc = lines.join("\n");
  await setDocAndCaret(page, doc, doc.length);

  for (let level = 1; level <= 6; level++) await assertHeadingSizes(page, tag, level);
  console.log(`${tag} PASS: every heading level renders a link at its heading size, wherever the link sits`);

  const outside = (await lineRuns(page, "outside link")).find((r) => r.inLink)!;
  const paragraph = (await lineRuns(page, "in a paragraph")).find((r) => !r.inLink)!;
  assert(
    !outside.inHeading && outside.fontSize === paragraph.fontSize && outside.fontWeight === paragraph.fontWeight,
    `${tag} a link outside a heading stays at the paragraph's size ${paragraph.fontSize} and weight ${paragraph.fontWeight}, got ${outside.fontSize}, weight ${outside.fontWeight}`,
  );
  console.log(`${tag} PASS: a link outside a heading is unchanged`);

  await context.route("https://example.com/**", (route) => route.fulfill({ status: 200, contentType: "text/html", body: "<title>target</title>" }));
  const [popup] = await Promise.all([
    page.waitForEvent("popup"),
    page.locator(".cm-quki-heading .cm-quki-link", { hasText: "end link 1" }).click(),
  ]);
  assert(popup.url() === `${URL_TEXT}/`, `${tag} clicking a link that ends a heading should open ${URL_TEXT}/, opened ${popup.url()}`);
  await popup.close();
  console.log(`${tag} PASS: a link that ends a heading still opens when clicked`);

  const linkHeading = `# [Title](${URL_TEXT})`;
  const editDoc = `intro\n${linkHeading}\nnext\nend`;
  const headingStart = editDoc.indexOf(linkHeading);
  const sourceLine = async (): Promise<string> => (await editorBody(page)).split("\n")[1]!;

  const headingShown = async (): Promise<{ text: string; links: number }> => {
    const line = page.locator(".cm-content .cm-line").nth(1);
    return { text: await line.innerText(), links: await line.locator(".cm-quki-link").count() };
  };
  await setDocAndCaret(page, editDoc, headingStart);
  let shown = await headingShown();
  assert(shown.text === "# Title" && shown.links === 1, `${tag} with the caret on the heading marker the marker should show and the link stay drawn, got ${JSON.stringify(shown)}`);
  await setDocAndCaret(page, editDoc, headingStart + linkHeading.length);
  shown = await headingShown();
  assert(shown.text === `[Title](${URL_TEXT})` && shown.links === 0, `${tag} with the caret at the end of the link its source should show, got ${JSON.stringify(shown)}`);
  await setDocAndCaret(page, editDoc, editDoc.length);
  assert((await page.locator(".cm-quki-heading .cm-quki-link", { hasText: "Title" }).count()) === 1, `${tag} with the caret elsewhere the heading should draw its link`);
  console.log(`${tag} PASS: the heading's source still reveals when the caret enters it`);

  const cdp = await context.newCDPSession(page);
  await setDocAndCaret(page, editDoc, headingStart + linkHeading.length);
  await cdp.send("Input.insertText", { text: "!" });
  await page.waitForTimeout(150);
  assert((await sourceLine()) === `${linkHeading}!`, `${tag} DOM text input at the end of a heading ending with a link should append, got ${JSON.stringify(await sourceLine())}`);

  await setDocAndCaret(page, editDoc, headingStart + 2);
  await page.evaluate(() => document.execCommand("delete"));
  await page.waitForTimeout(150);
  assert((await sourceLine()) === `#[Title](${URL_TEXT})`, `${tag} a DOM backward delete at the start of the heading's text should remove one space, got ${JSON.stringify(await sourceLine())}`);

  await setDocAndCaret(page, editDoc, headingStart + 2);
  await page.keyboard.press("Backspace");
  await page.waitForTimeout(150);
  assert((await sourceLine()) === `#[Title](${URL_TEXT})`, `${tag} Backspace at the start of the heading's text should remove one space, got ${JSON.stringify(await sourceLine())}`);

  const nextStart = editDoc.indexOf("\nnext") + 1;
  await setDocAndCaret(page, editDoc, nextStart);
  assert((await page.locator(".cm-quki-heading .cm-quki-link", { hasText: "Title" }).count()) === 1, `${tag} with the caret on the next line the heading should draw its link`);
  await page.evaluate(() => document.execCommand("delete"));
  await page.waitForTimeout(150);
  assert((await sourceLine()) === `${linkHeading}next`, `${tag} a DOM backward delete at the start of the next line should join it onto the heading, got ${JSON.stringify(await sourceLine())}`);
  console.log(`${tag} PASS: typing and deleting next to a heading that ends with a link edit one character, by key and by DOM edit`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-headingLinks] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    await runScenario(browser, url);
    console.log("[e2e-headingLinks] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-headingLinks] FAILED:", err);
    process.exit(1);
  });
