/** How long the app must be out of sight before coming back starts a new QuKi; null is Off. */
export type AwayMinutes = number | null;

export const AWAY_CHOICES: readonly { minutes: AwayMinutes; label: string }[] = [
  { minutes: null, label: "Off" },
  { minutes: 2, label: "After 2 minutes" },
  { minutes: 5, label: "After 5 minutes" },
  { minutes: 15, label: "After 15 minutes" },
  { minutes: 30, label: "After 30 minutes" },
];

export const DEFAULT_AWAY_MINUTES: AwayMinutes = 2;

const OFF = "off";

export function serializeAwayMinutes(minutes: AwayMinutes): string {
  return minutes === null ? OFF : String(minutes);
}

export function parseAwayMinutes(raw: string | null): AwayMinutes {
  if (raw === OFF) return null;
  const choice = AWAY_CHOICES.find((c) => c.minutes !== null && String(c.minutes) === raw);
  return choice ? choice.minutes : DEFAULT_AWAY_MINUTES;
}

/**
 * A Send opens the system share sheet, which can hide the app; a hide this
 * soon after Send is the share sheet's, not the user leaving.
 */
export const SEND_HIDE_WINDOW_MS = 10_000;

export interface AwayReturn {
  hiddenAt: number;
  shownAt: number;
  minutes: AwayMinutes;
  /** The app was hidden by Send's share sheet. */
  hiddenBySend: boolean;
  /** Text was shared in while the app was away; that opens its own new QuKi. */
  sharedIn: boolean;
}

export function shouldStartNewQuKi({ hiddenAt, shownAt, minutes, hiddenBySend, sharedIn }: AwayReturn): boolean {
  if (minutes === null || hiddenBySend || sharedIn) return false;
  return shownAt - hiddenAt >= minutes * 60_000;
}

/**
 * Follows the app going out of sight and coming back. Only time spent hidden
 * counts: an app left open and visible never starts a new QuKi, however long
 * it sits. Hidden and shown signals may arrive twice for one change (page
 * visibility and the native app lifecycle both report it); repeats are ignored.
 */
export class AwayTracker {
  private hiddenAt: number | null = null;
  private hiddenBySend = false;
  private sharedIn = false;
  private lastSendAt: number | null = null;

  constructor(private readonly now: () => number) {}

  noteSend(): void {
    this.lastSendAt = this.now();
  }

  noteShareIn(): void {
    if (this.hiddenAt !== null) this.sharedIn = true;
  }

  hidden(): void {
    if (this.hiddenAt !== null) return;
    const at = this.now();
    this.hiddenAt = at;
    this.hiddenBySend = this.lastSendAt !== null && at - this.lastSendAt <= SEND_HIDE_WINDOW_MS;
    this.sharedIn = false;
  }

  /** The app is visible again: whether to start a new QuKi. */
  shown(minutes: AwayMinutes): boolean {
    if (this.hiddenAt === null) return false;
    const decision = shouldStartNewQuKi({
      hiddenAt: this.hiddenAt,
      shownAt: this.now(),
      minutes,
      hiddenBySend: this.hiddenBySend,
      sharedIn: this.sharedIn,
    });
    this.forget();
    return decision;
  }

  /** The current trip away, if any, was part of something the app asked for and does not count. */
  forget(): void {
    this.hiddenAt = null;
    this.hiddenBySend = false;
    this.sharedIn = false;
  }
}
