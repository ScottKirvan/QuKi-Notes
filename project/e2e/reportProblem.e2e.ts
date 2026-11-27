import { chromium, type BrowserContext, type Page, type Route } from "playwright";

import { assert, serveDist } from "./serveDist.ts";

const SENTINEL_TEXT = "SENTINEL-BODY-TEXT-report-5520";
const RELAY = "https://report.scottkirvan.com/report";
const ISSUE_URL = "https://github.com/ScottKirvan/QuKi-Notes/issues/777";
// Set only to take screenshots of the form (see the PR); the assertions do not depend on them.
const SHOT_DIR = process.env.QUKI_REPORT_SHOT_DIR;
const SHOT_SCHEME = process.env.QUKI_REPORT_SCHEME === "light" ? "light" : "dark";

interface Reply {
  status: number;
  body: unknown;
  /** Hold the answer until released, to look at the pending state. */
  hold?: Promise<void>;
  /** Fail the request like a network error. */
  abort?: boolean;
}

/**
 * Stands in for the report relay. Nothing in this file may reach the real one:
 * every request to its host is answered here, and the browser is also started
 * with the host mapped to a dead address, so a request that escaped the
 * interception would fail instead of filing an issue. `leaks` lists anything
 * that was not a POST to /report or its preflight; the test fails if it is not empty.
 */
async function mockRelay(context: BrowserContext, replies: () => Reply): Promise<{ posts: string[]; leaks: string[] }> {
  const state = { posts: [] as string[], leaks: [] as string[] };
  await context.route("https://report.scottkirvan.com/**", async (route: Route) => {
    const request = route.request();
    const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "content-type", "access-control-allow-methods": "POST" };
    if (request.url() !== RELAY) {
      state.leaks.push(`${request.method()} ${request.url()}`);
      await route.abort();
      return;
    }
    if (request.method() === "OPTIONS") {
      await route.fulfill({ status: 204, headers: cors });
      return;
    }
    if (request.method() !== "POST") {
      state.leaks.push(`${request.method()} ${request.url()}`);
      await route.abort();
      return;
    }
    state.posts.push(request.postData() ?? "");
    const reply = replies();
    if (reply.hold) await reply.hold;
    if (reply.abort) {
      await route.abort("failed");
      return;
    }
    await route.fulfill({ status: reply.status, headers: { ...cors, "content-type": "application/json" }, body: JSON.stringify(reply.body) });
  });
  return state;
}

async function newPage(browser: import("playwright").Browser, url: string, scheme: "dark" | "light" = "dark"): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, colorScheme: scheme });
  await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: url });
  // Nothing under github.com may be loaded for real either (Open on GitHub, the issue link).
  await context.route("https://github.com/**", (route) => route.fulfill({ status: 200, contentType: "text/html", body: "<title>mock</title>" }));
  const page = await context.newPage();
  await page.goto(url);
  await page.waitForSelector(".cm-content");
  return { context, page };
}

async function openForm(page: Page): Promise<void> {
  if (!(await page.locator("#view-settings").isVisible())) await page.click("#btn-settings");
  await page.locator(".view:not([hidden]) .report-problem-btn").click();
  await page.locator(".report-dialog").waitFor();
}

async function fillForm(page: Page, type: "bug" | "feature" | "feedback", title: string, description: string): Promise<void> {
  await page.selectOption(".report-type", type);
  await page.fill(".report-title-input", title);
  await page.fill(".report-description", description);
}

const visible = (page: Page, selector: string): Promise<boolean> => page.locator(selector).isVisible();

