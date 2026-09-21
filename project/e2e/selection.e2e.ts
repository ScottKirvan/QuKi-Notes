import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type Browser, type Page } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.join(__dirname, "..", "dist");
const screenshotDir = process.env["QUKI_E2E_SCREENSHOTS"];

const CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".png": "image/png",
  ".map": "application/json; charset=utf-8",
};

function serveDist(): Promise<{ server: http.Server; url: string }> {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(distDir)) {
      reject(new Error(`dist/ not found at ${distDir} - run "npm run build" first`));
      return;
    }
    const server = http.createServer((req, res) => {
      const reqPath = (req.url ?? "/").split("?")[0]!;
      const filePath = path.join(distDir, reqPath === "/" ? "index.html" : reqPath);
      if (!filePath.startsWith(distDir)) {
        res.writeHead(403).end();
        return;
      }
      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(404).end();
          return;
        }
        res.writeHead(200, { "content-type": CONTENT_TYPES[path.extname(filePath)] ?? "application/octet-stream" });
        res.end(data);
      });
    });
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (address === null || typeof address === "string") {
        reject(new Error("failed to bind server"));
        return;
      }
      resolve({ server, url: `http://127.0.0.1:${address.port}` });
    });
  });
}

type Scheme = "light" | "dark";
type Rgb = [number, number, number];
type Box = { x: number; y: number; width: number; height: number };
type Sample = { dominant: Rgb; ink: Rgb };

type QukiWindow = typeof window & {
  qukiView: {
    state: { doc: { line(n: number): { from: number; to: number }; length: number; sliceString(from: number, to: number): string } };
    dispatch: (spec: unknown) => void;
    focus: () => void;
    coordsAtPos: (pos: number, side?: number) => { left: number; right: number; top: number; bottom: number } | null;
    contentDOM: HTMLElement;
  };
};

// Line 1 carries the caret in the first scenarios, line 3 is a list item, line 4 a quote,
// line 5 has an inline code span, line 6 is plain.
const DOC = ["plain caret line here", "second line other words", "- list item words", "> quote line words", "has `code span` inline", "last line words"].join("\n");

const MIN_DISTANCE_FROM_PAGE = 40;
const MIN_TEXT_CONTRAST = 4.5;
const MIN_MUTED_TEXT_CONTRAST = 3;
const BLEND_TOLERANCE = 3;

const failures: string[] = [];

function check(condition: boolean, message: string): void {
  if (!condition) failures.push(message);
}

function parseColour(css: string): { rgb: Rgb; alpha: number } {
  const match = css.match(/rgba?\(([^)]+)\)/);
  if (match === null) throw new Error(`not a colour: ${css}`);
  const parts = match[1]!.split(",").map((p) => Number(p.trim()));
  return { rgb: [parts[0]!, parts[1]!, parts[2]!], alpha: parts[3] ?? 1 };
}

function blend(over: { rgb: Rgb; alpha: number }, under: Rgb): Rgb {
  return [0, 1, 2].map((i) => Math.round(over.rgb[i]! * over.alpha + under[i]! * (1 - over.alpha))) as Rgb;
}

function distance(a: Rgb, b: Rgb): number {
  return Math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2);
}

function luminance(c: Rgb): number {
  const [r, g, b] = c.map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  }) as Rgb;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a: Rgb, b: Rgb): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}

const fmt = (c: Rgb): string => `rgb(${c.join(", ")})`;

