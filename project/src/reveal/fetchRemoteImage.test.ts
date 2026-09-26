import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchRemoteImage } from "./fetchRemoteImage";

function fakeResponse(init: {
  ok: boolean;
  status?: number;
  statusText?: string;
  contentType?: string | null;
  body?: Uint8Array;
}): Response {
  return {
    ok: init.ok,
    status: init.status ?? (init.ok ? 200 : 500),
    statusText: init.statusText ?? "",
    headers: {
      get: (name: string) => (name.toLowerCase() === "content-type" ? (init.contentType ?? null) : null),
    },
    arrayBuffer: async () => (init.body ?? new Uint8Array()).buffer,
  } as unknown as Response;
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("fetchRemoteImage", () => {
  it("returns bytes and content type for a successful image response", async () => {
    const body = new Uint8Array([1, 2, 3, 4]);
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => fakeResponse({ ok: true, contentType: "image/png", body })),
    );
    const result = await fetchRemoteImage("https://example.com/a.png");
    expect(result.contentType).toBe("image/png");
    expect(Array.from(result.bytes)).toEqual([1, 2, 3, 4]);
  });

  it("rejects on a non-OK HTTP status", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => fakeResponse({ ok: false, status: 404, statusText: "Not Found" })),
    );
    await expect(fetchRemoteImage("https://example.com/missing.png")).rejects.toThrow(/404/);
  });

  it("rejects when the response has no content-type", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => fakeResponse({ ok: true, contentType: null, body: new Uint8Array([1]) })),
    );
    await expect(fetchRemoteImage("https://example.com/unknown.bin")).rejects.toThrow(/content-type/);
  });

  it("rejects when the response's content-type is not an image type", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => fakeResponse({ ok: true, contentType: "text/html", body: new Uint8Array([1]) })),
    );
    await expect(fetchRemoteImage("https://example.com/page.html")).rejects.toThrow(/content-type/);
  });

  it("propagates a network-level failure (offline, DNS, CORS block) as a rejection", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new TypeError("Failed to fetch");
      }),
    );
    await expect(fetchRemoteImage("https://example.com/blocked.png")).rejects.toThrow("Failed to fetch");
  });
});
