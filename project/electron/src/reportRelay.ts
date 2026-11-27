/**
 * Where the main process posts a problem report. The window never talks to the
 * relay itself: it hands the main process the report's JSON text over IPC and
 * this file decides the address, so a compromised page cannot aim the request
 * elsewhere. The address is written once here (src/reportProblem.ts holds the
 * web and Android copy).
 */
export const REPORT_RELAY_URL = 'https://report.scottkirvan.com/report';

/** The relay's limit on a whole request. */
export const REPORT_REQUEST_MAX_BYTES = 256 * 1024;

export const REPORT_SEND_TIMEOUT_MS = 20_000;

/**
 * QUKI_TEST_REPORT_RELAY_URL is a test-only seam (see e2e/reportElectron.e2e.ts),
 * like QUKI_TEST_FORCE_DIALOG_PATH: it points Send at a local mock server so a
 * test never files a real issue. Only a loopback http address is honoured; any
 * other value is ignored and the real address is used.
 */
export function reportRelayUrl(env: { QUKI_TEST_REPORT_RELAY_URL?: string }): string {
  const override = env.QUKI_TEST_REPORT_RELAY_URL;
  if (!override) return REPORT_RELAY_URL;
  try {
    const url = new URL(override);
    if (url.protocol === 'http:' && (url.hostname === '127.0.0.1' || url.hostname === 'localhost')) return url.toString();
  } catch {
    // not a URL: fall through to the real address
  }
  return REPORT_RELAY_URL;
}

export interface ReportReply {
  status: number;
  json: unknown;
}

export interface ReportFetchResponse {
  status: number;
  text(): Promise<string>;
}

export type ReportFetch = (
  url: string,
  init: { method: 'POST'; headers: Record<string, string>; body: string; signal: AbortSignal },
) => Promise<ReportFetchResponse>;

/**
 * Posts one report. `body` comes from the window, so it is checked: it must be
 * a string within the relay's size limit. Rejects on a network failure or a
 * timeout; never retries.
 */
export async function postReport(
  body: unknown,
  fetchFn: ReportFetch,
  url: string,
  timeoutMs = REPORT_SEND_TIMEOUT_MS,
): Promise<ReportReply> {
  if (typeof body !== 'string' || Buffer.byteLength(body, 'utf8') > REPORT_REQUEST_MAX_BYTES) {
    throw new Error('invalid report request');
  }
  const response = await fetchFn(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body,
    signal: AbortSignal.timeout(timeoutMs),
  });
  const text = await response.text();
  let json: unknown = null;
  try {
    json = JSON.parse(text);
  } catch {
    json = null;
  }
  return { status: response.status, json };
}
