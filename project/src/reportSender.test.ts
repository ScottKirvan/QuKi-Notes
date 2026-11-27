import { afterEach, describe, expect, it, vi } from "vitest";

const request = vi.fn();
const state = { native: false };
vi.mock("@capacitor/core", () => ({
  Capacitor: { isNativePlatform: () => state.native },
  CapacitorHttp: { request: (options: unknown) => request(options) },
}));

import { capacitorSender, fetchSender, platformRelaySender } from "./reportSender";

afterEach(() => {
  vi.unstubAllGlobals();
  request.mockReset();
  state.native = false;
});

describe("fetchSender", () => {
  it("posts JSON to the relay with fetch and parses the reply", async () => {
    const fetchMock = vi.fn(async () => new Response('{"error":"rate_limited"}', { status: 429 }));
    vi.stubGlobal("fetch", fetchMock);
    const signal = new AbortController().signal;
    expect(await fetchSender('{"a":1}', signal)).toEqual({ status: 429, json: { error: "rate_limited" } });
    expect(fetchMock).toHaveBeenCalledWith("https://report.scottkirvan.com/report", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: '{"a":1}',
      signal,
    });
  });

  it("gives null json for a reply that is not JSON", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("<html>", { status: 502 })));
    expect(await fetchSender("{}", new AbortController().signal)).toEqual({ status: 502, json: null });
  });
});

describe("capacitorSender", () => {
  it("posts through native HTTP, not fetch", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    request.mockResolvedValue({ status: 201, data: '{"url":"https://github.com/o/r/issues/1","number":1}' });
    expect(await capacitorSender('{"a":1}', new AbortController().signal)).toEqual({
      status: 201,
      json: { url: "https://github.com/o/r/issues/1", number: 1 },
    });
    expect(request).toHaveBeenCalledWith(expect.objectContaining({ url: "https://report.scottkirvan.com/report", method: "POST", data: { a: 1 } }));
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("passes an already parsed reply through", async () => {
    request.mockResolvedValue({ status: 503, data: { error: "disabled" } });
    expect(await capacitorSender("{}", new AbortController().signal)).toEqual({ status: 503, json: { error: "disabled" } });
  });
});

describe("platformRelaySender", () => {
  it("uses the Electron bridge when present", async () => {
    const send = vi.fn(async () => ({ status: 201, json: {} }));
    vi.stubGlobal("window", { electronReportAPI: { send } });
    await platformRelaySender()("{}", new AbortController().signal);
    expect(send).toHaveBeenCalledWith("{}");
  });

  it("uses native HTTP on a native platform, fetch otherwise", () => {
    vi.stubGlobal("window", {});
    state.native = true;
    expect(platformRelaySender()).toBe(capacitorSender);
    state.native = false;
    expect(platformRelaySender()).toBe(fetchSender);
  });
});
