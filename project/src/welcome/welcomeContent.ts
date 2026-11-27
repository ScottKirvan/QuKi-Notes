export type TimeBucket = "morning" | "afternoon" | "evening" | "night";

export const GREETINGS: Record<TimeBucket, readonly string[]> = {
  morning: ["Good morning.", "Morning. What's on your mind?", "A fresh QuKi for a fresh day.", "Rise and shine."],
  afternoon: ["Good afternoon.", "Afternoon. What's on your mind?", "Got a thought? Write it down.", "Quick, before it slips away."],
  evening: ["Good evening.", "Evening. What's on your mind?", "Winding down? Capture the day.", "Anything worth keeping from today?"],
  night: ["Still up?", "Night thoughts welcome.", "Get it out of your head and onto the page.", "Write it down, then sleep on it."],
};

// Each tip must stay true of the app: when the behaviour a tip names changes, change or drop the tip.
export const TIPS: readonly string[] = [
  "Swipe a QuKi left in the list to move it to Trash.",
  "Press Enter at the end of a list item to continue the list.",
  "Tap below your text to start a line right there.",
  "Send shares your QuKi with another app, or copies it on desktop.",
  "The mode toggle switches between rendered and plain text.",
  "Paste a copied web page and it turns into Markdown.",
  "Paste an image to add it to your QuKi.",
  "Tap a checkbox to tick it. Start a line with - [ ] to make one.",
  "QuKis save themselves a couple of seconds after you stop typing.",
  "After a couple of minutes away, a fresh QuKi is waiting. Change it in Settings.",
  "Deleted QuKis stay in Trash for 30 days. Find it in Settings.",
  "Start a quote with > [!NOTE] to get a callout.",
];

export const RECENT_COUNT = 3;

export function timeBucket(hour: number): TimeBucket {
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 17) return "afternoon";
  if (hour >= 17 && hour < 22) return "evening";
  return "night";
}

function pick<T>(items: readonly T[], random: () => number): T {
  const index = Math.min(items.length - 1, Math.floor(random() * items.length));
  return items[index]!;
}

export function pickGreeting(hour: number, random: () => number = Math.random): string {
  return pick(GREETINGS[timeBucket(hour)], random);
}

export function pickTip(random: () => number = Math.random): string {
  return pick(TIPS, random);
}

/** The few most recently modified QuKis, newest first, whatever order `items` arrive in. */
export function pickRecent<T extends { modifiedAt: string }>(items: readonly T[], count: number = RECENT_COUNT): T[] {
  return [...items].sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt)).slice(0, count);
}

export interface WelcomeState {
  visible: boolean;
}

export type WelcomeEvent = "blank-quki" | "dismiss" | "quki-loaded";

/**
 * The welcome belongs to a blank, unsaved QuKi: it appears when one is shown
 * and goes on the first tap, keystroke or edit, or when a saved QuKi loads. It
 * stays gone until the next blank QuKi.
 */
export function nextWelcomeState(state: WelcomeState, event: WelcomeEvent): WelcomeState {
  if (event === "blank-quki") return { visible: true };
  return state.visible ? { visible: false } : state;
}

export const WELCOME_FADE_MS = 200;

export function fadeDurationMs(prefersReducedMotion: boolean): number {
  return prefersReducedMotion ? 0 : WELCOME_FADE_MS;
}
