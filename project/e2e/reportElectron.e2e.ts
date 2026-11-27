import * as fs from "node:fs";
import * as http from "node:http";
import * as os from "node:os";
import * as path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

import { _electron as electron, type ElectronApplication, type Page } from "playwright";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const electronDir = path.join(__dirname, "..", "electron");
const electronMain = path.join(electronDir, "dist", "main.js");
const electronRequire = createRequire(path.join(electronDir, "package.json"));
const electronExecutablePath = electronRequire("electron") as unknown as string;

const ISSUE_URL = "https://github.com/ScottKirvan/QuKi-Notes/issues/778";

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
}

// See e2e/electron.e2e.ts for why ELECTRON_RUN_AS_NODE must not be inherited.
const baseChildEnv = { ...process.env, QUKI_ELECTRON_DIR: "" };
delete baseChildEnv.ELECTRON_RUN_AS_NODE;

interface Seen {
  method: string;
  url: string;
  headers: http.IncomingHttpHeaders;
  body: string;
}

/** A local stand-in for the report relay: Send must reach this, never report.scottkirvan.com. */
function startMockRelay(reply: () => { status: number; body: unknown }): Promise<{ server: http.Server; url: string; seen: Seen[] }> {
  const seen: Seen[] = [];
  const server = http.createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => chunks.push(c));
    req.on("end", () => {
      seen.push({ method: req.method ?? "", url: req.url ?? "", headers: req.headers, body: Buffer.concat(chunks).toString("utf8") });
      const r = reply();
      res.writeHead(r.status, { "content-type": "application/json" });
      res.end(JSON.stringify(r.body));
    });
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const address = server.address() as { port: number };
      resolve({ server, url: `http://127.0.0.1:${address.port}/report`, seen });
    });
  });
}

async function launch(storageDir: string, userDataDir: string, relayUrl: string): Promise<{ app: ElectronApplication; page: Page }> {
  const env: NodeJS.ProcessEnv = {
    ...baseChildEnv,
    QUKI_ELECTRON_DIR: storageDir,
    QUKI_ELECTRON_USERDATA_DIR: userDataDir,
    QUKI_TEST_REPORT_RELAY_URL: relayUrl,
  };
  // The real relay's host is mapped to a dead address, so even a request that ignored the test seam
  // would fail instead of filing an issue.
  const app = await electron.launch({
    executablePath: electronExecutablePath,
    args: ["--host-resolver-rules=MAP report.scottkirvan.com 127.0.0.1:9", electronMain],
    env,
  });
  const page = await app.firstWindow();
  await page.waitForSelector(".cm-content");
  return { app, page };
}

async function main(): Promise<void> {
  if (!fs.existsSync(electronMain)) {
    throw new Error(`${electronMain} not found - run "npm run build" in project/electron first`);
  }

  let next: { status: number; body: unknown } = { status: 201, body: { url: ISSUE_URL, number: 778 } };
  const relay = await startMockRelay(() => next);
  const storageDir = fs.mkdtempSync(path.join(os.tmpdir(), "quki-report-e2e-storage-"));
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "quki-report-e2e-userdata-"));

  const { app, page } = await launch(storageDir, userDataDir, relay.url);
  try {
    await page.click("#btn-settings");
    await page.locator(".view:not([hidden]) .report-problem-btn").click();
    await page.locator(".report-dialog").waitFor();
    const details = await page.inputValue(".report-details");
    assert(details.includes(`Platform: ${process.platform}`), `Details should name the platform, got: ${details}`);

    await page.selectOption(".report-type", "feedback");
    await page.fill(".report-title-input", "Test, please ignore");
    await page.fill(".report-description", "Checking the Electron sender.");
    await page.fill(".report-details", "QuKi Notes test build");
    await page.click(".report-send");
    await page.locator(".report-issue-link").waitFor();

    assert(relay.seen.length === 1, `exactly one request should reach the relay, got ${relay.seen.length}`);
    const request = relay.seen[0]!;
    assert(request.method === "POST" && request.url === "/report", `POST /report expected, got ${request.method} ${request.url}`);
    assert(request.headers["content-type"] === "application/json", `content-type must be application/json, got ${request.headers["content-type"]}`);
    assert(request.headers.origin === undefined, `the main process sends no Origin header, got ${request.headers.origin}`);
    assert(
      request.body ===
        JSON.stringify({
          app: "quki-notes",
          type: "feedback",
          title: "[GENERAL] Test, please ignore",
          body: "## Description\n\nChecking the Electron sender.\n\n## Environment\n\nQuKi Notes test build",
        }),
      `the POST body must be exactly the reviewed report, got: ${request.body}`,
    );
    assert((await page.getAttribute(".report-issue-link", "href")) === ISSUE_URL, "the success link is the issue");
    console.log("[e2e-report-electron] PASS: Send posts the reviewed report from the main process and shows the issue link");

    // An error reply and a dead relay both keep the fallbacks.
    await page.click(".report-close");
    await page.click("#view-settings .report-problem-btn");
    await page.locator(".report-dialog").waitFor();
    await page.fill(".report-title-input", "Second");
    await page.fill(".report-description", "Second report");
    next = { status: 429, body: { error: "rate_limited" } };
    await page.click(".report-send");
    await page.waitForFunction(() => /Too many reports/.test(document.querySelector(".report-message")?.textContent ?? ""));
    assert(relay.seen.length === 2, "one request per tap");
    for (const selector of [".report-github", ".report-copy", ".report-email"]) {
      assert(await page.locator(selector).isVisible(), `${selector} must stay offered after a failure`);
    }
    assert(!(await page.locator(".report-send").isDisabled()), "Send is usable again");

    await new Promise<void>((resolve) => relay.server.close(() => resolve()));
    await page.click(".report-send");
    await page.waitForFunction(() => /Couldn't reach the report service/.test(document.querySelector(".report-message")?.textContent ?? ""));
    console.log("[e2e-report-electron] PASS: an error reply and an unreachable relay both keep the fallbacks");
  } finally {
    await app.close();
    relay.server.close();
    fs.rmSync(storageDir, { recursive: true, force: true });
    fs.rmSync(userDataDir, { recursive: true, force: true });
  }
  console.log("[e2e-report-electron] ALL SCENARIOS PASSED");
}

main().catch((err: unknown) => {
  console.error("[e2e-report-electron] FAILED:", err);
  process.exit(1);
});
