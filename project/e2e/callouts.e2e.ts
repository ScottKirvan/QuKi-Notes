import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type Scheme = "light" | "dark";

const DOC = "plain\n\n> [!WARNING]\n> Mind the *gap*\n\nafter";

// github.com's warning colour: GitHubDHC's in dark, github.com light's in light.
const WARNING_COLOUR: Record<Scheme, string> = {
  dark: "rgb(240, 183, 47)",
  light: "rgb(154, 103, 0)",
};

async function setDocAndCaret(page: Page, text: string, caret: number): Promise<void> {
  await page.evaluate(
    ({ text, caret }) => {
      const view = (window as unknown as { qukiView: { state: { doc: { length: number } }; dispatch: (spec: unknown) => void; focus: () => void } }).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: caret } });
      view.focus();
    },
    { text, caret },
  );
  await page.waitForTimeout(250);
}

interface TitleState {
  text: string;
  colour: string;
  weight: number;
  iconPaths: number;
  iconWidth: number;
  iconFill: string;
  lineBackground: string;
  bodyBackground: string;
  bodyTextColour: string;
  normalTextColour: string;
}

async function titleState(page: Page): Promise<TitleState | null> {
  return page.evaluate(() => {
    const title = document.querySelector<HTMLElement>(".cm-quki-callout-title");
    if (!title) return null;
    const icon = title.querySelector<SVGSVGElement>("svg.cm-quki-callout-icon");
    const line = title.closest<HTMLElement>(".cm-line")!;
    const body = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent?.includes("Mind the"))!;
    const plain = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent === "plain")!;
    const bodyText = [...body.childNodes].find((n) => n.nodeType === Node.TEXT_NODE && n.textContent?.includes("Mind"));
    return {
      text: title.textContent ?? "",
      colour: getComputedStyle(title).color,
      weight: Number(getComputedStyle(title).fontWeight),
      iconPaths: icon ? icon.querySelectorAll("path").length : 0,
      iconWidth: icon ? icon.getBoundingClientRect().width : 0,
      iconFill: icon ? getComputedStyle(icon.querySelector("path")!).fill : "",
      lineBackground: getComputedStyle(line).backgroundImage,
      bodyBackground: getComputedStyle(body).backgroundImage,
      bodyTextColour: bodyText ? getComputedStyle(bodyText.parentElement!).color : "no bare text node",
      normalTextColour: getComputedStyle(plain).color,
    };
  });
}

async function markerLineText(page: Page): Promise<string> {
  return page.evaluate(() => document.querySelectorAll<HTMLElement>(".cm-line")[2]?.textContent ?? "");
}

async function runScenario(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-callouts:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 800 } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  await setDocAndCaret(page, DOC, 0);
  const title = await titleState(page);
  assert(title !== null, `${tag} a > [!WARNING] block with the caret elsewhere must render a callout title`);
  assert(title.text === "Warning", `${tag} the title must read "Warning", got "${title.text}"`);
  assert(title.colour === WARNING_COLOUR[scheme], `${tag} the title must be ${WARNING_COLOUR[scheme]}, got ${title.colour}`);
  assert(title.weight >= 600, `${tag} the title must be bold, got ${title.weight}`);
  assert(title.iconPaths === 1 && title.iconWidth === 16, `${tag} the title must show a 16px icon, got ${title.iconPaths} path(s), ${title.iconWidth}px`);
  assert(title.iconFill === WARNING_COLOUR[scheme], `${tag} the icon must be drawn in the warning colour, got ${title.iconFill}`);
  console.log(`${tag} PASS: the title shows the icon and "Warning" in ${title.colour}`);

  for (const [what, background] of [["title line", title.lineBackground], ["body line", title.bodyBackground]] as const) {
    assert(background.includes(WARNING_COLOUR[scheme]), `${tag} the ${what}'s left border must be ${WARNING_COLOUR[scheme]}, got ${background}`);
  }
  console.log(`${tag} PASS: the title and body lines carry a left border in the warning colour`);

  assert(title.bodyTextColour === title.normalTextColour, `${tag} the body text must stay the normal text colour ${title.normalTextColour}, got ${title.bodyTextColour}`);
  console.log(`${tag} PASS: the body text is not muted`);

  await setDocAndCaret(page, DOC, 12);
  assert((await titleState(page)) === null, `${tag} with the caret on the marker line the title must not render`);
  const raw = await markerLineText(page);
  assert(raw === "> [!WARNING]", `${tag} with the caret on the marker line it must show raw, got "${raw}"`);
  console.log(`${tag} PASS: the marker line shows raw with the caret on it`);

  await setDocAndCaret(page, DOC, 0);
  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await page.waitForTimeout(250);
  assert((await titleState(page)) === null, `${tag} plain-text mode must not render the callout title`);
  const plainRaw = await markerLineText(page);
  assert(plainRaw === "> [!WARNING]", `${tag} plain-text mode must show the raw marker line, got "${plainRaw}"`);
  console.log(`${tag} PASS: plain-text mode shows the raw marker`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-callouts] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) await runScenario(browser, url, scheme);
    console.log("[e2e-callouts] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-callouts] FAILED:", err);
    process.exit(1);
  });
