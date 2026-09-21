import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type Scheme = "light" | "dark";

const NARROW = "iiiiiiiiii";
const WIDE = "WWWWWWWWWW";
const DOC = [
  `${NARROW} ${WIDE} plain`,
  `# ${NARROW} ${WIDE} heading`,
  `- ${NARROW} ${WIDE} bullet`,
  `- [ ] ${NARROW} ${WIDE} task`,
  `> ${NARROW} ${WIDE} quote`,
  `**${NARROW} ${WIDE}** bold, *${NARROW} ${WIDE}* italic, [${NARROW} ${WIDE}](https://example.com) link`,
  `\`${NARROW}\` and \`${WIDE}\` chips`,
  "last line",
].join("\n\n");

type QukiWindow = typeof window & {
  qukiView: { state: { doc: { length: number } }; dispatch: (spec: unknown) => void };
};

async function setDocAndCaret(page: Page, text: string, caret: number): Promise<void> {
  await page.evaluate(
    ({ text, caret }) => {
      const view = (window as QukiWindow).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: caret } });
    },
    { text, caret },
  );
  await page.waitForTimeout(250);
}

async function togglePlainText(page: Page): Promise<void> {
  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await page.waitForTimeout(250);
}

/** The font-family the browser computes for `var(<name>)`, so it can be compared with what an element actually got. */
async function resolvedFamily(page: Page, variable: string): Promise<string> {
  return page.evaluate((variable) => {
    const probe = document.createElement("div");
    probe.style.fontFamily = `var(${variable})`;
    document.body.appendChild(probe);
    const family = getComputedStyle(probe).fontFamily;
    probe.remove();
    return family;
  }, variable);
}

interface Run {
  width: number;
  family: string;
}

/** Width and font of the run `glyphs` inside the first element matching `scope` that contains it. */
async function measureRun(page: Page, scope: string, needleOfElement: string, glyphs: string): Promise<Run> {
  return page.evaluate(
    ({ scope, needleOfElement, glyphs }) => {
      const element = [...document.querySelectorAll<HTMLElement>(scope)].find((e) => e.textContent?.includes(needleOfElement));
      if (!element) throw new Error(`no ${scope} containing ${needleOfElement}`);
      const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const index = (node.textContent ?? "").indexOf(glyphs);
        if (index < 0) continue;
        const range = document.createRange();
        range.setStart(node, index);
        range.setEnd(node, index + glyphs.length);
        const style = getComputedStyle(node.parentElement!);
        return { width: range.getBoundingClientRect().width, family: style.fontFamily };
      }
      throw new Error(`no text node with ${glyphs} in ${scope} containing ${needleOfElement}`);
    },
    { scope, needleOfElement, glyphs },
  );
}

async function assertProportional(page: Page, tag: string, what: string, scope: string, needle: string, expectedFamily: string): Promise<void> {
  const narrow = await measureRun(page, scope, needle, NARROW);
  const wide = await measureRun(page, scope, needle, WIDE);
  assert(wide.width > narrow.width * 1.5, `${tag} ${what}: ten W must be clearly wider than ten i in a proportional font, got W ${wide.width.toFixed(1)}px vs i ${narrow.width.toFixed(1)}px (${narrow.family})`);
  assert(narrow.family === expectedFamily, `${tag} ${what}: font-family must come from --font-text (${expectedFamily}), got ${narrow.family}`);
  assert(wide.family === expectedFamily, `${tag} ${what}: the wide run must use --font-text (${expectedFamily}), got ${wide.family}`);
}

async function assertMonospace(page: Page, tag: string, what: string, scope: string, needle: string, expectedFamily: string, wideNeedle = needle): Promise<void> {
  const narrow = await measureRun(page, scope, needle, NARROW);
  const wide = await measureRun(page, scope, wideNeedle, WIDE);
  assert(wide.family === expectedFamily, `${tag} ${what}: the wide run must use --font-monospace (${expectedFamily}), got ${wide.family}`);
  assert(Math.abs(wide.width - narrow.width) <= 0.5, `${tag} ${what}: ten W and ten i must be equally wide in a monospace font, got W ${wide.width.toFixed(2)}px vs i ${narrow.width.toFixed(2)}px (${narrow.family})`);
  assert(narrow.family === expectedFamily, `${tag} ${what}: font-family must come from --font-monospace (${expectedFamily}), got ${narrow.family}`);
}

