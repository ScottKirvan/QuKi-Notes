import { chromium } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-search-snippet] serving dist/ at ${url}`);
  const browser = await chromium.launch();

  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(url);
    await page.waitForSelector(".cm-content");

    // Given a QuKi whose match is not on its first line, inside bold markup
    await page.click(".cm-content");
    await page.keyboard.press("Control+A");
    await page.keyboard.type("Weekend plans\nRemember to buy **ripe bananas** for the cake");
    await page.waitForTimeout(2500); // 2s auto-save debounce + margin

    const list = page.locator("#view-list");
    await page.click("#btn-quki-list");
    await list.locator(".list-row").first().waitFor({ timeout: 5000 });
    const preview = list.locator(".list-row-preview").first();
    await page.waitForFunction(() => document.querySelector("#view-list .list-row-preview")?.textContent === "Weekend plans");

    // When the user searches, in different case from the body
    await list.locator(".search-input").fill("BANANAS");
    await list.locator(".search-hit").first().waitFor({ timeout: 5000 });

    // Then the row keeps its first line as a title, and below it shows the
    // matching line, markers stripped, with the match highlighted
    await page.waitForFunction(() => document.querySelector("#view-list .list-row-preview")?.textContent === "Weekend plans");
    const snippetLine = list.locator(".list-row-snippet").first();
    const text = await snippetLine.textContent();
    assert(text === "Remember to buy ripe bananas for the cake", `expected the matching line as the snippet, got "${text}"`);
    const hits = await list.locator(".search-hit").allTextContents();
    assert(JSON.stringify(hits) === JSON.stringify(["bananas"]), `expected one highlighted "bananas", got ${JSON.stringify(hits)}`);
    const hitBackground = await list.locator(".search-hit").first().evaluate((el) => getComputedStyle(el).backgroundColor);
    const expected = await page.evaluate(() => {
      const probe = document.createElement("div");
      probe.style.background = "var(--text-highlight-bg)";
      document.body.append(probe);
      const resolved = getComputedStyle(probe).backgroundColor;
      probe.remove();
      return resolved;
    });
    assert(expected !== "rgba(0, 0, 0, 0)", "--text-highlight-bg should have a default on the body theme class");
    assert(hitBackground === expected, `highlight background should be --text-highlight-bg (${expected}), got ${hitBackground}`);
    const snippetHits = await snippetLine.locator(".search-hit").count();
    assert(snippetHits === 1, `the highlight should be in the matching line under the title, got ${snippetHits}`);
    console.log(`[e2e-search-snippet] PASS: title "Weekend plans", snippet "${text}" with "${hits[0]}" highlighted in ${hitBackground}`);

    // When the match is in the first line, the row shows just that line, highlighted
    await list.locator(".search-input").fill("weekend");
    await list.locator(".list-row-preview .search-hit").first().waitFor({ timeout: 5000 });
    const firstLineText = await preview.textContent();
    assert(firstLineText === "Weekend plans", `expected the first line alone, got "${firstLineText}"`);
    const firstLineHits = await list.locator(".list-row-preview .search-hit").allTextContents();
    assert(JSON.stringify(firstLineHits) === JSON.stringify(["Weekend"]), `expected "Weekend" highlighted, got ${JSON.stringify(firstLineHits)}`);
    assert((await list.locator(".list-row-snippet").count()) === 0, "a first-line match should not add a second line");
    console.log("[e2e-search-snippet] PASS: a first-line match shows only that line, highlighted");

    // When the search box is cleared, rows go back to the normal preview
    await list.locator(".search-input").fill("");
    await page.waitForFunction(
      () =>
        document.querySelector("#view-list .list-row-preview")?.textContent === "Weekend plans" &&
        document.querySelectorAll("#view-list .search-hit").length === 0,
      undefined,
      { timeout: 5000 },
    );
    assert((await list.locator(".list-row-snippet").count()) === 0, "rows should not keep the snippet class once the search box is empty");
    console.log("[e2e-search-snippet] PASS: clearing the search restores the normal preview");

    await context.close();
    console.log("[e2e-search-snippet] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-search-snippet] FAILED:", err);
    process.exit(1);
  });