async function main(): Promise<void> {
  const { server, url } = await serveDist();
  console.log(`[e2e-report] serving dist/ at ${url}`);
  const browser = await chromium.launch({ args: ["--host-resolver-rules=MAP report.scottkirvan.com 127.0.0.1:9"] });
  try {
    // --- Scenario 1: the form, its fixed contents and the fallbacks. ---
    {
      const { context, page } = await newPage(browser, url, SHOT_SCHEME);
      const relay = await mockRelay(context, () => ({ status: 201, body: { url: ISSUE_URL, number: 777 } }));

      await page.click("#btn-settings");
      const row = page.locator(".view:not([hidden]) .report-problem-btn");
      assert((await row.count()) === 1, "Settings -> Diagnostics should have a Report a problem row");
      assert(
        (await page.locator(".view:not([hidden]) .settings-section:has(h2:text-is('Diagnostics')) .report-problem-btn").count()) === 1,
        "the row belongs in the Diagnostics section",
      );
      await row.click();
      await page.locator(".report-dialog").waitFor();

      const details = await page.inputValue(".report-details");
      assert(/^QuKi Notes \d+\.\d+\.\d+ \(branch .*, built .*\)\nPlatform: web$/.test(details), `Details should hold the version, build and platform, got: ${details}`);
      assert(await visible(page, ".report-title-input"), "title field");
      assert(await visible(page, ".report-description"), "description field");
      assert((await page.locator(".report-type option").allTextContents()).join("|") === "Bug|Feature request|Feedback", "the three types");
      assert(!(await visible(page, ".report-log")), "the log box must be hidden until the user ticks Include recent log");
      assert(!(await page.isChecked(".report-log-check")), "Include recent log must be off by default");

      const notice = (await page.textContent(".report-notice")) ?? "";
      assert(/public GitHub issue/.test(notice) && /anyone can read it/.test(notice), `the public notice must be stated plainly, got: ${notice}`);
      assert(/Email instead/.test(notice), "the notice should point to email for private matters");
      assert((await page.getAttribute(".report-privacy-link", "href")) === "https://www.scottkirvan.com/QuKi-Notes/privacy", "the notice links the privacy page");
      assert((await page.getAttribute(".report-privacy-link", "target")) === "_blank", "links open in the browser, never inside the app");

      for (const [selector, label] of [[".report-send", "Send"], [".report-github", "Open on GitHub"], [".report-copy", "Copy report"], [".report-email", "Email instead (private)"]] as const) {
        assert(await visible(page, selector), `${label} must always be offered`);
        assert((await page.textContent(selector)) === label, `${label} label`);
      }

      // Send needs a title and a description; nothing leaves the device without them.
      await page.click(".report-send");
      assert(/Add a title first/.test((await page.textContent(".report-message")) ?? ""), "an empty title must be refused");
      await page.fill(".report-title-input", "No description yet");
      await page.click(".report-send");
      assert(/Add a description first/.test((await page.textContent(".report-message")) ?? ""), "an empty description must be refused");
      assert(relay.posts.length === 0, "an incomplete report must not be sent");

      if (SHOT_DIR) {
        await page.screenshot({ path: `${SHOT_DIR}/report-form-top-${SHOT_SCHEME}.png` });
        await page.locator(".report-actions").scrollIntoViewIfNeeded();
        await page.screenshot({ path: `${SHOT_DIR}/report-form-actions-${SHOT_SCHEME}.png` });
      }

      // Escape closes it; nothing was sent.
      await page.keyboard.press("Escape");
      await page.locator(".report-dialog").waitFor({ state: "detached" });
      assert(relay.posts.length === 0, "closing must not send");

      // The Android Back button closes it before going back a screen.
      await openForm(page);
      await page.evaluate(() => (window as unknown as { qukiSystemBack: () => Promise<void> }).qukiSystemBack());
      await page.locator(".report-dialog").waitFor({ state: "detached" });
      assert(await visible(page, "#view-settings"), "Back should close the form and stay on Settings");
      assert(relay.leaks.length === 0 && relay.posts.length === 0, `no relay traffic expected, got ${relay.leaks.join(", ")}`);
      console.log("[e2e-report] PASS: the form opens from Settings -> Diagnostics with the notice, fallbacks and prefilled details; Escape and Back close it");
      await context.close();
    }

    // --- Scenario 2: Send, pending state, exact request, success link. ---
    {
      const { context, page } = await newPage(browser, url);
      let release: () => void = () => {};
      const hold = new Promise<void>((resolve) => (release = resolve));
      const relay = await mockRelay(context, () => ({ status: 201, body: { url: ISSUE_URL, number: 777 }, hold }));
      await openForm(page);
      await fillForm(page, "feedback", "  Test, please ignore  ", "Just checking the form.");
      await page.fill(".report-details", "QuKi Notes test build\nPlatform: web");

      await page.click(".report-send");
      await page.waitForFunction(() => (document.querySelector(".report-send") as HTMLButtonElement).disabled);
      assert((await page.textContent(".report-send")) === "Sending…", "Send should say it is sending");
      await page.click(".report-send", { force: true }).catch(() => {});
      await page.waitForTimeout(200);
      assert(relay.posts.length === 1, `one tap, one request while pending, got ${relay.posts.length}`);
      assert(await visible(page, ".report-github") && await visible(page, ".report-copy") && await visible(page, ".report-email"), "fallbacks stay available while pending");
      release();
      await page.locator(".report-issue-link").waitFor();

      assert(relay.posts.length === 1, "Send must not retry");
      const posted = JSON.parse(relay.posts[0]!) as Record<string, unknown>;
      assert(
        JSON.stringify(posted) ===
          JSON.stringify({
            app: "quki-notes",
            type: "feedback",
            title: "[GENERAL] Test, please ignore",
            body: "## Description\n\nJust checking the form.\n\n## Environment\n\nQuKi Notes test build\nPlatform: web",
          }),
        `the POST body must be exactly the reviewed report, got: ${relay.posts[0]}`,
      );
      assert((await page.getAttribute(".report-issue-link", "href")) === ISSUE_URL, "the success link is the issue");
      assert((await page.textContent(".report-issue-link")) === "issue #777", "the success link names the issue");
      assert((await page.getAttribute(".report-issue-link", "target")) === "_blank", "the link opens in the browser, not in the app");
      const popup = page.waitForEvent("popup");
      await page.click(".report-issue-link");
      const opened = await popup;
      assert(opened.url() === ISSUE_URL, `tapping the link opens the issue, got ${opened.url()}`);
      await opened.close();
      await page.click(".report-close");
      await page.locator(".report-dialog").waitFor({ state: "detached" });
      assert(relay.leaks.length === 0, `unexpected relay traffic: ${relay.leaks.join(", ")}`);
      console.log("[e2e-report] PASS: Send posts exactly the reviewed report once, is disabled while pending, and shows the issue link");
      await context.close();
    }

    // --- Scenario 3: every error class keeps the fallbacks, invalid_report names the field. ---
    {
      const { context, page } = await newPage(browser, url, SHOT_SCHEME);
      let reply: Reply = { status: 500, body: {} };
      const relay = await mockRelay(context, () => reply);
      await openForm(page);
      await fillForm(page, "bug", "Something broke", "Steps: 1, 2, 3");

      const cases: Array<[string, Reply, RegExp]> = [
        ["rate_limited", { status: 429, body: { error: "rate_limited" } }, /Too many reports/],
        ["upstream_error", { status: 502, body: { error: "upstream_error" } }, /GitHub didn't accept/],
        ["disabled", { status: 503, body: { error: "disabled" } }, /switched off/],
        ["not_configured", { status: 503, body: { error: "not_configured" } }, /switched off/],
        ["internal_error", { status: 500, body: { error: "internal_error" } }, /report service had a problem/],
        ["network failure", { status: 0, body: null, abort: true }, /Couldn't reach the report service/],
      ];
      for (const [name, r, pattern] of cases) {
        reply = r;
        const before = relay.posts.length;
        await page.click(".report-send");
        await page.waitForFunction(() => !(document.querySelector(".report-message") as HTMLElement).hidden);
        const text = (await page.textContent(".report-message")) ?? "";
        assert(pattern.test(text), `${name}: unexpected message: ${text}`);
        assert(/Open on GitHub, Copy report or Email/.test(text), `${name}: the message must offer the fallbacks, got: ${text}`);
        assert(relay.posts.length === before + 1, `${name}: exactly one request per tap`);
        assert(!(await page.locator(".report-send").isDisabled()), `${name}: Send must be usable again`);
        assert((await page.locator(".report-actions.report-actions-failed").count()) === 1, `${name}: the fallbacks are highlighted`);
        for (const selector of [".report-github", ".report-copy", ".report-email"]) assert(await visible(page, selector), `${name}: ${selector} must be offered`);
        await page.waitForTimeout(150);
        assert(relay.posts.length === before + 1, `${name}: no automatic retry`);
      }
      if (SHOT_DIR) {
        await page.locator(".report-message").scrollIntoViewIfNeeded();
        await page.screenshot({ path: `${SHOT_DIR}/report-form-failed-${SHOT_SCHEME}.png` });
      }

      reply = { status: 400, body: { error: "invalid_report", field: "title" } };
      await page.click(".report-send");
      await page.waitForFunction(() => /The title/.test(document.querySelector(".report-message")?.textContent ?? ""));
      reply = { status: 400, body: { error: "invalid_report", field: "body" } };
      await page.click(".report-send");
      await page.waitForFunction(() => /The report text/.test(document.querySelector(".report-message")?.textContent ?? ""));
      assert(relay.leaks.length === 0, `unexpected relay traffic: ${relay.leaks.join(", ")}`);
      console.log("[e2e-report] PASS: rate_limited, upstream_error, disabled, not_configured, internal_error and a network failure keep every fallback; invalid_report names the field");
      await context.close();
    }

    // --- Scenario 4: the failure log is opt-in, visible, editable, and holds no QuKi text. ---
    {
      const { context, page } = await newPage(browser, url);
      const relay = await mockRelay(context, () => ({ status: 201, body: { url: ISSUE_URL, number: 777 } }));
      await page.click(".cm-content");
      await page.keyboard.type(`my private note ${SENTINEL_TEXT}`);
      await page.evaluate((text) => {
        void Promise.reject(new RangeError(`Maximum call stack size exceeded ${text}`));
      }, "x");
      await page.waitForTimeout(300);

      await openForm(page);
      await fillForm(page, "bug", "Log test", "With a log");
      await page.click(".report-send");
      await page.locator(".report-issue-link").waitFor();
      assert(!relay.posts[0]!.includes("Failure log"), "the log must not be sent unless ticked");
      await page.click(".report-close");

      await openForm(page);
      await fillForm(page, "bug", "Log test", "With a log");
      await page.check(".report-log-check");
      await page.waitForFunction(() => (document.querySelector(".report-log") as HTMLTextAreaElement).value.length > 0);
      assert(await visible(page, ".report-log"), "ticking Include recent log shows the log");
      const log = await page.inputValue(".report-log");
      assert(/\[unhandled-rejection\] promise RangeError/.test(log), `the log should show the recorded failure, got:\n${log}`);
      assert(!log.includes(SENTINEL_TEXT), "the log must not contain QuKi text");
      assert(/personal details/.test((await page.textContent(".report-dialog")) ?? ""), "the personal-details warning must be shown");

      await page.fill(".report-log", "[edited] only this line goes");
      await page.click(".report-send");
      await page.locator(".report-issue-link").waitFor();
      const body = (JSON.parse(relay.posts[1]!) as { body: string }).body;
      assert(body.includes("```\n[edited] only this line goes\n```"), `the edited log is what is sent, got: ${body}`);
      assert(!body.includes("RangeError"), "the unedited log must not be sent");
      for (const post of relay.posts) assert(!post.includes(SENTINEL_TEXT), "no QuKi text may be in any report");
      assert(relay.leaks.length === 0, `unexpected relay traffic: ${relay.leaks.join(", ")}`);
      console.log("[e2e-report] PASS: the log is off by default, shown and editable when ticked, sent as edited, and holds no QuKi text");
      await context.close();
    }

    // --- Scenario 5: Open on GitHub, Copy report and Email instead. ---
    {
      const { context, page } = await newPage(browser, url);
      const relay = await mockRelay(context, () => ({ status: 201, body: { url: ISSUE_URL, number: 777 } }));
      await openForm(page);

      // Incomplete: Open on GitHub refuses, and opens nothing.
      let popups = 0;
      context.on("page", () => popups++);
      await page.click(".report-github");
      await page.waitForTimeout(300);
      assert(popups === 0, "Open on GitHub must refuse an incomplete report");
      assert(/Add a title first/.test((await page.textContent(".report-message")) ?? ""), "and say why");

      await fillForm(page, "feature", "Dark mode toggle", "Please add one & more");
      const popup = page.waitForEvent("popup");
      await page.click(".report-github");
      const opened = await popup;
      const target = new URL(opened.url());
      assert(target.origin + target.pathname === "https://github.com/ScottKirvan/QuKi-Notes/issues/new", `Open on GitHub goes to a new issue, got ${opened.url()}`);
      assert(target.searchParams.get("template") === "feature_request.md", "with the feature template");
      assert(target.searchParams.get("title") === "[FEATURE] Dark mode toggle", "and the title");
      assert((target.searchParams.get("body") ?? "").includes("Please add one & more"), "and the body");
      await opened.close();

      await page.click(".report-copy");
      await page.waitForFunction(() => /Report copied/.test(document.querySelector(".toast")?.textContent ?? ""));
      const clipboard = (await page.evaluate(() => navigator.clipboard.readText())).split("\r\n").join("\n");
      assert(clipboard.startsWith("[FEATURE] Dark mode toggle\n\n## Is your feature request related to a problem?\n\nPlease add one & more"), `Copy report puts title and body on the clipboard, got: ${clipboard}`);

      // The mail link is built when it is tapped; read it without leaving the page.
      await page.evaluate(() => document.querySelector(".report-email")!.addEventListener("click", (e) => e.preventDefault()));
      await page.click(".report-email");
      const mailto = (await page.getAttribute(".report-email", "href")) ?? "";
      assert(mailto.startsWith("mailto:quki-notes@skvfx.com?subject="), `Email goes to the project address, got ${mailto}`);
      assert(mailto.length <= 1800, "the mailto link stays short");
      const query = new URLSearchParams(mailto.slice(mailto.indexOf("?") + 1));
      assert(query.get("subject") === "[FEATURE] Dark mode toggle", "with the subject");
      assert((query.get("body") ?? "").startsWith("Please add one & more"), "and the body");
      assert(relay.posts.length === 0 && relay.leaks.length === 0, "the fallbacks send nothing to the relay");
      console.log("[e2e-report] PASS: Open on GitHub, Copy report and Email instead build the right link or text and send nothing to the relay");
      await context.close();
    }

    console.log("[e2e-report] ALL SCENARIOS PASSED");
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((err: unknown) => {
  console.error("[e2e-report] FAILED:", err);
  process.exit(1);
});
