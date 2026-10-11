import { chromium, type Page } from "playwright";

import { assert, clickFirstLine, serveDist } from "./serveDist.ts";

const PLACEHOLDER = "…";

async function startRecording(page: Page): Promise<void> {
  await page.evaluate(() => {
    const states: string[] = [];
    const w = window as unknown as { __listStates: string[] | null };
    w.__listStates = states;
    const snapshot = (): void => {
      if (w.__listStates !== states) return;
      const rows = document.querySelectorAll("#view-list .list-row").length;
      const previews = Array.from(document.querySelectorAll("#view-list .list-row-preview")).map((p) => p.textContent);
      const state = JSON.stringify({ rows, previews });
      if (states[states.length - 1] !== state) states.push(state);
    };
    new MutationObserver(snapshot).observe(document.body, { subtree: true, childList: true, characterData: true });
    const tick = (): void => {
      snapshot();
      if (w.__listStates === states) requestAnimationFrame(tick);
    };
    tick();
  });
}

async function stopRecording(page: Page): Promise<Array<{ rows: number; previews: string[] }>> {
  const states = await page.evaluate(() => {
    const w = window as unknown as { __listStates: string[] | null };
    const recorded = w.__listStates ?? [];
    w.__listStates = null;
    return recorded;
  });
  return states.map((s) => JSON.parse(s) as { rows: number; previews: string[] });
}

async function openListRecording(page: Page, expectedFirstPreview: string, expectedRows: number) {
  await startRecording(page);
  await page.click("#btn-quki-list");
  await page.waitForFunction(
    ([first, rows]) => {
      const previews = Array.from(document.querySelectorAll("#view-list .list-row-preview")).map((p) => p.textContent);
      return previews.length === rows && previews[0] === first && !previews.includes("…");
    },
    [expectedFirstPreview, expectedRows] as const,
    { timeout: 10000 },
  );
  await page.waitForTimeout(300);
  return stopRecording(page);
}

function assertNoFlicker(label: string, states: Array<{ rows: number; previews: string[] }>): void {
  const describe = JSON.stringify(states);
  for (const state of states) {
    assert(state.rows > 0, `${label}: the list went blank while opening: ${describe}`);
    assert(!state.previews.includes(PLACEHOLDER), `${label}: a row showed a placeholder while opening: ${describe}`);
  }
  assert(states.length <= 2, `${label}: the rows changed more than once while opening: ${describe}`);
}

const { server, url } = await serveDist();
const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  await page.goto(url);
  await page.waitForSelector(".cm-content");

  const texts = ["Flicker alpha", "Flicker bravo", "Flicker charlie"];
  for (const [i, text] of texts.entries()) {
    await clickFirstLine(page);
    await page.keyboard.type(text);
    await page.click("#btn-quki-list");
    await page.waitForFunction(
      ([first, rows]) => {
        const previews = Array.from(document.querySelectorAll("#view-list .list-row-preview")).map((p) => p.textContent);
        return previews.length === rows && previews[0] === first && !previews.includes("…");
      },
      [text, i + 1] as const,
      { timeout: 10000 },
    );
    await page.locator("#view-list .new-btn").click();
    await page.waitForSelector("#view-list", { state: "hidden" });
  }

  const reopened = await openListRecording(page, "Flicker charlie", 3);
  assertNoFlicker("reopening the list", reopened);
  assert(reopened.length === 1, `reopening an unchanged list should not change its rows: ${JSON.stringify(reopened)}`);
  console.log("[e2e-listOpenFlicker] PASS: reopening the list keeps its rows on screen without a blank or placeholder");

  await page.locator("#view-list .new-btn").click();
  await page.waitForSelector("#view-list", { state: "hidden" });
  await clickFirstLine(page);
  await page.keyboard.type("Flicker delta");
  const afterTyping = await openListRecording(page, "Flicker delta", 4);
  assertNoFlicker("opening the list right after typing", afterTyping);
  const last = afterTyping[afterTyping.length - 1]!;
  assert(
    JSON.stringify(last.previews) === JSON.stringify(["Flicker delta", "Flicker charlie", "Flicker bravo", "Flicker alpha"]),
    `the list should end on the fresh rows, got ${JSON.stringify(last)}`,
  );
  console.log("[e2e-listOpenFlicker] PASS: opening the list after typing swaps straight to the fresh rows");
} finally {
  await browser.close();
  server.close();
}
