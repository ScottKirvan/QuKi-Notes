import type { QuKiStore } from "quki-core";

import { recordFailure } from "../failureLog";
import { extractPreview } from "../preview";
import { formatRelativeTime } from "../relativeTime";
import {
  fadeDurationMs,
  nextWelcomeState,
  pickGreeting,
  pickRecent,
  pickTip,
  type WelcomeEvent,
  type WelcomeState,
} from "./welcomeContent";

export interface Welcome {
  /** A blank, unsaved QuKi is on screen. */
  showForBlankQuKi: () => void;
  /** A saved QuKi was loaded into the editor. */
  hideForLoadedQuKi: () => void;
  /** The user tapped, typed or edited. */
  dismiss: () => void;
}

/**
 * A decoration over the top of an empty editor. It is never in the editor's
 * document, and it takes no taps (pointer-events: none) except on the recent
 * QuKis, so the tap that dismisses it reaches the editor as it always did.
 * The first pointer or key event anywhere dismisses it.
 */
export function createWelcome(host: HTMLElement, store: QuKiStore, openQuKi: (id: string) => void): Welcome {
  let state: WelcomeState = { visible: false };
  let root: HTMLElement | null = null;
  let removeTimer: ReturnType<typeof setTimeout> | undefined;
  let generation = 0;

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  function remove(): void {
    clearTimeout(removeTimer);
    root?.remove();
    root = null;
  }

  function apply(event: WelcomeEvent): void {
    const was = state.visible;
    state = nextWelcomeState(state, event);
    if (was && !state.visible) {
      generation++;
      document.removeEventListener("pointerdown", onPointerDown, true);
      document.removeEventListener("keydown", onKeyDown, true);
      const leaving = root;
      if (leaving === null) return;
      const ms = fadeDurationMs(reducedMotion.matches);
      if (ms === 0) {
        remove();
        return;
      }
      leaving.classList.add("welcome-leaving");
      removeTimer = setTimeout(() => {
        if (root === leaving) remove();
      }, ms + 50);
    }
  }

  function onPointerDown(event: Event): void {
    if (event.target instanceof Node && root?.contains(event.target)) return;
    apply("dismiss");
  }

  function onKeyDown(): void {
    apply("dismiss");
  }

  async function loadRecent(): Promise<Array<{ id: string; preview: string; modifiedAt: string }>> {
    try {
      const recent = pickRecent(await store.list());
      return await Promise.all(
        recent.map(async ({ id, modifiedAt }) => {
          try {
            return { id, modifiedAt, preview: extractPreview((await store.read(id)).body) };
          } catch {
            return { id, modifiedAt, preview: extractPreview(null) };
          }
        }),
      );
    } catch (error) {
      console.error("QuKi welcome (recent list) failed unexpectedly:", error);
      recordFailure("welcome-recent-list", error);
      return [];
    }
  }

  function buildRoot(): HTMLElement {
    const el = document.createElement("div");
    el.className = "welcome";

    const decoration = document.createElement("div");
    decoration.className = "welcome-decoration";
    decoration.setAttribute("aria-hidden", "true");

    const icon = document.createElement("img");
    icon.className = "welcome-icon";
    icon.src = "/icons/icon-192.png";
    icon.alt = "";
    icon.draggable = false;

    const greeting = document.createElement("p");
    greeting.className = "welcome-greeting";
    greeting.textContent = pickGreeting(new Date().getHours());

    const tip = document.createElement("p");
    tip.className = "welcome-tip";
    tip.textContent = pickTip();

    decoration.append(icon, greeting, tip);
    el.append(decoration);
    return el;
  }

  function renderRecent(el: HTMLElement, entries: Array<{ id: string; preview: string; modifiedAt: string }>): void {
    if (entries.length === 0) return;
    const nav = document.createElement("nav");
    nav.className = "welcome-recent";
    nav.setAttribute("aria-label", "Recent QuKis");
    for (const entry of entries) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "welcome-recent-row";
      const preview = document.createElement("span");
      preview.className = "welcome-recent-preview";
      preview.textContent = entry.preview;
      const time = document.createElement("span");
      time.className = "welcome-recent-time";
      time.textContent = formatRelativeTime(entry.modifiedAt);
      button.append(preview, time);
      button.addEventListener("click", () => openQuKi(entry.id));
      nav.append(button);
    }
    el.append(nav);
  }

  return {
    showForBlankQuKi(): void {
      remove();
      document.removeEventListener("pointerdown", onPointerDown, true);
      document.removeEventListener("keydown", onKeyDown, true);
      state = nextWelcomeState({ visible: false }, "blank-quki");
      const mine = ++generation;
      const el = buildRoot();
      root = el;
      host.append(el);
      document.addEventListener("pointerdown", onPointerDown, true);
      document.addEventListener("keydown", onKeyDown, true);
      void loadRecent().then((entries) => {
        if (generation === mine && state.visible && root === el) renderRecent(el, entries);
      });
    },
    hideForLoadedQuKi: () => apply("quki-loaded"),
    dismiss: () => apply("dismiss"),
  };
}
