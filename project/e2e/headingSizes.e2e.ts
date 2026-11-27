import { chromium, type Browser } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

type Scheme = "light" | "dark";

const DOC = ["# H1 text", "## H2 text", "### H3 text", "#### H4 text", "##### H5 text", "###### H6 text", "plain body text", ""].join("\n");

async function runScheme(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-headingSizes ${scheme}]`;
  const context = await browser.newContext({ viewport: { width: 900, height: 900 }, colorScheme: scheme });
  const page = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await page.evaluate((doc) => {
    const view = (window as unknown as { qukiView: { state: { doc: { length: number } }; dispatch: (spec: unknown) => void } }).qukiView;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: doc }, selection: { anchor: doc.length } });
  }, DOC);
  await page.waitForTimeout(250);

  const measured = await page.evaluate(() => {
    const read = (needle: string): { size: number; weight: number; lineHeight: number } => {
      const line = [...document.querySelectorAll<HTMLElement>(".cm-line")].find((l) => l.textContent?.includes(needle));
      if (!line) throw new Error(`no line containing ${needle}`);
      const style = getComputedStyle(line.querySelector<HTMLElement>(".cm-quki-heading") ?? line);
      return { size: parseFloat(style.fontSize), weight: Number(style.fontWeight), lineHeight: line.getBoundingClientRect().height };
    };
    return { sizes: [1, 2, 3, 4, 5, 6].map((n) => read(`H${n} text`)), body: read("plain body text") };
  });

  const sizes = measured.sizes.map((m) => m.size);
  for (let i = 1; i < 6; i++) {
    assert(sizes[i - 1]! > sizes[i]!, `${tag} h${i} (${sizes[i - 1]}px) should be larger than h${i + 1} (${sizes[i]}px): ${JSON.stringify(sizes)}`);
  }
  const h6 = measured.sizes[5]!;
  assert(h6.size !== measured.body.size || h6.weight !== measured.body.weight, `${tag} h6 should differ from body text, got ${JSON.stringify({ h6, body: measured.body })}`);
  const heights = measured.sizes.map((m) => m.lineHeight);
  for (let i = 1; i < 6; i++) assert(heights[i - 1]! >= heights[i]!, `${tag} line heights should not grow from h${i} to h${i + 1}: ${JSON.stringify(heights)}`);
  console.log(`${tag} PASS: sizes ${sizes.join(" > ")}px, body ${measured.body.size}px, h6 weight ${h6.weight}`);

  assert(pageErrors.length === 0, `page errors: ${pageErrors.join("; ")}`);
  await context.close();
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  const browser = await chromium.launch();
  try {
    for (const scheme of ["dark", "light"] as const) await runScheme(browser, url, scheme);
    console.log("[e2e-headingSizes] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-headingSizes] FAILED:", err);
    process.exit(1);
  });
