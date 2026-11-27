/**
 * The pure logic of the in-app "Report a problem" form: how a report the user
 * reviewed becomes a relay request, a pre-filled GitHub link, a clipboard text
 * or an email. Ported from BojuBot's src/utils/report.ts so the two apps stay
 * alike; QuKi-specific parts are the constants, the 256-character title, the
 * byte limit on a request and the mailto builder. Nothing here touches the
 * network or the DOM. Nothing is sent until the user taps Send.
 */

export type ReportType = "bug" | "feature" | "feedback";

export interface ReportInput {
  type: ReportType;
  /** One-line summary; the issue title after its type prefix. */
  title: string;
  /** What went wrong, or what the user would like. Goes in the body only. */
  description: string;
  /** Version line and platform, already reviewed and editable. */
  details: string;
  /** Recent failure log, only when the user ticked "Include recent log". */
  log?: string;
}

/** The one place the relay's address is written (Electron's main process has its own copy, electron/src/reportRelay.ts). */
export const RELAY_URL = "https://report.scottkirvan.com/report";
/** The relay's name for QuKi Notes; it picks the repo the issue goes to. */
export const RELAY_APP = "quki-notes";
export const REPO_URL = "https://github.com/ScottKirvan/QuKi-Notes";
export const PRIVACY_URL = "https://www.scottkirvan.com/QuKi-Notes/privacy";
export const REPORT_EMAIL = "quki-notes@skvfx.com";

/** The relay's limits on the title and the body, and on the whole request. */
export const TITLE_MAX = 256;
export const RELAY_BODY_MAX = 65000;
export const RELAY_REQUEST_MAX_BYTES = 256 * 1024;
/** Browsers and GitHub cope with URLs well beyond this, but it keeps us safe everywhere. */
export const REPORT_URL_MAX = 7000;
/** Some mail apps refuse a longer mailto: link. */
export const MAILTO_MAX = 1800;

/** Title prefixes the repo's issue templates use. */
const TITLE_PREFIX: Record<ReportType, string> = { bug: "[BUG] ", feature: "[FEATURE] ", feedback: "[GENERAL] " };
/** The repo's issue templates; blank issues are disabled, so a link without one lands on the template picker and loses the report. */
const TEMPLATE: Record<ReportType, string> = { bug: "bug_report.md", feature: "feature_request.md", feedback: "general_report.md" };

const DEFAULT_TITLE: Record<ReportType, string> = { bug: "Problem report", feature: "Feature request", feedback: "Feedback" };

/** "[BUG] The title", on one line, the whole thing no longer than TITLE_MAX. */
export function reportTitle(type: ReportType, title: string): string {
  const prefix = TITLE_PREFIX[type];
  const room = TITLE_MAX - prefix.length;
  const first = title.trim().split(/\r?\n/)[0]!.replace(/\s+/g, " ").trim();
  const text = first.length > room ? first.slice(0, room - 1).trimEnd() + "…" : first;
  return prefix + (text || DEFAULT_TITLE[type]);
}

/**
 * Markdown body following the shape of the repo's issue templates. `footer`
 * adds the "Sent from..." line; the relay adds its own, so Send leaves it off.
 */
export function reportBody(input: ReportInput, footer = true): string {
  const description = input.description.trim() || "_(no description)_";
  const details = input.details.trim();
  const parts: string[] = [];
  if (input.type === "feature") {
    parts.push("## Is your feature request related to a problem?", description);
    if (details) parts.push("## Additional Context", details);
  } else {
    parts.push("## Description", description);
    if (details) parts.push("## Environment", details);
  }
  if (input.log?.trim()) parts.push("## Failure log", "```\n" + input.log.trim() + "\n```");
  if (footer) parts.push("---", "_Sent from QuKi Notes' Report a problem form._");
  return parts.join("\n\n");
}

