import { chromium } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type QukiWindow = typeof window & { qukiSystemBack: () => Promise<void> };

const ABOUT = ".about-dialog";
const REPORT_DIALOG = ".report-dialog";

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    const page = await (await browser.newContext({ viewport: { width: 390, height: 780 } })).newPage();
    const relayRequests: string[] = [];
    await page.route("**://report.scottkirvan.com/**", async (route) => {
      relayRequests.push(route.request().url());
      await route.abort();
    });
    await page.goto(url);
    await page.waitForSelector(".cm-content");
    await page.waitForFunction(() => typeof (window as QukiWindow).qukiSystemBack === "function");

    await page.click("#btn-help");
    await page.locator(ABOUT).waitFor({ state: "visible" });
    await page.locator('.about-link-btn[data-row="report"]').click();
    await page.locator(REPORT_DIALOG).waitFor({ state: "visible" });
    assert(!(await page.locator(ABOUT).isVisible()), "About must close before the report form opens");
    const heading = await page.locator(`${REPORT_DIALOG} h2`).textContent();
    assert(heading === "Report a problem", `the report form must open from About, got heading "${heading}"`);
    console.log("[e2e-about-report] PASS: Report a problem in About closes About and opens the report form");

    const box = (await page.locator(REPORT_DIALOG).boundingBox())!;
    assert(box.x >= 0 && box.x + box.width <= 390, `the report form must fit the phone width, got ${JSON.stringify(box)}`);
    const overlayFixed = await page.locator(".report-overlay").evaluate((el) => getComputedStyle(el).position);
    assert(overlayFixed === "fixed", `the report form must sit in an overlay over the app (position: fixed), got ${overlayFixed}`);
    console.log("[e2e-about-report] PASS: the report form is a styled overlay dialog that fits the phone");

    await page.evaluate(() => (window as QukiWindow).qukiSystemBack());
    await page.locator(REPORT_DIALOG).waitFor({ state: "hidden" });
    assert(relayRequests.length === 0, `opening and closing the form must not contact the relay, saw ${relayRequests.join(", ")}`);
    console.log("[e2e-about-report] PASS: Back closes the form and nothing was sent");
    console.log("[e2e-about-report] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((error) => {
  console.error("[e2e-about-report] FAILED:", error);
  process.exit(1);
});
