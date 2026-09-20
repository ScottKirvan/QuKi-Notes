import { describe, expect, it } from "vitest";

import { formatRelativeTime } from "./relativeTime.js";

const NOW = new Date(2026, 5, 15, 12, 0, 0); // Jun 15, 2026, 12:00:00 local

function minutesAgo(n: number): Date {
  return new Date(NOW.getTime() - n * 60_000);
}
function secondsAgo(n: number): Date {
  return new Date(NOW.getTime() - n * 1000);
}
function hoursAgo(n: number): Date {
  return new Date(NOW.getTime() - n * 3_600_000);
}

describe("formatRelativeTime", () => {
  it("shows 'just now' for the current instant", () => {
    expect(formatRelativeTime(NOW, NOW)).toBe("just now");
  });

  it("shows 'just now' up to 59 seconds", () => {
    expect(formatRelativeTime(secondsAgo(59), NOW)).toBe("just now");
  });

  it("shows '1 min ago' at exactly 60 seconds", () => {
    expect(formatRelativeTime(secondsAgo(60), NOW)).toBe("1 min ago");
  });

  it("shows 'N min ago' under an hour", () => {
    expect(formatRelativeTime(minutesAgo(5), NOW)).toBe("5 min ago");
    expect(formatRelativeTime(minutesAgo(59), NOW)).toBe("59 min ago");
  });

  it("shows '1h ago' at exactly 60 minutes", () => {
    expect(formatRelativeTime(minutesAgo(60), NOW)).toBe("1h ago");
  });

  it("shows 'Nh ago' under a day", () => {
    expect(formatRelativeTime(hoursAgo(5), NOW)).toBe("5h ago");
    expect(formatRelativeTime(hoursAgo(23), NOW)).toBe("23h ago");
  });

  it("shows 'Yesterday' at exactly 24 hours", () => {
    expect(formatRelativeTime(hoursAgo(24), NOW)).toBe("Yesterday");
  });

  it("shows 'Yesterday' up to just under 48 hours", () => {
    expect(formatRelativeTime(hoursAgo(47), NOW)).toBe("Yesterday");
  });

  it("switches to 'Mon D' formatting at exactly 48 hours, same year", () => {
    expect(formatRelativeTime(hoursAgo(48), NOW)).toBe("Jun 13");
  });

  it("shows 'Mon D' for an older date within the same calendar year", () => {
    const then = new Date(2026, 0, 7, 9, 0, 0); // Jan 7, 2026
    expect(formatRelativeTime(then, NOW)).toBe("Jan 7");
  });

  it("shows 'Mon D, YYYY' for a date in an earlier calendar year", () => {
    const then = new Date(2025, 0, 7, 9, 0, 0); // Jan 7, 2025
    expect(formatRelativeTime(then, NOW)).toBe("Jan 7, 2025");
  });

  it("accepts an ISO string timestamp, not just a Date", () => {
    const then = new Date(NOW.getTime() - 5 * 60_000).toISOString();
    expect(formatRelativeTime(then, NOW)).toBe("5 min ago");
  });
});
