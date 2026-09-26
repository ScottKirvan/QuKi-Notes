import { BookOpen } from "lucide";

import { buildLineParts, formatBuildString, type BuildInfo } from "../buildInfo";
import { createIcon } from "./icons";
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

// BEHAVIOR_SPEC.md §7's Help dialog link rows: urls, icons, titles and
// descriptions ported verbatim from lib/features/settings/help_dialog.dart
// (Documentation/Discord/GitHub/Buy me a coffee), Flutter's only source for
// them - there is no web equivalent to check them against.
const DOCS_URL = "https://www.scottkirvan.com/QuKi-Notes/";
const DISCORD_URL = "https://discord.gg/TN6XJSNK5Y";
const GITHUB_URL = "https://github.com/ScottKirvan/QuKi-Notes";
const KOFI_URL = "https://ko-fi.com/ScottKirvan";

// Discord and GitHub icon SVGs, copied verbatim (path data included) from
// help_dialog.dart's _kDiscordSvg/_kGithubSvg. Both already carry
// stroke="currentColor", so they follow the surrounding text color the same
// way the app's Lucide icons do - no per-instance color logic needed.
const DISCORD_SVG = `<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" width="100%" height="100%"><path d="M17.59,34.1733c-.89,1.3069-1.8944,2.6152-2.91,3.8267C7.3,37.79,4.5,33,4.5,33A44.83,44.83,0,0,1,9.31,13.48,16.47,16.47,0,0,1,18.69,10l1,2.31A32.6875,32.6875,0,0,1,24,12a32.9643,32.9643,0,0,1,4.33.3l1-2.31a16.47,16.47,0,0,1,9.38,3.51A44.8292,44.8292,0,0,1,43.5,33s-2.8,4.79-10.18,5a47.4193,47.4193,0,0,1-2.86-3.81m6.46-2.9c-3.84,1.9454-7.5555,3.89-12.92,3.89s-9.08-1.9446-12.92-3.89"/><circle cx="17.847" cy="26.23" r="3.35"/><circle cx="30.153" cy="26.23" r="3.35"/></svg>`;
const GITHUB_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4"/><path d="M9 18c-4.51 2-5-2-7-2"/></svg>`;
// Ko-fi's own asset carries no fill/stroke of its own - help_dialog.dart forces
// the color with a ColorFilter (BlendMode.srcIn) instead of baking one into the
// SVG. fill="currentColor" is added here to get the same theme-following color
// on the web, where nothing else applies it; the path data itself is untouched.
const KOFI_SVG = `<svg fill="currentColor" role="img" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><title>Ko-fi</title><path d="M11.351 2.715c-2.7 0-4.986.025-6.83.26C2.078 3.285 0 5.154 0 8.61c0 3.506.182 6.13 1.585 8.493 1.584 2.701 4.233 4.182 7.662 4.182h.83c4.209 0 6.494-2.234 7.637-4a9.5 9.5 0 0 0 1.091-2.338C21.792 14.688 24 12.22 24 9.208v-.415c0-3.247-2.13-5.507-5.792-5.87-1.558-.156-2.65-.208-6.857-.208m0 1.947c4.208 0 5.09.052 6.571.182 2.624.311 4.13 1.584 4.13 4v.39c0 2.156-1.792 3.844-3.87 3.844h-.935l-.156.649c-.208 1.013-.597 1.818-1.039 2.546-.909 1.428-2.545 3.064-5.922 3.064h-.805c-2.571 0-4.831-.883-6.078-3.195-1.09-2-1.298-4.155-1.298-7.506 0-2.181.857-3.402 3.012-3.714 1.533-.233 3.559-.26 6.39-.26m6.547 2.287c-.416 0-.65.234-.65.546v2.935c0 .311.234.545.65.545 1.324 0 2.051-.754 2.051-2s-.727-2.026-2.052-2.026m-10.39.182c-1.818 0-3.013 1.48-3.013 3.142 0 1.533.858 2.857 1.949 3.897.727.701 1.87 1.429 2.649 1.896a1.47 1.47 0 0 0 1.507 0c.78-.467 1.922-1.195 2.623-1.896 1.117-1.039 1.974-2.364 1.974-3.897 0-1.662-1.247-3.142-3.039-3.142-1.065 0-1.792.545-2.338 1.298-.493-.753-1.246-1.298-2.312-1.298"/></svg>`;

interface LinkRowSpec {
  key: string;
  title: string;
  description: string;
  label: string;
  url: string;
  /** Documentation alone renders as the filled/accent primary action in Flutter (FilledButton vs OutlinedButton). */
  accent?: boolean;
}

const LINK_ROWS: LinkRowSpec[] = [
  {
    key: "docs",
    title: "Documentation",
    description: "Official guide and setup instructions.",
    label: "Visit",
    url: DOCS_URL,
    accent: true,
  },
  {
    key: "discord",
    title: "Discord",
    description: "Chat with other QuKi-Notes users and get support.",
    label: "Join",
    url: DISCORD_URL,
  },
  {
    key: "github",
    title: "GitHub",
    description: "Source code, issues, and release notes.",
    label: "View",
    url: GITHUB_URL,
  },
  {
    key: "kofi",
    title: "Buy me a coffee",
    description: "Show your love. Support QuKi-Notes and the author.",
    label: "Give",
    url: KOFI_URL,
  },
];

function iconMarkup(key: string): string {
  // BookOpen goes through the app's own Lucide-icon path (icons.ts) instead
  // of a hand-copied SVG string, so it stays in sync with every other
  // Lucide icon in the app; the other three have no Lucide equivalent and
  // are Flutter's own custom assets, so they're embedded as-is.
  if (key === "docs") return "";
  if (key === "discord") return DISCORD_SVG;
  if (key === "github") return GITHUB_SVG;
  return KOFI_SVG;
}

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
      <div class="about-links">
        ${LINK_ROWS.map(
          (row) => `
          <div class="about-link-row">
            <span class="about-link-icon" data-row="${row.key}">${iconMarkup(row.key)}</span>
            <div class="about-link-text">
              <span class="about-link-title">${row.title}</span>
              <span class="about-link-desc">${row.description}</span>
            </div>
            <a
              class="about-link-btn${row.accent ? " accent" : ""}"
              data-row="${row.key}"
              href="${row.url}"
              target="_blank"
              rel="noopener noreferrer"
            >${row.label}</a>
          </div>`,
        ).join("")}
      </div>
      <div class="confirm-actions">
        <button type="button" class="about-close">Close</button>
      </div>
    </div>
  `;
  container.appendChild(overlay);

  const docsIconHost = overlay.querySelector<HTMLElement>('.about-link-icon[data-row="docs"]');
  if (docsIconHost) docsIconHost.appendChild(createIcon(BookOpen, 20));

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
  const linkBtns = Array.from(overlay.querySelectorAll<HTMLAnchorElement>(".about-link-btn"));
  const closeBtn = overlay.querySelector<HTMLButtonElement>(".about-close")!;

  let opener: HTMLElement | null = null;

  const close = (): void => {
    if (overlay.hidden) return;
    overlay.hidden = true;
    document.removeEventListener("keydown", onKeyDown);
    opener?.focus();
    opener = null;
  };

  const focusOrder: HTMLElement[] = [copyBtn, ...linkBtns, closeBtn];

  const onKeyDown = (e: KeyboardEvent): void => {
    if (e.key === "Escape") {
      e.preventDefault();
      close();
      return;
    }
    if (e.key !== "Tab") return;
    const first = focusOrder[0]!;
    const last = focusOrder[focusOrder.length - 1]!;
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