async function sampleBoxes(scratch: Page, png: Buffer, boxes: Box[]): Promise<Sample[]> {
  return scratch.evaluate(
    async ({ base64, boxes }) => {
      const blob = await (await fetch(`data:image/png;base64,${base64}`)).blob();
      const bitmap = await createImageBitmap(blob);
      const canvas = document.createElement("canvas");
      canvas.width = bitmap.width;
      canvas.height = bitmap.height;
      const ctx = canvas.getContext("2d")!;
      ctx.drawImage(bitmap, 0, 0);
      return boxes.map((box) => {
        const x = Math.max(0, Math.floor(box.x));
        const y = Math.max(0, Math.floor(box.y));
        const w = Math.max(1, Math.floor(box.width));
        const h = Math.max(1, Math.floor(box.height));
        const data = ctx.getImageData(x, y, w, h).data;
        const counts = new Map<number, number>();
        for (let i = 0; i < data.length; i += 4) {
          const key = (data[i]! << 16) | (data[i + 1]! << 8) | data[i + 2]!;
          counts.set(key, (counts.get(key) ?? 0) + 1);
        }
        let dominantKey = 0;
        let best = -1;
        for (const [key, count] of counts) {
          if (count > best) {
            best = count;
            dominantKey = key;
          }
        }
        const dominant: [number, number, number] = [(dominantKey >> 16) & 255, (dominantKey >> 8) & 255, dominantKey & 255];
        let ink: [number, number, number] = dominant;
        let farthest = -1;
        for (let i = 0; i < data.length; i += 4) {
          const d = (data[i]! - dominant[0]) ** 2 + (data[i + 1]! - dominant[1]) ** 2 + (data[i + 2]! - dominant[2]) ** 2;
          if (d > farthest) {
            farthest = d;
            ink = [data[i]!, data[i + 1]!, data[i + 2]!];
          }
        }
        return { dominant, ink };
      });
    },
    { base64: png.toString("base64"), boxes },
  );
}

async function probe(page: Page, names: string[]): Promise<Record<string, string>> {
  return page.evaluate((varNames) => {
    const el = document.createElement("div");
    document.body.appendChild(el);
    const result: Record<string, string> = {};
    for (const name of varNames) {
      el.style.setProperty("background-color", "");
      el.style.setProperty("background-color", `var(${name})`);
      result[name] = getComputedStyle(el).backgroundColor;
    }
    el.remove();
    return result;
  }, names);
}

async function select(page: Page, from: number, to: number): Promise<void> {
  await page.evaluate(
    ({ from, to }) => {
      const view = (window as QukiWindow).qukiView;
      view.focus();
      view.dispatch({ selection: { anchor: from, head: to } });
    },
    { from, to },
  );
  await page.waitForTimeout(150);
}

async function offsetOf(page: Page, line: number, text: string): Promise<{ from: number; to: number }> {
  return page.evaluate(
    ({ line, text }) => {
      const view = (window as QukiWindow).qukiView;
      const info = view.state.doc.line(line);
      const content = view.state.doc.sliceString(info.from, info.to);
      const at = content.indexOf(text);
      if (at < 0) throw new Error(`"${text}" is not on line ${line}: ${content}`);
      return { from: info.from + at, to: info.from + at + text.length };
    },
    { line, text },
  );
}

async function lineSpan(page: Page, line: number, clipFrom: number, clipTo: number): Promise<Box> {
  return page.evaluate(
    ({ line, clipFrom, clipTo }) => {
      const view = (window as QukiWindow).qukiView;
      const info = view.state.doc.line(line);
      const start = view.coordsAtPos(Math.max(info.from, clipFrom), 1);
      const end = view.coordsAtPos(Math.min(info.to, clipTo), -1);
      if (start === null || end === null) throw new Error(`line ${line} is not rendered`);
      const height = start.bottom - start.top;
      return { x: start.left + 3, y: start.top + height * 0.2, width: end.right - start.left - 6, height: height * 0.6 };
    },
    { line, clipFrom, clipTo },
  );
}

async function shot(page: Page, scheme: Scheme, name: string): Promise<Buffer> {
  const png = await page.screenshot();
  if (screenshotDir !== undefined) {
    fs.mkdirSync(screenshotDir, { recursive: true });
    fs.writeFileSync(path.join(screenshotDir, `selection-${scheme}-${name}.png`), png);
  }
  return png;
}

