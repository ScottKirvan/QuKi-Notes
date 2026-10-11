import { chromium, type Page } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

const TAG = "[e2e-spellcheck]";

const DOC = [
  "Teh prose line",
  "",
  "Some `inlinecodde` here",
  "",
  "```",
  "fencedd codde",
  "```",
  "",
  "- [ ] taskk item",
  "",
  "| colA | colB |",
  "| ---- | ---- |",
  "| one  | two  |",
  "",
  "last linne",
].join("\n");

async function setDocAndCaret(page: Page, caret: number): Promise<void> {
  await page.evaluate(
    ({ text, caret }) => {
      const view = (window as unknown as { qukiView: { state: { doc: { length: number } }; dispatch: (spec: unknown) => void } }).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: caret } });
    },
    { text: DOC, caret },
  );
  await page.waitForTimeout(250);
}

async function contentAttributes(page: Page): Promise<Record<string, string | null>> {
  return page.evaluate(() => {
    const content = document.querySelector<HTMLElement>(".cm-content")!;
    return {
      spellcheck: content.getAttribute("spellcheck"),
      autocorrect: content.getAttribute("autocorrect"),
      autocapitalize: content.getAttribute("autocapitalize"),
    };
  });
}

// HTMLElement.spellcheck is the browser's own answer for an element,
// inherited from the nearest ancestor that sets the attribute.
async function spellcheckedAt(page: Page, needle: string): Promise<boolean> {
  return page.evaluate((needle) => {
    const content = document.querySelector<HTMLElement>(".cm-content")!;
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if ((node.textContent ?? "").includes(needle) && node.parentElement) return node.parentElement.spellcheck;
    }
    throw new Error(`no text node containing ${needle}`);
  }, needle);
}

async function assertSpellcheckLayout(page: Page, what: string): Promise<void> {
  const attrs = await contentAttributes(page);
  assert(attrs.spellcheck === "true", `${TAG} ${what}: .cm-content spellcheck must be "true", got ${attrs.spellcheck}`);
  assert(attrs.autocorrect === "on", `${TAG} ${what}: .cm-content autocorrect must be "on", got ${attrs.autocorrect}`);
  assert(attrs.autocapitalize === "sentences", `${TAG} ${what}: .cm-content autocapitalize must be "sentences", got ${attrs.autocapitalize}`);
  assert(await spellcheckedAt(page, "Teh"), `${TAG} ${what}: ordinary text must be spellchecked`);
  assert(await spellcheckedAt(page, "linne"), `${TAG} ${what}: the last line must be spellchecked`);
  assert(!(await spellcheckedAt(page, "inlinecodde")), `${TAG} ${what}: inline code must not be spellchecked`);
  assert(!(await spellcheckedAt(page, "fencedd")), `${TAG} ${what}: fenced code must not be spellchecked`);
  console.log(`${TAG} PASS (${what}): editor is spellchecked, code is not`);
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

    await setDocAndCaret(page, DOC.length);
    await assertSpellcheckLayout(page, "rendered, code collapsed");
    const widgets = await page.evaluate(() => ({
      checkboxes: document.querySelectorAll(".cm-content .cm-quki-checkbox").length,
      tables: document.querySelectorAll(".cm-content table").length,
    }));
    assert(widgets.checkboxes === 1, `${TAG} the task checkbox must still render, found ${widgets.checkboxes}`);
    assert(widgets.tables === 1, `${TAG} the table must still render, found ${widgets.tables}`);
    console.log(`${TAG} PASS: checkbox and table widgets still render`);

    await setDocAndCaret(page, DOC.indexOf("inlinecodde") + 2);
    await assertSpellcheckLayout(page, "rendered, inline code revealed");

    await setDocAndCaret(page, DOC.indexOf("fencedd") + 2);
    await assertSpellcheckLayout(page, "rendered, fenced code revealed");

    await page.evaluate(() => document.querySelector<HTMLButtonElement>("#btn-mode-toggle")!.click());
    await page.waitForTimeout(250);
    await setDocAndCaret(page, DOC.length);
    assert(await page.evaluate(() => document.querySelector(".cm-editor.cm-quki-plain-text") !== null), `${TAG} the mode toggle must have switched to plain-text mode`);
    await assertSpellcheckLayout(page, "plain-text mode");

    assert(pageErrors.length === 0, `${TAG} page errors: ${pageErrors.join("; ")}`);
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