/** What Copy report puts on the clipboard. */
export function reportText(input: ReportInput): string {
  return `${reportTitle(input.type, input.title)}\n\n${reportBody(input)}`;
}

/**
 * A GitHub "new issue" link with the title and body filled in. If the result
 * would be too long, the log is dropped first, then the body is cut, with a
 * note telling the reporter to paste the full text (Copy report) instead.
 */
export function reportIssueUrl(input: ReportInput, maxLength = REPORT_URL_MAX): string {
  const make = (body: string): string =>
    `${REPO_URL}/issues/new?template=${TEMPLATE[input.type]}&title=${encodeURIComponent(reportTitle(input.type, input.title))}&body=${encodeURIComponent(body)}`;

  let url = make(reportBody(input));
  if (url.length <= maxLength) return url;

  url = make(reportBody({ ...input, log: undefined }) + "\n\n_The failure log was too long for a link; paste it in a comment._");
  if (url.length <= maxLength) return url;

  const note = "\n\n_…cut to fit a link. Use **Copy report** in QuKi Notes and paste the full text here._";
  let body = reportBody({ ...input, log: undefined });
  while (body.length > 0 && make(body + note).length > maxLength) body = body.slice(0, Math.floor(body.length * 0.9));
  return make(body + note);
}

/**
 * A mailto: link to the project's address, the private route. Plain text, the
 * log last; if the link would be too long the log is dropped, then the body is
 * cut with a note to use Copy report.
 */