async function interfaceMismatches(page: Page, interfaceFamily: string, minimumChecked = 1): Promise<string[]> {
  return page.evaluate(({ interfaceFamily, minimumChecked }) => {
    const found: string[] = [];
    let checked = 0;
    for (const el of document.body.querySelectorAll<HTMLElement>("*")) {
      if (el.closest(".cm-editor") || el.closest("svg") || !el.checkVisibility()) continue;
      const isControl = ["INPUT", "TEXTAREA", "SELECT", "BUTTON"].includes(el.tagName);
      const ownText = [...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && (n.textContent ?? "").trim() !== "");
      if (!isControl && !ownText) continue;
      checked += 1;
      const family = getComputedStyle(el).fontFamily;
      if (family !== interfaceFamily) found.push(`${el.tagName.toLowerCase()}.${String(el.className)} has ${family}`);
    }
    if (checked < minimumChecked) found.push(`only ${checked} elements were checked, expected at least ${minimumChecked}`);
    return found;
  }, { interfaceFamily, minimumChecked });
}

async function assertInterfaceFont(page: Page, tag: string, screen: string, interfaceFamily: string): Promise<void> {
  const mismatches = await interfaceMismatches(page, interfaceFamily, 2);
  assert(mismatches.length === 0, `${tag} ${screen}: every piece of text outside the editor must use --font-interface (${interfaceFamily}), but:\n  ${mismatches.join("\n  ")}`);
}

async function assertEditorFonts(page: Page, tag: string): Promise<void> {
  const text = await resolvedFamily(page, "--font-text");
  const mono = await resolvedFamily(page, "--font-monospace");
  assert(text !== mono, `${tag}: --font-text and --font-monospace must differ (${text})`);

  await setDocAndCaret(page, DOC, DOC.length);
  await assertProportional(page, tag, "a paragraph", ".cm-line", "plain", text);
  await assertProportional(page, tag, "a heading", ".cm-line", "heading", text);
  await assertProportional(page, tag, "a list item", ".cm-line", "bullet", text);
  await assertProportional(page, tag, "a task item", ".cm-line", "task", text);
  await assertProportional(page, tag, "a quote", ".cm-line", "quote", text);
  await assertProportional(page, tag, "bold text", ".cm-quki-strong", NARROW, text);
  await assertProportional(page, tag, "italic text", ".cm-quki-em", NARROW, text);
  await assertProportional(page, tag, "a link", ".cm-quki-link", NARROW, text);
  await assertMonospace(page, tag, "inline code chips", ".cm-quki-code", NARROW, mono, WIDE);
  console.log(`${tag} PASS: paragraph, heading, list item, task, quote, bold, italic and link are proportional and use --font-text; code chips are monospace and use --font-monospace`);

  await setDocAndCaret(page, DOC, 0);
  await assertProportional(page, tag, "a paragraph with the caret in it", ".cm-line", "plain", text);
  console.log(`${tag} PASS: revealing source keeps the body font`);

  await togglePlainText(page);
  await assertMonospace(page, tag, "plain-text mode paragraph", ".cm-line", "plain", mono);
  await assertMonospace(page, tag, "plain-text mode heading", ".cm-line", "heading", mono);
  await assertMonospace(page, tag, "plain-text mode list item", ".cm-line", "bullet", mono);
  console.log(`${tag} PASS: plain-text mode is monospace and uses --font-monospace`);
  await togglePlainText(page);
  await assertProportional(page, tag, "a paragraph after leaving plain-text mode", ".cm-line", "plain", text);
  console.log(`${tag} PASS: leaving plain-text mode restores the body font`);
}

