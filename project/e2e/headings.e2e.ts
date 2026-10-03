import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type Scheme = "light" | "dark";

const DOC = "# Heading one\n\n## Heading two\n\n### Heading three\n\nplain paragraph\n\nA [link](https://example.com) here\n";
const HEADINGS = ["Heading one", "Heading two", "Heading three"];

interface TextStyle {
  underlined: boolean;
  weight: number;
  chain: string[];
}

async function setDocAndCaret(page: Page, text: string, caret: number): Promise<void> {
  await page.evaluate(
    ({ text, caret }) => {
      const view = (window as unknown as { qukiView: { state: { doc: { length: number } }; dispatch: (spec: unknown) => void } }).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: caret } });
    },
    { text, caret },
  );
  await page.waitForTimeout(250);
}

async function textStyle(page: Page, needle: string): Promise<TextStyle> {
  return page.evaluate((needle) => {
    const line = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent?.includes(needle));
    if (!line) throw new Error(`no line containing ${needle}`);
    const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node && !(node.textContent ?? "").includes(needle.split(" ")[0]!)) node = walker.nextNode();
    if (!node || !node.parentElement) throw new Error(`no text node for ${needle}`);
    const chain: HTMLElement[] = [];
    for (let el: HTMLElement | null = node.parentElement; el; el = el.parentElement) chain.push(el);
    return {
      underlined: chain.some((el) => getComputedStyle(el).textDecorationLine.includes("underline")),
      weight: Number(getComputedStyle(node.parentElement).fontWeight),
      chain: chain.map((el) => `${el.tagName.toLowerCase()}.${el.className}=${getComputedStyle(el).textDecorationLine}`),
    };
  }, needle);
}

async function assertHeadings(page: Page, tag: string, what: string): Promise<void> {
  for (const heading of HEADINGS) {
    const style = await textStyle(page, heading);
    assert(!style.underlined, `${tag} ${what}: "${heading}" must not be underlined, but an element in its chain is: ${style.chain.join(" < ")}`);
    assert(style.weight >= 600, `${tag} ${what}: "${heading}" must stay bold, computed font-weight ${style.weight}`);
  }
}

async function runScenario(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-headings:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 800 } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  await setDocAndCaret(page, DOC, DOC.length);
  await assertHeadings(page, tag, "collapsed");
  console.log(`${tag} PASS: collapsed headings are bold and not underlined`);

  await setDocAndCaret(page, DOC, 5);
  await assertHeadings(page, tag, "revealed");
  console.log(`${tag} PASS: a revealed heading is bold and not underlined`);

  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await page.waitForTimeout(250);
  await assertHeadings(page, tag, "plain-text mode");
  console.log(`${tag} PASS: headings are bold and not underlined in plain-text mode`);
  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await page.waitForTimeout(250);

  await setDocAndCaret(page, DOC, DOC.length);
  const link = await textStyle(page, "link");
  assert(link.underlined, `${tag} links keep their underline; if this fails the underline check above proves nothing (${link.chain.join(" < ")})`);
  console.log(`${tag} PASS: a link is still underlined, so the check above can see an underline`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-headings] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) await runScenario(browser, url, scheme);
    console.log("[e2e-headings] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-headings] FAILED:", err);
    process.exit(1);
  });
