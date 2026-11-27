import type { BackDismissStack } from "../backDismissStack";
import { creditsData, type CreditsData } from "../credits";
import { creditsTimeline } from "../creditsTimeline";

export interface CreditsDialogOptions {
  backDismiss?: BackDismissStack;
  data?: CreditsData;
}

export interface CreditsDialog {
  /** `opener` is the element that gets focus back on close. */
  open: (opener: HTMLElement) => void;
  close: () => void;
  isOpen: () => boolean;
}

/**
 * Movie-style credits: the list rolls slowly upward until the last line
 * reaches the middle, fades out, and starts again. Scrolling, touching or
 * clicking the list, focusing a link or pressing ArrowDown stops the roll so
 * it can be read at the reader's own pace. With reduced motion on, it never
 * rolls and is a plain scrollable list.
 */
export function createCreditsDialog(container: HTMLElement, options: CreditsDialogOptions = {}): CreditsDialog {
  const data = options.data ?? creditsData;

  const overlay = document.createElement("div");
  overlay.className = "confirm-overlay credits-overlay";
  overlay.hidden = true;

  const dialog = document.createElement("div");
  dialog.className = "confirm-dialog credits-dialog";
  dialog.setAttribute("role", "dialog");
  dialog.setAttribute("aria-modal", "true");
  dialog.setAttribute("aria-labelledby", "credits-title");

  const heading = document.createElement("h2");
  heading.id = "credits-title";
  heading.className = "credits-heading";
  heading.textContent = "Credits";

  const viewport = document.createElement("div");
  viewport.className = "credits-viewport";
  const track = document.createElement("div");
  track.className = "credits-track";
  viewport.appendChild(track);

  for (const section of data.sections) {
    const sectionEl = document.createElement("div");
    sectionEl.className = "credits-section";
    const title = document.createElement("div");
    title.className = "credits-title";
    title.textContent = section.title;
    sectionEl.appendChild(title);
    for (const entry of section.entries) {
      const entryEl = document.createElement("div");
      entryEl.className = "credits-entry";
      if (entry.url !== undefined) {
        const link = document.createElement("a");
        link.className = "credits-name";
        link.textContent = entry.name;
        link.href = entry.url;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        entryEl.appendChild(link);
      } else {
        const name = document.createElement("span");
        name.className = "credits-name";
        name.textContent = entry.name;
        entryEl.appendChild(name);
      }
      if (entry.detail !== undefined) {
        const detail = document.createElement("div");
        detail.className = "credits-detail";
        detail.textContent = entry.detail;
        entryEl.appendChild(detail);
      }
      sectionEl.appendChild(entryEl);
    }
    track.appendChild(sectionEl);
  }
  const notice = document.createElement("div");
  notice.className = "credits-notice";
  notice.textContent = data.notice;
  track.appendChild(notice);

  const actions = document.createElement("div");
  actions.className = "confirm-actions";
  const closeBtn = document.createElement("button");
  closeBtn.type = "button";
  closeBtn.className = "credits-close";
  closeBtn.textContent = "Close";
  actions.appendChild(closeBtn);

  dialog.append(heading, viewport, actions);
  overlay.appendChild(dialog);

  let opener: HTMLElement | null = null;
  let unregisterBack = (): void => {};
  let roll: Animation | null = null;
  let frame = 0;

  const stopRolling = (): void => {
    window.cancelAnimationFrame(frame);
    roll?.cancel();
    roll = null;
    viewport.classList.remove("is-rolling");
    viewport.classList.add("is-static");
  };

  const startRolling = (): void => {
    viewport.scrollTop = 0;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      stopRolling();
      return;
    }
    viewport.classList.remove("is-static");
    viewport.classList.add("is-rolling");
    frame = window.requestAnimationFrame(() => {
      const t = creditsTimeline(track.offsetHeight, viewport.clientHeight);
      roll = track.animate(
        [
          { transform: `translateY(${t.fromPx}px)`, opacity: 1, offset: 0 },
          { transform: `translateY(${t.toPx}px)`, opacity: 1, offset: t.rollFraction },
          { transform: `translateY(${t.toPx}px)`, opacity: 0, offset: 1 },
        ],
        { duration: t.totalMs, iterations: Infinity, easing: "linear" },
      );
    });
  };

  const close = (): void => {
    if (overlay.hidden) return;
    stopRolling();
    overlay.hidden = true;
    overlay.remove();
    unregisterBack();
    document.removeEventListener("keydown", onKeyDown);
    opener?.focus();
    opener = null;
  };

  const onKeyDown = (e: KeyboardEvent): void => {
    if (e.key === "Escape") {
      e.preventDefault();
      close();
      return;
    }
    if (e.key === "ArrowDown") {
      stopRolling();
      return;
    }
    if (e.key !== "Tab") return;
    const focusable = [...Array.from(track.querySelectorAll<HTMLElement>("a[href]")), closeBtn];
    const first = focusable[0]!;
    const last = focusable[focusable.length - 1]!;
    const active = document.activeElement;
    if (e.shiftKey && (active === first || !dialog.contains(active))) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && (active === last || !dialog.contains(active))) {
      e.preventDefault();
      first.focus();
    }
  };

  viewport.addEventListener("wheel", stopRolling, { passive: true });
  viewport.addEventListener("pointerdown", stopRolling);
  viewport.addEventListener("focusin", stopRolling);
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) close();
  });
  closeBtn.addEventListener("click", close);

  return {
    open: (openedFrom) => {
      if (!overlay.hidden) return;
      opener = openedFrom;
      container.appendChild(overlay);
      overlay.hidden = false;
      document.addEventListener("keydown", onKeyDown);
      unregisterBack();
      unregisterBack = options.backDismiss?.push(close) ?? ((): void => {});
      closeBtn.focus();
      startRolling();
    },
    close,
    isOpen: () => !overlay.hidden,
  };
}
