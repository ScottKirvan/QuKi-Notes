import { countText, formatCount } from "../wordCount";

export interface WordCountReadout {
  setEnabled(enabled: boolean): void;
  /** Call when the text changes; the count is redrawn on the next frame. */
  refresh(): void;
  /** Call when the toolbar shows or hides, or the editor's size changes. */
  reposition(): void;
}

const GAP_PX = 4;
const EDGE_PX = 8;

/**
 * The optional word and character count in the editor's lower right corner,
 * sitting just above the formatting toolbar while it shows. Taps pass
 * through it to the text underneath.
 */
export function createWordCountReadout(
  container: HTMLElement,
  scroller: HTMLElement,
  text: () => string,
  toolbarHeight: () => number,
  enabled: boolean,
): WordCountReadout {
  const element = document.createElement("div");
  element.className = "word-count";
  element.setAttribute("aria-live", "polite");
  element.hidden = !enabled;
  container.appendChild(element);

  let frame: number | null = null;

  function draw(): void {
    element.textContent = formatCount(countText(text()));
  }

  function reposition(): void {
    if (element.hidden) return;
    element.style.bottom = `${toolbarHeight() + GAP_PX}px`;
    const scrollbar = scroller.offsetWidth - scroller.clientWidth;
    element.style.right = `${scrollbar + EDGE_PX}px`;
  }

  if (enabled) {
    draw();
    reposition();
  }

  return {
    setEnabled(next: boolean): void {
      element.hidden = !next;
      if (next) {
        draw();
        reposition();
      }
    },
    refresh(): void {
      if (element.hidden || frame !== null) return;
      frame = requestAnimationFrame(() => {
        frame = null;
        draw();
      });
    },
    reposition,
  };
}