async function runScenario(browser: Browser, url: string, scheme: Scheme): Promise<void> {
  const tag = `[e2e-selection:${scheme}]`;
  failures.length = 0;
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 420, height: 700 } });
  const page = await context.newPage();
  const scratch = await context.newPage();
  const pageErrors: string[] = [];
  page.on("pageerror", (err) => pageErrors.push(String(err)));
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  await page.evaluate((text) => {
    const view = (window as QukiWindow).qukiView;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
  }, DOC);

  const colours = await probe(page, ["--background-primary", "--text-selection", "--text-normal"]);
  const pageBg = parseColour(colours["--background-primary"]!).rgb;
  const selectionBlend = blend(parseColour(colours["--text-selection"]!), pageBg);
  console.log(`${tag} page background ${fmt(pageBg)}, --text-selection ${colours["--text-selection"]}, expected blend ${fmt(selectionBlend)}, blend-vs-page distance ${distance(selectionBlend, pageBg).toFixed(1)}, contrast ${contrast(selectionBlend, pageBg).toFixed(2)}:1`);

  async function checkSelection(label: string, boxes: Box[], png: Buffer, options: { muted?: number[]; noText?: boolean } = {}): Promise<void> {
    const samples = await sampleBoxes(scratch, png, boxes);
    samples.forEach((s, i) => {
      const away = distance(s.dominant, pageBg);
      const off = distance(s.dominant, selectionBlend);
      console.log(`${tag}   ${label} [${i}]: selection area is ${fmt(s.dominant)} (page ${fmt(pageBg)}, ${away.toFixed(1)} away; expected blend ${fmt(selectionBlend)}, ${off.toFixed(1)} away), ink ${fmt(s.ink)} contrast ${contrast(s.ink, s.dominant).toFixed(2)}:1`);
      check(away >= MIN_DISTANCE_FROM_PAGE, `${label} [${i}]: the selected area ${fmt(s.dominant)} is not visibly different from the page ${fmt(pageBg)} (${away.toFixed(1)} < ${MIN_DISTANCE_FROM_PAGE})`);
      check(off <= BLEND_TOLERANCE * Math.sqrt(3), `${label} [${i}]: the selected area ${fmt(s.dominant)} is not --text-selection over the page (${fmt(selectionBlend)})`);
      if (options.noText) return;
      const needed = options.muted?.includes(i) ? MIN_MUTED_TEXT_CONTRAST : MIN_TEXT_CONTRAST;
      check(contrast(s.ink, s.dominant) >= needed, `${label} [${i}]: the text ${fmt(s.ink)} is not readable on ${fmt(s.dominant)} (${contrast(s.ink, s.dominant).toFixed(2)}:1 < ${needed}:1)`);
    });
  }

  async function checkCaretLineIsPlain(label: string, line: number): Promise<void> {
    const active = await page.evaluate(() => document.querySelectorAll(".cm-activeLine").length);
    check(active === 0, `${label}: ${active} element(s) carry .cm-activeLine`);
    const lineBg = await page.evaluate(
      (line) => {
        const view = (window as QukiWindow).qukiView;
        const pos = view.state.doc.line(line).from;
        const rect = view.coordsAtPos(pos, 1)!;
        const el = document.elementsFromPoint(rect.left + 4, (rect.top + rect.bottom) / 2).find((e) => e.classList.contains("cm-line"));
        return el === undefined ? null : getComputedStyle(el).backgroundColor;
      },
      line,
    );
    check(lineBg !== null && parseColour(lineBg).alpha === 0, `${label}: the caret's line has background ${lineBg}`);
    const png = await shot(page, scheme, label.replace(/\W+/g, "-"));
    const box = await page.evaluate(
      (line) => {
        const view = (window as QukiWindow).qukiView;
        const info = view.state.doc.line(line);
        const end = view.coordsAtPos(info.to, -1)!;
        const content = view.contentDOM.getBoundingClientRect();
        return { x: end.right + 24, y: end.top + 3, width: content.right - end.right - 40, height: end.bottom - end.top - 6 };
      },
      line,
    );
    const [sample] = await sampleBoxes(scratch, png, [box]);
    check(distance(sample!.dominant, pageBg) === 0, `${label}: beside the text the caret's line is ${fmt(sample!.dominant)}, not the page ${fmt(pageBg)}`);
    console.log(`${tag}   ${label}: right of the caret's line text is ${fmt(sample!.dominant)} (page ${fmt(pageBg)})`);
  }

  // 1. a word on the caret's line
  {
    const word = await offsetOf(page, 1, "caret");
    await select(page, word.from, word.to);
    await checkCaretLineIsPlain("caret line", 1);
    const png = await shot(page, scheme, "caret-line-word");
    await checkSelection("word on the caret's line", [await lineSpan(page, 1, word.from, word.to)], png);
  }

  // 2. a word on another line
  {
    const word = await offsetOf(page, 2, "other");
    await select(page, word.from, word.to);
    await checkCaretLineIsPlain("second line", 2);
    const png = await shot(page, scheme, "second-line-word");
    await checkSelection("word on a second line", [await lineSpan(page, 2, word.from, word.to)], png);
  }

  // 3. one selection across every kind of line
  {
    const first = await offsetOf(page, 1, "caret");
    const last = await offsetOf(page, 6, "words");
    await select(page, first.from, last.to);
    const png = await shot(page, scheme, "across-lines");
    const boxes: Box[] = [];
    for (const line of [1, 2, 3, 4, 5, 6]) boxes.push(await lineSpan(page, line, first.from, last.to));
    await checkSelection("across lines (1 plain, 2 plain, 3 list item, 4 quote, 5 code, 6 plain)", boxes, png, { muted: [3] });
    const code = await page.evaluate(() => {
      const el = document.querySelector(".cm-quki-code");
      if (el === null) return null;
      const r = el.getBoundingClientRect();
      const middle = { y: r.top + r.height * 0.4, height: r.height * 0.2 };
      return {
        inside: { x: r.left + 2, y: r.top + r.height * 0.15, width: r.width - 4, height: r.height * 0.7 },
        leftPadding: { x: Math.floor(r.left) + 1, width: 1, ...middle },
        rightPadding: { x: Math.ceil(r.right) - 2, width: 1, ...middle },
      };
    });
    check(code !== null, "across lines: no .cm-quki-code element rendered for the code span");
    if (code !== null) {
      await checkSelection("across lines, inside the code span's own box", [code.inside], png);
      await checkSelection("across lines, the code span's left padding", [code.leftPadding], png, { noText: true });
      await checkSelection("across lines, the code span's right padding", [code.rightPadding], png, { noText: true });
    }
  }

  // 4. inside a list item whose marker is revealed
  {
    const word = await offsetOf(page, 3, "item");
    await select(page, word.from - 2, word.to);
    const png = await shot(page, scheme, "revealed-list-marker");
    await checkSelection("revealed list marker and text", [await lineSpan(page, 3, word.from - 2, word.to)], png);
  }

  // 5. inside a quote line
  {
    const word = await offsetOf(page, 4, "quote");
    await select(page, word.from, word.to);
    const png = await shot(page, scheme, "quote-word");
    await checkSelection("word in a quote line", [await lineSpan(page, 4, word.from, word.to)], png, { muted: [0] });
  }

  // 6. inside an inline code span while the caret is elsewhere on that line
  {
    const word = await offsetOf(page, 5, "code span");
    await select(page, word.from, word.to);
    const png = await shot(page, scheme, "code-span");
    await checkSelection("inline code span", [await lineSpan(page, 5, word.from, word.to)], png);
  }

  // 7. a selection that ends partway through a collapsed code span
  {
    const code = await offsetOf(page, 5, "code span");
    const lineStart = (await offsetOf(page, 5, "has")).from;
    const cut = code.from + 4;
    await select(page, lineStart, cut);
    const png = await shot(page, scheme, "code-span-partial");
    await checkSelection("selected part of a partly selected code span", [await lineSpan(page, 5, code.from, cut)], png);
    const chipColour = parseColour((await probe(page, ["--code-background"]))["--code-background"]!).rgb;
    const [rest] = await sampleBoxes(scratch, png, [await lineSpan(page, 5, cut + 1, code.to)]);
    console.log(`${tag}   unselected rest of the code span is ${fmt(rest!.dominant)} (--code-background ${fmt(chipColour)})`);
    check(distance(rest!.dominant, chipColour) <= BLEND_TOLERANCE, `the unselected rest of the code span is ${fmt(rest!.dominant)}, not its own --code-background ${fmt(chipColour)}`);
  }

  if (pageErrors.length > 0) failures.push(`page errors: ${pageErrors.join("; ")}`);
  await context.close();
  if (failures.length > 0) throw new Error(`${tag} ${failures.length} check(s) failed:\n  ${failures.join("\n  ")}`);
  console.log(`${tag} PASS: no active-line background, and selections are visibly --text-selection with readable text on the caret's line, other lines, across lines, a list item, a revealed marker, a quote and a code span`);
}

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-selection] serving dist/ at ${url}`);
  const browser = await chromium.launch();
  const errors: string[] = [];
  try {
    for (const scheme of ["light", "dark"] as const) {
      try {
        await runScenario(browser, url, scheme);
      } catch (err) {
        errors.push(err instanceof Error ? err.message : String(err));
        console.error(errors[errors.length - 1]);
      }
    }
    if (errors.length > 0) throw new Error("selection checks failed");
    console.log("[e2e-selection] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-selection] FAILED:", err);
    process.exit(1);
  });
