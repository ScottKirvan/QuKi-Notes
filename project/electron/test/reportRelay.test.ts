import { describe, expect, it, vi } from 'vitest';

import { postReport, REPORT_RELAY_URL, REPORT_REQUEST_MAX_BYTES, reportRelayUrl } from '../src/reportRelay.js';

describe('reportRelayUrl', () => {
  it('is the real relay by default', () => {
    expect(reportRelayUrl({})).toBe(REPORT_RELAY_URL);
    expect(REPORT_RELAY_URL).toBe('https://report.scottkirvan.com/report');
  });

  it('honours the test seam for a loopback http address', () => {
    expect(reportRelayUrl({ QUKI_TEST_REPORT_RELAY_URL: 'http://127.0.0.1:4567/report' })).toBe('http://127.0.0.1:4567/report');
    expect(reportRelayUrl({ QUKI_TEST_REPORT_RELAY_URL: 'http://localhost:1/report' })).toBe('http://localhost:1/report');
  });

  it('ignores any other override', () => {
    for (const value of ['https://evil.example/report', 'http://example.com/report', 'nonsense', '']) {
      expect(reportRelayUrl({ QUKI_TEST_REPORT_RELAY_URL: value })).toBe(REPORT_RELAY_URL);
    }
  });
});

describe('postReport', () => {
  const ok = (status: number, text: string) => vi.fn(async () => ({ status, text: async () => text }));

  it('posts the JSON text as application/json and returns status and parsed JSON', async () => {
    const fetchFn = ok(201, '{"url":"https://github.com/o/r/issues/1","number":1}');
    const reply = await postReport('{"a":1}', fetchFn, 'http://127.0.0.1:1/report');
    expect(reply).toEqual({ status: 201, json: { url: 'https://github.com/o/r/issues/1', number: 1 } });
    const [url, init] = fetchFn.mock.calls[0] as unknown as [string, { method: string; headers: Record<string, string>; body: string }];
    expect(url).toBe('http://127.0.0.1:1/report');
    expect(init.method).toBe('POST');
    expect(init.headers['content-type']).toBe('application/json');
    expect(init.body).toBe('{"a":1}');
  });

  it('returns null json for a reply that is not JSON', async () => {
    expect(await postReport('{}', ok(502, '<html>bad gateway</html>'), 'u')).toEqual({ status: 502, json: null });
  });

  it('rejects a body that is not a string or is over the relay limit, without sending', async () => {
    const fetchFn = ok(201, '{}');
    await expect(postReport({ a: 1 }, fetchFn, 'u')).rejects.toThrow();
    await expect(postReport('x'.repeat(REPORT_REQUEST_MAX_BYTES + 1), fetchFn, 'u')).rejects.toThrow();
    expect(fetchFn).not.toHaveBeenCalled();
  });

  it('rejects when the network fails', async () => {
    await expect(postReport('{}', vi.fn(async () => { throw new Error('offline'); }), 'u')).rejects.toThrow('offline');
  });

  it('gives fetch an abort signal that fires at the timeout', async () => {
    const fetchFn = vi.fn((_url: string, init: { signal: AbortSignal }) => new Promise<never>((_resolve, reject) => {
      init.signal.addEventListener('abort', () => reject(new Error('aborted')));
    }));
    await expect(postReport('{}', fetchFn as never, 'u', 20)).rejects.toThrow('aborted');
  });
});
