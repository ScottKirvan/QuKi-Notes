const MONTH_DAY = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" });
const MONTH_DAY_YEAR = new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric" });

/**
 * BEHAVIOR_SPEC.md §9's "Age" column is framed as elapsed duration, not
 * calendar-date difference, for the first four rows - so "Exactly one day"
 * is read here as the elapsed-duration bucket [24h, 48h), consistent with
 * the "Under a day" bucket immediately above it, rather than as a calendar
 * day-of-month comparison (which would make "Yesterday" fire for a QuKi
 * edited two minutes before midnight). The spec does not disambiguate this
 * explicitly.
 */
export function formatRelativeTime(timestamp: string | number | Date, now: Date = new Date()): string {
  const then = timestamp instanceof Date ? timestamp : new Date(timestamp);
  const diffMs = now.getTime() - then.getTime();
  const diffMinutes = Math.floor(diffMs / 60_000);

  if (diffMinutes < 1) return "just now";
  if (diffMinutes < 60) return `${diffMinutes} min ago`;

  const diffHours = Math.floor(diffMs / 3_600_000);
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffHours < 48) return "Yesterday";

  if (then.getFullYear() === now.getFullYear()) return MONTH_DAY.format(then);
  return MONTH_DAY_YEAR.format(then);
}