export function reportMailtoUrl(input: ReportInput, maxLength = MAILTO_MAX): string {
  const subject = reportTitle(input.type, input.title);
  const make = (body: string): string => `mailto:${REPORT_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  const plain = (withLog: boolean): string => {
    const parts = [input.description.trim() || "(no description)"];
    if (input.details.trim()) parts.push(input.details.trim());
    if (withLog && input.log?.trim()) parts.push("Failure log:\n" + input.log.trim());
    return parts.join("\n\n");
  };

  let url = make(plain(true));
  if (url.length <= maxLength) return url;

  const logNote = "\n\n(The failure log was too long for a link; use Copy report and paste it here.)";
  url = make(plain(false) + (input.log?.trim() ? logNote : ""));
  if (url.length <= maxLength) return url;

  const note = "\n\n(…cut to fit. Use Copy report in QuKi Notes and paste the full text here.)";
  let body = plain(false);
  while (body.length > 0 && make(body + note).length > maxLength) body = body.slice(0, Math.floor(body.length * 0.9));
  return make(body + note);
}

/** What Send posts to the report relay: `POST /report` as JSON. */
export interface RelayRequest {
  app: string;
  type: ReportType;
  title: string;
  body: string;
}

function requestBytes(request: RelayRequest): number {
  return new TextEncoder().encode(JSON.stringify(request)).length;
}

const fits = (request: RelayRequest, maxBody: number, maxBytes: number): boolean =>
  request.body.length <= maxBody && requestBytes(request) <= maxBytes;

/**
 * The relay request for a report. A body over the relay's limits drops the
 * log first, then is cut with a visible note, so a long log never makes Send
 * fail. `truncated` says which of those happened, for the form to tell the user.
 */
export function relayRequest(
  input: ReportInput,
  maxBody = RELAY_BODY_MAX,
  maxBytes = RELAY_REQUEST_MAX_BYTES,
): { request: RelayRequest; truncated: "none" | "log-dropped" | "cut" } {
  const make = (body: string): RelayRequest => ({ app: RELAY_APP, type: input.type, title: reportTitle(input.type, input.title), body });

  let request = make(reportBody(input, false));
  if (fits(request, maxBody, maxBytes)) return { request, truncated: "none" };

  request = make(reportBody({ ...input, log: undefined }, false) + "\n\n_The failure log was too long to include._");
  if (fits(request, maxBody, maxBytes)) return { request, truncated: "log-dropped" };

  const note = "\n\n_…cut to fit._";
  let body = reportBody({ ...input, log: undefined }, false);
  body = body.slice(0, Math.max(0, Math.min(body.length, maxBody - note.length)));
  while (body.length > 0 && !fits(make(body + note), maxBody, maxBytes)) body = body.slice(0, Math.floor(body.length * 0.9));
  return { request: make(body + note), truncated: "cut" };
}

/** How a Send ended: the public issue's link, or a message for the form. */
export type SendResult =
  | { ok: true; url: string; number: number }
  | { ok: false; message: string };

const FIELD_LABEL: Record<string, string> = {
  title: "The title",
  body: "The report text (description, details or failure log)",
  type: "The report type",
};

const FALLBACKS = "Use Open on GitHub, Copy report or Email instead.";

/** Message for a Send that got no reply at all (offline, blocked, timed out). */
export const RELAY_UNREACHABLE = `Couldn't reach the report service. Check your connection and try again. ${FALLBACKS}`;

/**
 * Read the relay's reply. Anything but a `201` with an issue link is a failure
 * with a plain-language message; the form keeps Open on GitHub, Copy report
 * and Email at all times, so a report is never lost.
 */
export function readRelayResponse(status: number, json: unknown): SendResult {
  const data = (json && typeof json === "object" ? json : {}) as Record<string, unknown>;
  if (status === 201 && typeof data.url === "string" && data.url.startsWith("https://github.com/")) {
    return { ok: true, url: data.url, number: typeof data.number === "number" ? data.number : 0 };
  }
  switch (data.error) {
    case "rate_limited":
      return { ok: false, message: `Too many reports were sent in the last minute. Wait a moment and try again. ${FALLBACKS}` };
    case "payload_too_large":
      return { ok: false, message: "The report is too long to send. Shorten the details or the failure log and try again." };
    case "invalid_report": {
      const field = typeof data.field === "string" ? data.field : "";
      const label = FIELD_LABEL[field] ?? "A part of the report";
      return { ok: false, message: `${label} is empty or too long. Fix it and try again.` };
    }
    case "disabled":
    case "not_configured":
      return { ok: false, message: `Sending reports is switched off right now. ${FALLBACKS}` };
    case "upstream_error":
      return { ok: false, message: `GitHub didn't accept the report just now. ${FALLBACKS}` };
    case "internal_error":
      return { ok: false, message: `The report service had a problem. ${FALLBACKS}` };
    default:
      return { ok: false, message: `The report couldn't be sent${status ? ` (error ${status})` : ""}. ${FALLBACKS}` };
  }
}

/** What a platform sender hands back: the relay's HTTP status and its parsed JSON (null if it wasn't JSON). */
export interface RelayReply {
  status: number;
  json: unknown;
}

/** Posts the JSON text to the relay on this platform; rejects on a network failure. */
export type RelaySender = (body: string, signal: AbortSignal) => Promise<RelayReply>;

export const SEND_TIMEOUT_MS = 20_000;

/**
 * Send one report. Never throws and never retries: every failure, a timeout
 * included, is a message. `timeoutMs` exists so tests need not wait 20 s.
 */
export async function sendReport(send: RelaySender, input: ReportInput, timeoutMs = SEND_TIMEOUT_MS): Promise<SendResult> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<null>((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve(null);
    }, timeoutMs);
  });
  try {
    const reply = await Promise.race([send(JSON.stringify(relayRequest(input).request), controller.signal), timeout]);
    if (!reply) return { ok: false, message: RELAY_UNREACHABLE };
    return readRelayResponse(reply.status, reply.json);
  } catch {
    return { ok: false, message: RELAY_UNREACHABLE };
  } finally {
    clearTimeout(timer);
  }
}

/** The last `n` non-empty lines of a log. */
export function tailLines(text: string, n: number): string {
  if (n <= 0) return "";
  const lines = text.split(/\r?\n/).filter((l) => l.trim());
  return lines.slice(-n).join("\n");
}
