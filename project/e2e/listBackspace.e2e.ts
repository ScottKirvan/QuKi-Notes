import { chromium, type Page } from "playwright";
import { assert, serveDist } from "./serveDist.ts";

type WindowWithQukiView = typeof window & {
  qukiView: {
    state: { doc: { toString(): string; length: number }; selection: { main: { head: number } } };
    dispatch: (spec: unknown) => void;
    focus: () => void;
  };
};

async function setDocAndCaret(page: Page, text: string, caret: number): Promise<void> {
  await page.evaluate(
    ({ text, caret }) => {
      const view = (window as WindowWithQukiView).qukiView;
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text }, selection: { anchor: caret } });
      view.focus();
    },
    { text, caret },
  );
  await page.waitForTimeout(100);
}

async function editorBody(page: Page): Promise<string> {
  return page.evaluate(() => (window as WindowWithQukiView).qukiView.state.doc.toString());
}

async function shownLine(page: Page, needle: string): Promise<{ text: string; checkboxes: number }> {
  const line = page.locator(".cm-content .cm-line", { hasText: needle });
  assert((await line.count()) === 1, `exactly one line should contain ${JSON.stringify(needle)}`);
  return { text: await line.innerText(), checkboxes: await line.locator(".cm-quki-checkbox").count() };
}

// Each step is [source line, line as shown]. Past a list marker the marker stays
// rendered (BEHAVIOR_SPEC.md §12 reveal rule 3), so a bullet shows as "•".
async function stepBack(page: Page, doc: string, needle: string, steps: [string, string][]): Promise<void> {
  await setDocAndCaret(page, doc, doc.indexOf(needle));
  for (const [source, shownText] of steps) {
    await page.keyboard.press("Backspace");
    await page.waitForTimeout(50);
    const body = await editorBody(page);
    const sourceLine = body.split("\n").find((l) => l.includes(needle));
    assert(sourceLine === source, `after Backspace the source line should be ${JSON.stringify(source)}, got ${JSON.stringify(sourceLine)}`);
    const shown = await shownLine(page, needle);
    assert(shown.checkboxes === 0, `a marker being edited should not draw a checkbox widget (source ${JSON.stringify(source)})`);
    assert(shown.text === shownText, `source ${JSON.stringify(source)} should show as ${JSON.stringify(shownText)}, got ${JSON.stringify(shown.text)}`);
  }
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    await setDocAndCaret(page, "intro\n\n- [ ] buy milk\n\nend", 0);
    assert((await shownLine(page, "buy milk")).checkboxes === 1, "with the caret elsewhere the task should render a checkbox");

    const taskDoc = "intro\n\n- [ ] buy milk\n\nend";
    await setDocAndCaret(page, taskDoc, taskDoc.indexOf("buy milk"));
    const before = await shownLine(page, "buy milk");
    assert(before.checkboxes === 0 && before.text === "- [ ] buy milk", `with the caret just after the checkbox its source should show, got ${JSON.stringify(before)}`);

    await stepBack(page, taskDoc, "buy milk", [
      ["- [ ]buy milk", "•[ ]buy milk"],
      ["- [ buy milk", "•[ buy milk"],
      ["- [buy milk", "•[buy milk"],
      ["- buy milk", "- buy milk"],
      ["-buy milk", "-buy milk"],
      ["buy milk", "buy milk"],
    ]);
    console.log("[e2e-listBackspace] PASS: Backspace steps back one character at a time through a rendered checkbox");

    await stepBack(page, "intro\n\n- parent\n\t- [x] child task\n\nend", "child task", [
      ["\t- [x]child task", "•[x]child task"],
      ["\t- [xchild task", "•[xchild task"],
      ["\t- [child task", "•[child task"],
    ]);
    console.log("[e2e-listBackspace] PASS: the same holds for an indented checked task");

    await stepBack(page, "intro\n\n- apple\n\nend", "apple", [["-apple", "-apple"], ["apple", "apple"]]);
    await stepBack(page, "intro\n\n1. one\n\nend", "one", [["1.one", "1.one"], ["1one", "1one"], ["one", "one"]]);
    console.log("[e2e-listBackspace] PASS: bullet and numbered markers step back one character at a time");

    await stepBack(page, "intro\n\n> > deeper\n\nend", "deeper", [
      ["> >deeper", "> >deeper"],
      ["> deeper", "> deeper"],
      [">deeper", ">deeper"],
      ["deeper", "deeper"],
    ]);
    console.log("[e2e-listBackspace] PASS: quote markers step back one character at a time");

    // execCommand("delete") is the browser's own backward delete in the DOM,
    // bypassing CodeMirror's keymap - the path an Android keyboard takes
    // without EditContext. An empty item keeps its marker drawn with the
    // caret after it, so the browser removes the whole widget in one go.
    for (const [item, steps] of [
      ["- [ ] ", ["- [ ]", "- [ ", "- ["]],
      ["- ", ["-", ""]],
      ["1. ", ["1.", "1"]],
    ] as const) {
      const doc = `intro\n\n${item}\n\nend`;
      await setDocAndCaret(page, doc, doc.indexOf("\n\nend"));
      assert((await page.locator(".cm-content .cm-quki-marker").count()) === 1, `the empty item ${JSON.stringify(item)} should draw its marker`);
      for (const expected of steps) {
        await page.evaluate(() => document.execCommand("delete"));
        await page.waitForTimeout(100);
        const line = (await editorBody(page)).split("\n")[2];
        assert(line === expected, `a DOM backward delete in ${JSON.stringify(item)} should leave ${JSON.stringify(expected)}, got ${JSON.stringify(line)}`);
      }
    }
    console.log("[e2e-listBackspace] PASS: a DOM backward delete over a drawn marker removes one character at a time");
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
