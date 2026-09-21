import { buildLineParts, formatBuildString, type BuildInfo } from "../buildInfo";
import type { ShowToast } from "./toast";

export interface AboutDialogOptions {
  version: string;
  buildInfo: BuildInfo;
  showToast: ShowToast;
}

export interface AboutDialog {
  /** `opener` is the element that gets focus back on close; Safari does not focus a button on click, so activeElement can't be trusted to name it. */
  open: (opener: HTMLElement) => void;
  close: () => void;
}

const ICON_URL = "/icons/icon-192.png";

export function createAboutDialog(container: HTMLElement, options: AboutDialogOptions): AboutDialog {
  const buildString = formatBuildString(options.version, options.buildInfo);

  const overlay = document.createElement("div");
  overlay.className = "confirm-overlay about-overlay";
  overlay.hidden = true;
  overlay.innerHTML = `
    <div class="confirm-dialog about-dialog" role="dialog" aria-modal="true" aria-labelledby="about-title">
      <div class="about-header">
        <img class="about-icon" src="${ICON_URL}" alt="" width="64" height="64" />
        <div class="about-heading">
          <h2 id="about-title" class="about-name">QuKi Notes</h2>
          <button type="button" class="about-copy" title="Copy build information">
            <span class="about-version"></span>
            <span class="about-build"></span>
          </button>
        </div>
      </div>
      <div class="confirm-actions">
        <button type="button" class="about-close">Close</button>
      </div>
    </div>
  `;
  container.appendChild(overlay);

  overlay.querySelector<HTMLElement>(".about-version")!.textContent = `Version ${options.version}`;
  const buildEl = overlay.querySelector<HTMLElement>(".about-build")!;
  const parts = buildLineParts(options.buildInfo);
  parts.forEach((part, index) => {
    const isLast = index === parts.length - 1;
    const span = document.createElement("span");
    span.className = "about-build-part";
    span.textContent = isLast ? part : `${part} ·`;
    buildEl.append(span, isLast ? "" : " ");
  });
  const copyBtn = overlay.querySelector<HTMLButtonElement>(".about-copy")!;
  const closeBtn = overlay.querySelector<HTMLButtonElement>(".about-close")!;

  let opener: HTMLElement | null = null;

  const close = (): void => {
    if (overlay.hidden) return;
    overlay.hidden = true;
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
    if (e.key !== "Tab") return;
    const first = copyBtn;
    const last = closeBtn;
    const active = document.activeElement;
    if (e.shiftKey && (active === first || !overlay.contains(active))) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && (active === last || !overlay.contains(active))) {
      e.preventDefault();
      first.focus();
    }
  };

  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) close();
  });
  closeBtn.addEventListener("click", close);
  copyBtn.addEventListener("click", () => {
    void (async () => {
      try {
        await navigator.clipboard.writeText(buildString);
        options.showToast("Copied to clipboard.", 2000);
      } catch (error) {
        console.error("QuKi build info copy-to-clipboard failed:", error);
      }
    })();
  });

  return {
    open: (openedFrom) => {
      opener = openedFrom;
      overlay.hidden = false;
      document.addEventListener("keydown", onKeyDown);
      closeBtn.focus();
    },
    close,
  };
}
