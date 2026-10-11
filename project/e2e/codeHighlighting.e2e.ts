import { chromium, type Browser, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type Scheme = "light" | "dark";

const JS_DOC = '```js\nconst greeting = "hi"; // say it\n```\n\nafter <span title="attr">inline html</span>\n';
const PYTHON_DOC = "```py\ndef greet():\n    return 1\n```\n\nafter\n";
const UNKNOWN_DOC = '```nope\nconst greeting = "hi";\n```\n\nafter\n';

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

async function variableColour(page: Page, name: string): Promise<string> {
  return page.evaluate((name) => {
    const probe = document.createElement("span");
    probe.style.color = `var(${name})`;
    document.body.appendChild(probe);
    const colour = getComputedStyle(probe).color;
    probe.remove();
    return colour;
  }, name);
}

// The computed colour of the first text in the editor equal to `text`, and of its line.
async function tokenColour(page: Page, text: string): Promise<{ token: string; line: string; classes: string }> {
  return page.evaluate((text) => {
    const walker = document.createTreeWalker(document.querySelector(".cm-content")!, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.textContent !== text || !node.parentElement) continue;
      const line = node.parentElement.closest(".cm-line")!;
      return {
        token: getComputedStyle(node.parentElement).color,
        line: getComputedStyle(line).color,
        classes: node.parentElement.className,
      };
    }
    throw new Error(`no text node exactly "${text}"`);
  }, text);
}

async function runScenario(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-code-highlighting:${scheme}]`;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 800 } });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  const languageRequests: string[] = [];
  // On the context, not the page: the service worker makes the fetch.
  context.on("request", (request) => {
    if (/\/assets\/lang-[^/]*\.js$/.test(request.url())) languageRequests.push(request.url());
  });
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await page.waitForTimeout(500);
  assert(languageRequests.length === 0, `${tag} no code language may load before a block names one, got ${languageRequests.join(", ")}`);

  const keyword = await variableColour(page, "--code-keyword");
  const string = await variableColour(page, "--code-string");
  const comment = await variableColour(page, "--code-comment");
  const normal = await variableColour(page, "--code-normal");
  assert(new Set([keyword, string, comment, normal]).size === 4, `${tag} the code colours must differ for this test to mean anything: ${keyword} ${string} ${comment} ${normal}`);

  await setDocAndCaret(page, PYTHON_DOC, PYTHON_DOC.length);
  await page.waitForSelector(".cm-quki-tok-keyword", { timeout: 10000 });
  assert(languageRequests.length > 0, `${tag} a python block must load its language on demand`);
  const def = await tokenColour(page, "def");
  assert(def.token === keyword, `${tag} python's "def" must be --code-keyword ${keyword}, got ${def.token} (${def.classes})`);
  console.log(`${tag} PASS: no language loads until a block names one, and a python block then loads and colours its own`);

  // JavaScript ships in the main bundle already (markdown's HTML support imports it).
  await setDocAndCaret(page, JS_DOC, JS_DOC.length);
  await page.waitForSelector(".cm-quki-tok-keyword", { timeout: 10000 });
  const collapsed = { keyword: await tokenColour(page, "const"), string: await tokenColour(page, '"hi"'), comment: await tokenColour(page, "// say it") };
  assert(collapsed.keyword.token === keyword, `${tag} "const" must be --code-keyword ${keyword}, got ${collapsed.keyword.token} (${collapsed.keyword.classes})`);
  assert(collapsed.string.token === string, `${tag} "hi" must be --code-string ${string}, got ${collapsed.string.token} (${collapsed.string.classes})`);
  assert(collapsed.comment.token === comment, `${tag} the comment must be --code-comment ${comment}, got ${collapsed.comment.token} (${collapsed.comment.classes})`);
  console.log(`${tag} PASS: a js block's keyword, string and comment take their code colours`);

  const attr = await tokenColour(page, '"attr"');
  assert(attr.token === attr.line, `${tag} inline HTML in a paragraph stays literal text, but its attribute value is ${attr.token} on a ${attr.line} line`);
  console.log(`${tag} PASS: inline HTML outside a code block is not coloured`);

  await setDocAndCaret(page, JS_DOC, JS_DOC.indexOf("const") + 2);
  const revealedFence = await page.evaluate(() => [...document.querySelectorAll(".cm-line")].some((l) => l.textContent === "```js"));
  assert(revealedFence, `${tag} the caret inside the block must reveal its raw fences`);
  const revealed = await tokenColour(page, "const");
  assert(revealed.token === keyword, `${tag} a revealed block keeps its colours: "const" is ${revealed.token}`);
  console.log(`${tag} PASS: with the caret inside, the raw block keeps its code colours`);

  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await page.waitForSelector(".cm-editor.cm-quki-plain-text");
  await page.waitForTimeout(250);
  for (const text of ["const", '"hi"', "// say it"]) {
    const plain = await tokenColour(page, text);
    assert(plain.token === plain.line, `${tag} plain-text mode leaves code uncoloured: "${text}" is ${plain.token} on a ${plain.line} line`);
  }
  console.log(`${tag} PASS: plain-text mode shows code uncoloured`);
  await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
  await page.waitForTimeout(250);

  await setDocAndCaret(page, UNKNOWN_DOC, UNKNOWN_DOC.length);
  const unknownTokens = await page.evaluate(() => document.querySelectorAll('.cm-content [class*="cm-quki-tok-"]').length);
  assert(unknownTokens === 0, `${tag} an unknown language's block gets no code colours, found ${unknownTokens} coloured tokens`);
  const unknownLine = await page.evaluate(() => {
    const line = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent?.includes("greeting"))!;
    return { colour: getComputedStyle(line).color, font: getComputedStyle(line).fontFamily };
  });
  assert(unknownLine.colour === normal, `${tag} an unknown language's code is --code-normal ${normal}, got ${unknownLine.colour}`);
  assert(unknownLine.font.includes("monospace"), `${tag} an unknown language's code stays monospace, got ${unknownLine.font}`);
  console.log(`${tag} PASS: an unknown language's block stays plain monospace`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-code-highlighting] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  try {
    for (const scheme of ["light", "dark"] as const) await runScenario(browser, url, scheme);
    console.log("[e2e-code-highlighting] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-code-highlighting] FAILED:", err);
    process.exit(1);
  });
