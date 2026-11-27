import { describe, expect, it, vi } from "vitest";

import {
  MAILTO_MAX,
  RELAY_BODY_MAX,
  RELAY_REQUEST_MAX_BYTES,
  RELAY_UNREACHABLE,
  RELAY_URL,
  REPORT_EMAIL,
  REPORT_URL_MAX,
  TITLE_MAX,
  readRelayResponse,
  relayRequest,
  reportBody,
  reportIssueUrl,
  reportMailtoUrl,
  reportText,
  reportTitle,
  sendReport,
  tailLines,
  type ReportInput,
} from "./reportProblem";

const input: ReportInput = { type: "bug", title: "It crashes", description: "When I tap save", details: "QuKi Notes 0.27.0\nPlatform: web" };

describe("reportTitle", () => {
  it("prefixes by type, matching the repo's issue templates", () => {
    expect(reportTitle("bug", "x")).toBe("[BUG] x");
    expect(reportTitle("feature", "x")).toBe("[FEATURE] x");
    expect(reportTitle("feedback", "x")).toBe("[GENERAL] x");
  });

  it("keeps one line, collapses whitespace and falls back to a default", () => {
    expect(reportTitle("bug", "  one \t two \n second line ")).toBe("[BUG] one two");
    expect(reportTitle("bug", "  ")).toBe("[BUG] Problem report");
    expect(reportTitle("feature", "")).toBe("[FEATURE] Feature request");
    expect(reportTitle("feedback", "")).toBe("[GENERAL] Feedback");
  });

  it("never exceeds the relay's 256 characters, prefix included", () => {
    const long = reportTitle("feature", "a".repeat(1000));
    expect(long.length).toBe(TITLE_MAX);
    expect(long.endsWith("…")).toBe(true);
    expect(reportTitle("bug", "b".repeat(TITLE_MAX - 6)).length).toBe(TITLE_MAX);
  });
});

describe("reportBody", () => {
  it("follows the bug template shape, and adds the footer only when asked", () => {
    const body = reportBody(input);
    expect(body).toContain("## Description\n\nWhen I tap save");
    expect(body).toContain("## Environment\n\nQuKi Notes 0.27.0");
    expect(body).toContain("Report a problem form");
    expect(reportBody(input, false)).not.toContain("Sent from");
  });

  it("follows the feature template shape", () => {
    expect(reportBody({ ...input, type: "feature" })).toContain("## Is your feature request related to a problem?");
  });

  it("puts the log in a code fence only when there is one", () => {
    expect(reportBody(input)).not.toContain("Failure log");
    expect(reportBody({ ...input, log: "  " })).not.toContain("Failure log");
    expect(reportBody({ ...input, log: "line one" })).toContain("## Failure log\n\n```\nline one\n```");
  });

  it("holds only what the user supplied", () => {
    const body = reportBody({ type: "feedback", title: "t", description: "", details: "" });
    expect(body).toContain("_(no description)_");
    expect(body).not.toContain("Environment");
  });
});

describe("reportText", () => {
  it("is the title, a blank line and the body", () => {
    expect(reportText(input)).toBe(`[BUG] It crashes\n\n${reportBody(input)}`);
  });
});