async function assertVariablesDriveTheFonts(page: Page, tag: string): Promise<void> {
  await setDocAndCaret(page, DOC, DOC.length);
  const before = {
    text: await resolvedFamily(page, "--font-text"),
    mono: await resolvedFamily(page, "--font-monospace"),
    interface: await resolvedFamily(page, "--font-interface"),
  };
  const familyOf = (scope: string, needle: string, glyphs: string) => measureRun(page, scope, needle, glyphs).then((r) => r.family);
  const setTheme = (name: string, value: string) => page.evaluate(([n, v]) => document.body.style.setProperty(n!, v!), [name, value]);

  await setTheme("--font-text-theme", "Georgia, serif");
  const afterText = await resolvedFamily(page, "--font-text");
  assert(afterText !== before.text, `${tag}: setting --font-text-theme must change --font-text (${afterText})`);
  assert((await familyOf(".cm-line", "plain", NARROW)) === afterText, `${tag}: the editor's body text must follow --font-text-theme`);
  assert((await familyOf(".cm-quki-code", NARROW, NARROW)) === before.mono, `${tag}: a code chip must not follow --font-text-theme`);
  assert((await resolvedFamily(page, "--font-interface")) === before.interface, `${tag}: --font-interface must not follow --font-text-theme`);
  await setTheme("--font-text-theme", "");

  await setTheme("--font-monospace-theme", "'Times New Roman', serif");
  const afterMono = await resolvedFamily(page, "--font-monospace");
  assert(afterMono !== before.mono, `${tag}: setting --font-monospace-theme must change --font-monospace (${afterMono})`);
  assert((await familyOf(".cm-quki-code", NARROW, NARROW)) === afterMono, `${tag}: a code chip must follow --font-monospace-theme`);
  assert((await familyOf(".cm-line", "plain", NARROW)) === before.text, `${tag}: body text must not follow --font-monospace-theme`);
  await togglePlainText(page);
  assert((await familyOf(".cm-line", "plain", NARROW)) === afterMono, `${tag}: plain-text mode must follow --font-monospace-theme`);
  await togglePlainText(page);
  await setTheme("--font-monospace-theme", "");

  await setTheme("--font-interface-theme", "Georgia, serif");
  const afterInterface = await resolvedFamily(page, "--font-interface");
  assert(afterInterface !== before.interface, `${tag}: setting --font-interface-theme must change --font-interface (${afterInterface})`);
  assert((await interfaceMismatches(page, afterInterface)).length === 0, `${tag}: the app chrome must follow --font-interface-theme`);
  assert((await familyOf(".cm-line", "plain", NARROW)) === before.text, `${tag}: body text must not follow --font-interface-theme`);
  await setTheme("--font-interface-theme", "");

  console.log(`${tag} PASS: a theme setting --font-text-theme, --font-monospace-theme or --font-interface-theme restyles exactly its own part of the app`);
}

async function runScenario(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-fonts:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 800 } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  await assertEditorFonts(page, tag);
  await assertVariablesDriveTheFonts(page, tag);

  const interfaceFamily = await resolvedFamily(page, "--font-interface");
  const bodyFamily = await page.evaluate(() => getComputedStyle(document.body).fontFamily);
  assert(bodyFamily === interfaceFamily, `${tag}: the page's own font must be --font-interface (${interfaceFamily}), got ${bodyFamily}`);

  await setDocAndCaret(page, "A QuKi to list, delete and restore\n", 5);
  await page.waitForSelector("#btn-quki-list:not([disabled])");
  await assertInterfaceFont(page, tag, "the editor's app bar", interfaceFamily);

  await page.click("#btn-quki-list");
  await page.locator(".view:not([hidden]) .list-row").first().waitFor();
  await assertInterfaceFont(page, tag, "the list", interfaceFamily);
  await page.locator(".view:not([hidden]) .back-btn").click();

  await page.click("#btn-settings");
  await page.locator(".view:not([hidden]) .trash-btn").waitFor();
  await assertInterfaceFont(page, tag, "settings", interfaceFamily);
  await page.locator(".view:not([hidden]) .back-btn").click();

  await page.click("#btn-help");
  await page.locator("[role=dialog]").waitFor({ state: "visible" });
  await assertInterfaceFont(page, tag, "the About box", interfaceFamily);
  await page.locator(".about-close").click();

  await page.click("#btn-delete");
  await page.locator(".toast").waitFor({ state: "visible" });
  await assertInterfaceFont(page, tag, "the toast", interfaceFamily);

  await page.click("#btn-settings");
  await page.locator(".view:not([hidden]) .trash-btn").click();
  await page.locator(".view:not([hidden]) .list-row").first().waitFor();
  await assertInterfaceFont(page, tag, "the trash", interfaceFamily);
  await page.locator(".view:not([hidden]) .empty-trash-btn").click();
  await page.locator(".confirm-cancel").waitFor({ state: "visible" });
  await assertInterfaceFont(page, tag, "the empty-trash confirmation", interfaceFamily);
  console.log(`${tag} PASS: the page, app bar, list, settings, About box, toast, trash and confirmation all use --font-interface`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-fonts] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) await runScenario(browser, url, scheme);
    console.log("[e2e-fonts] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-fonts] FAILED:", err);
    process.exit(1);
  });
