import { describe, expect, it } from "vitest";

import { osLabel, osLabelFromUserAgent } from "./platformLabel";

describe("osLabel", () => {
  it("names the platform and adds the release when there is one", () => {
    expect(osLabel("win32", "10.0.28120")).toBe("Windows 10.0.28120");
    expect(osLabel("darwin", "24.1.0")).toBe("macOS 24.1.0");
    expect(osLabel("linux", "6.8.0")).toBe("Linux 6.8.0");
    expect(osLabel("freebsd", "14.0")).toBe("freebsd 14.0");
    expect(osLabel("linux", "")).toBe("Linux");
  });
});

describe("osLabelFromUserAgent", () => {
  it("reads Android's version", () => {
    expect(osLabelFromUserAgent("Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36")).toBe("Android 14");
  });

  it("names Windows, macOS, iOS, ChromeOS and Linux without a version", () => {
    expect(osLabelFromUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36")).toBe("Windows");
    expect(osLabelFromUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15")).toBe("macOS");
    expect(osLabelFromUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15")).toBe("iOS");
    expect(osLabelFromUserAgent("Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36")).toBe("ChromeOS");
    expect(osLabelFromUserAgent("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36")).toBe("Linux");
  });

  it("is empty for a user agent it does not recognise", () => {
    expect(osLabelFromUserAgent("")).toBe("");
    expect(osLabelFromUserAgent("curl/8.0")).toBe("");
  });
});