describe("reportIssueUrl", () => {
  it("opens a new issue on the QuKi Notes repo with the matching template, title and body", () => {
    const url = new URL(reportIssueUrl(input));
    expect(url.origin + url.pathname).toBe("https://github.com/ScottKirvan/QuKi-Notes/issues/new");
    expect(url.searchParams.get("template")).toBe("bug_report.md");
    expect(url.searchParams.get("title")).toBe("[BUG] It crashes");
    expect(url.searchParams.get("body")).toBe(reportBody(input));
    expect(new URL(reportIssueUrl({ ...input, type: "feature" })).searchParams.get("template")).toBe("feature_request.md");
    expect(new URL(reportIssueUrl({ ...input, type: "feedback" })).searchParams.get("template")).toBe("general_report.md");
  });

  it("drops a long log first, with a note", () => {
    const url = new URL(reportIssueUrl({ ...input, log: "line\n".repeat(5000) }));
    expect(url.href.length).toBeLessThanOrEqual(REPORT_URL_MAX);
    expect(url.searchParams.get("body")).not.toContain("## Failure log");
    expect(url.searchParams.get("body")).toContain("The failure log was too long for a link");
    expect(url.searchParams.get("body")).toContain("When I tap save");
  });

  it("cuts a long description to fit, with a note pointing at Copy report", () => {
    const href = reportIssueUrl({ ...input, description: "word ".repeat(5000) });
    expect(href.length).toBeLessThanOrEqual(REPORT_URL_MAX);
    expect(new URL(href).searchParams.get("body")).toContain("Copy report");
  });
});

describe("reportMailtoUrl", () => {
  it("addresses the project's email with subject and plain-text body", () => {
    const url = reportMailtoUrl({ ...input, log: "a log line" });
    expect(url.startsWith(`mailto:${REPORT_EMAIL}?`)).toBe(true);
    const query = new URLSearchParams(url.slice(url.indexOf("?") + 1));
    expect(query.get("subject")).toBe("[BUG] It crashes");
    expect(query.get("body")).toBe("When I tap save\n\nQuKi Notes 0.27.0\nPlatform: web\n\nFailure log:\na log line");
  });

  it("stays within a safe length: the log goes first, then the text is cut", () => {
    const withLog = reportMailtoUrl({ ...input, log: "line\n".repeat(2000) });
    expect(withLog.length).toBeLessThanOrEqual(MAILTO_MAX);
    expect(decodeURIComponent(withLog)).toContain("When I tap save");
    expect(decodeURIComponent(withLog)).toContain("use Copy report");
    const huge = reportMailtoUrl({ ...input, description: "word ".repeat(5000) });
    expect(huge.length).toBeLessThanOrEqual(MAILTO_MAX);
    expect(decodeURIComponent(huge)).toContain("Copy report");
  });
});

describe("relayRequest", () => {
  it("names the app and type, and sends the title and body without a footer (the relay adds its own)", () => {
    const { request, truncated } = relayRequest(input);
    expect(request).toEqual({ app: "quki-notes", type: "bug", title: "[BUG] It crashes", body: reportBody(input, false) });
    expect(truncated).toBe("none");
  });

  it("drops a log that pushes the body over 65,000 characters, and says so in the body", () => {
    const { request, truncated } = relayRequest({ ...input, log: "x".repeat(RELAY_BODY_MAX) });
    expect(truncated).toBe("log-dropped");
    expect(request.body.length).toBeLessThanOrEqual(RELAY_BODY_MAX);
    expect(request.body).toContain("The failure log was too long to include.");
    expect(request.body).not.toContain("```");
    expect(request.body).toContain("When I tap save");
  });

  it("cuts a description that is itself too long, with a visible note", () => {
    const { request, truncated } = relayRequest({ ...input, description: "y".repeat(RELAY_BODY_MAX * 2) });
    expect(truncated).toBe("cut");
    expect(request.body.length).toBeLessThanOrEqual(RELAY_BODY_MAX);
    expect(request.body.endsWith("_…cut to fit._")).toBe(true);
  });

  it("keeps the whole request under 256 KB even when every character is several bytes", () => {
    const { request } = relayRequest({ ...input, description: "😀".repeat(RELAY_BODY_MAX) });
    expect(request.body.length).toBeLessThanOrEqual(RELAY_BODY_MAX);
    expect(new TextEncoder().encode(JSON.stringify(request)).length).toBeLessThanOrEqual(RELAY_REQUEST_MAX_BYTES);
  });
});

