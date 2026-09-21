import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type Browser, type Page } from "playwright";

import { assert, runHangScenarios, type HangEnvironment } from "./hangSupport.ts";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.join(__dirname, "..", "dist");

const CONTENT_TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
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
        const ext = path.extname(filePath);
        res.writeHead(200, { "content-type": CONTENT_TYPES[ext] ?? "application/octet-stream" });
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

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-hangingIndent:chromium] serving dist/ at ${url}`);

  const browser: Browser = await chromium.launch();
  const env: HangEnvironment = {
    name: "chromium",
    async open(scheme, width, height) {
      const context = await browser.newContext({ viewport: { width, height }, colorScheme: scheme });
      const page = await context.newPage();
      await page.goto(url);
      await page.waitForSelector(".cm-content");
      return {
        page,
        resize: (w, h) => page.setViewportSize({ width: w, height: h }),
        close: () => context.close(),
      };
    },
    async assertEngine(page: Page) {
      const version = await page.evaluate(() => navigator.userAgent);
      assert(version.includes("Chrome/"), `expected a Chromium engine, got ${version}`);
      return version;
    },
  };
  try {
    await runHangScenarios(env);
  } finally {
    await browser.close();
    server.close();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err: unknown) => {
    console.error("[e2e-hangingIndent:chromium] FAILED:", err);
    process.exit(1);
  });
