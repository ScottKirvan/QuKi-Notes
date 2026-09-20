import type { QuKiStore, QuKiSummary } from "quki-core";

import { guardLatest } from "../asyncGuard";
import { extractPreview } from "../preview";
import { formatRelativeTime } from "../relativeTime";
import { attachSwipeToDelete } from "./swipeToDelete";

export interface ListViewCallbacks {
  /** Flushes the current editor, opens the given QuKi, and returns to the editor. */
  onOpenQuKi: (id: string) => Promise<void>;
  /** Flushes the current editor and resets it to a blank, unsaved QuKi. */
  onNewQuKi: () => Promise<void>;
  onOpenSettings: () => void;
  /** Moves a QuKi to Trash; if it's the one open in the editor, resets the editor first. */
  onDeleteQuKi: (id: string) => Promise<void>;
  onBack: () => void;
}

export interface ListView {
  element: HTMLElement;
  /** BEHAVIOR_SPEC.md §5: "The list refreshes from the folder each time it opens." */
  open: () => Promise<void>;
}

export function createListView(store: QuKiStore, container: HTMLElement, callbacks: ListViewCallbacks): ListView {
  container.innerHTML = `
    <header class="view-header">
      <button type="button" class="back-btn" aria-label="Back to editor">&larr;</button>
      <h1>QuKis</h1>
      <div class="view-actions">
        <button type="button" class="new-btn">New</button>
        <button type="button" class="settings-btn">Settings</button>
      </div>
    </header>
    <div class="search-bar">
      <input type="search" class="search-input" placeholder="Search QuKis" aria-label="Search QuKis" />
    </div>
    <div class="list-body"></div>
  `;

  const backBtn = container.querySelector<HTMLButtonElement>(".back-btn")!;
  const newBtn = container.querySelector<HTMLButtonElement>(".new-btn")!;
  const settingsBtn = container.querySelector<HTMLButtonElement>(".settings-btn")!;
  const searchInput = container.querySelector<HTMLInputElement>(".search-input")!;
  const listBody = container.querySelector<HTMLDivElement>(".list-body")!;

  let currentQuery = "";

  const guardedFetch = guardLatest(
    async (query: string): Promise<QuKiSummary[]> => (query === "" ? store.list() : store.search(query)),
  );

  async function refresh(): Promise<void> {
    const query = currentQuery;
    const results = await guardedFetch(query);
    if (results === undefined) return; // a newer search superseded this one
    renderRows(results, query);
  }

  function renderRows(items: QuKiSummary[], query: string): void {
    listBody.innerHTML = "";
    if (items.length === 0) {
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent =
        query === "" ? "No QuKis yet.\nTap + to capture your first thought." : `No results for "${query}".`;
      listBody.appendChild(empty);
      return;
    }
    for (const item of items) listBody.appendChild(renderRow(item));
  }

  function renderRow(item: QuKiSummary): HTMLElement {
    const row = document.createElement("div");
    row.className = "list-row";

    const swipeBg = document.createElement("div");
    swipeBg.className = "list-row-swipe-bg";
    swipeBg.setAttribute("aria-hidden", "true");
    swipeBg.textContent = "\u{1F5D1}";

    const content = document.createElement("div");
    content.className = "list-row-content";
    content.setAttribute("role", "button");
    content.tabIndex = 0;

    const main = document.createElement("div");
    main.className = "list-row-main";

    const preview = document.createElement("div");
    preview.className = "list-row-preview";
    preview.textContent = "…";

    const time = document.createElement("div");
    time.className = "list-row-time";
    time.textContent = formatRelativeTime(item.modifiedAt);

    main.append(preview, time);
    content.append(main);
    row.append(swipeBg, content);

    // The preview requires reading the body, per row (BEHAVIOR_SPEC.md §5:
    // "the preview is read from the file per row"). A read failure means
    // "unreadable" - extractPreview(null) resolves that to "(empty)".
    store.read(item.id).then(
      (detail) => {
        preview.textContent = extractPreview(detail.body);
      },
      () => {
        preview.textContent = extractPreview(null);
      },
    );

    const open = (): void => {
      void callbacks.onOpenQuKi(item.id);
    };
    content.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        open();
      }
    });

    // BEHAVIOR_SPEC.md §5: "Swiping right-to-left deletes it - red
    // background, trash icon, no confirmation" - matching the same "QuKi
    // moved to Trash." toast delete already uses elsewhere.
    attachSwipeToDelete(content, {
      onTap: open,
      onCommit: () => {
        void callbacks.onDeleteQuKi(item.id).then(() => refresh());
      },
    });

    return row;
  }

  searchInput.addEventListener("input", () => {
    currentQuery = searchInput.value.trim();
    void refresh();
  });
  backBtn.addEventListener("click", () => callbacks.onBack());
  newBtn.addEventListener("click", () => {
    void callbacks.onNewQuKi();
  });
  settingsBtn.addEventListener("click", () => callbacks.onOpenSettings());

  return {
    element: container,
    open: async (): Promise<void> => {
      searchInput.value = "";
      currentQuery = "";
      await refresh();
    },
  };
}