describe("readRelayResponse", () => {
  it("accepts a 201 with an issue link", () => {
    expect(readRelayResponse(201, { url: "https://github.com/ScottKirvan/QuKi-Notes/issues/9", number: 9 })).toEqual({
      ok: true,
      url: "https://github.com/ScottKirvan/QuKi-Notes/issues/9",
      number: 9,
    });
  });

  it("refuses a 201 whose link is not a GitHub link", () => {
    expect(readRelayResponse(201, { url: "https://evil.example/x", number: 1 }).ok).toBe(false);
    expect(readRelayResponse(201, null).ok).toBe(false);
  });

  const failure = (status: number, json: unknown): string => {
    const result = readRelayResponse(status, json);
    if (result.ok) throw new Error("expected a failure");
    return result.message;
  };

  it("names the field for invalid_report", () => {
    expect(failure(400, { error: "invalid_report", field: "title" })).toContain("The title");
    expect(failure(400, { error: "invalid_report", field: "body" })).toContain("The report text");
    expect(failure(400, { error: "invalid_report", field: "weird" })).toContain("A part of the report");
  });

  it("offers the fallbacks for rate_limited, upstream_error, disabled, not_configured and internal_error", () => {
    const cases: Array<[number, string]> = [
      [429, "rate_limited"],
      [502, "upstream_error"],
      [503, "disabled"],
      [503, "not_configured"],
      [500, "internal_error"],
    ];
    for (const [status, error] of cases) {
      expect(failure(status, { error }), error).toContain("Open on GitHub, Copy report or Email");
    }
    expect(failure(429, { error: "rate_limited" })).toContain("Too many reports");
    expect(failure(503, { error: "disabled" })).toContain("switched off");
  });

  it("explains payload_too_large, and falls back to the status for anything unknown", () => {
    expect(failure(413, { error: "payload_too_large" })).toContain("too long");
    expect(failure(418, { error: "teapot" })).toContain("error 418");
    expect(failure(418, { error: "teapot" })).toContain("Open on GitHub, Copy report or Email");
    expect(failure(0, "not json")).not.toContain("error 0");
  });
});

describe("sendReport", () => {
  it("sends the relay request as JSON to the sender and returns the issue", async () => {
    const send = vi.fn(async (_body: string, _signal: AbortSignal) => ({
      status: 201,
      json: { url: "https://github.com/ScottKirvan/QuKi-Notes/issues/3", number: 3 },
    }));
    const result = await sendReport(send, input);
    expect(result).toEqual({ ok: true, url: "https://github.com/ScottKirvan/QuKi-Notes/issues/3", number: 3 });
    expect(send).toHaveBeenCalledTimes(1);
    expect(JSON.parse(send.mock.calls[0]![0])).toEqual(relayRequest(input).request);
  });

  it("turns a network failure into the unreachable message, with no retry", async () => {
    const send = vi.fn(async (): Promise<never> => {
      throw new TypeError("Failed to fetch");
    });
    expect(await sendReport(send, input)).toEqual({ ok: false, message: RELAY_UNREACHABLE });
    expect(send).toHaveBeenCalledTimes(1);
  });

  it("gives up at the timeout and aborts the request", async () => {
    let signal: AbortSignal | undefined;
    const send = (_body: string, s: AbortSignal): Promise<never> => {
      signal = s;
      return new Promise(() => {});
    };
    expect(await sendReport(send, input, 20)).toEqual({ ok: false, message: RELAY_UNREACHABLE });
    expect(signal?.aborted).toBe(true);
  });

  it("maps an error reply", async () => {
    const result = await sendReport(async () => ({ status: 429, json: { error: "rate_limited" } }), input);
    expect(result.ok).toBe(false);
  });
});

describe("constants", () => {
  it("keeps the relay address in one place", () => {
    expect(RELAY_URL).toBe("https://report.scottkirvan.com/report");
  });
});

describe("tailLines", () => {
  it("keeps the last n non-empty lines", () => {
    expect(tailLines("a\n\nb\nc\nd\n", 2)).toBe("c\nd");
    expect(tailLines("a\nb", 0)).toBe("");
  });
});
