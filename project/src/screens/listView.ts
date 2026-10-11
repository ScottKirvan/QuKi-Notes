import { ArrowLeft, CircleHelp, Plus, Settings, Trash2 } from "lucide";
import { findMatches, type QuKiStore, type SearchMatch, type SnippetRange } from "quki-core";

import { guardLatest } from "../asyncGuard";
import { extractPreview } from "../preview";
import { formatRelativeTime } from "../relativeTime";
import { createIcon, setIconButton } from "./icons";
import { attachSwipeToDelete } from "./swipeToDelete";

export interface ListViewCallbacks {
  /** Flushes the current editor, opens the given QuKi, and returns to the editor. */
  onOpenQuKi: (id: string) => Promise<void>;
  /** Flushes the current editor and resets it to a blank, unsaved QuKi. */
  onNewQuKi: () => Promise<void>;
  onOpenSettings: () => void;
  /** BEHAVIOR_SPEC.md §5: the list's own Help action, opening the same help/about dialog as the editor's. */
  onOpenHelp: (opener: HTMLElement) => void;
  /** Moves a QuKi to Trash; if it's the one open in the editor, resets the editor first. */
  onDeleteQuKi: (id: string) => Promise<void>;
  onBack: () => void;
}

export interface ListView {
  element: HTMLElement;
  /** BEHAVIOR_SPEC.md §5: "The list refreshes from the folder each time it opens." */
  open: () => Promise<void>;
}

function showHighlighted(target: HTMLElement, text: string, highlights: readonly SnippetRange[]): void {
  target.replaceChildren();
  let at = 0;
  for (const { start, end } of highlights) {
    if (start > at) target.append(text.slice(at, start));
    const hit = document.createElement("mark");
    hit.className = "search-hit";
    hit.textContent = text.slice(start, end);
    target.append(hit);
    at = end;
  }
  if (at < text.length) target.append(text.slice(at));
}

interface ListEntry extends SearchMatch {
  preview: string | null;
}

export function createListView(store: QuKiStore, container: HTMLElement, callbacks: ListViewCallbacks): ListView {
  container.innerHTML = `
    <header class="view-header">
      <button type="button" class="back-btn"></button>
      <h1>QuKis</h1>
      <div class="view-actions">
        <button type="button" class="new-btn"></button>
        <button type="button" class="help-btn"></button>
        <button type="button" class="settings-btn"></button>
      </div>
    </header>
    <div class="search-bar">
      <input type="search" class="search-input" placeholder="Search QuKis" aria-label="Search QuKis" />
    </div>
    <div class="list-body"></div>
  `;

  const backBtn = container.querySelector<HTMLButtonElement>(".back-btn")!;
  const newBtn = container.querySelector<HTMLButtonElement>(".new-btn")!;
  const helpBtn = container.querySelector<HTMLButtonElement>(".help-btn")!;
  const settingsBtn = container.querySelector<HTMLButtonElement>(".settings-btn")!;
  const searchInput = container.querySelector<HTMLInputElement>(".search-input")!;
  const listBody = container.querySelector<HTMLDivElement>(".list-body")!;

  setIconButton(backBtn, ArrowLeft, "Back to editor");
  setIconButton(newBtn, Plus, "New");
  setIconButton(helpBtn, CircleHelp, "Help");
  setIconButton(settingsBtn, Settings, "Settings");
  helpBtn.addEventListener("click", () => callbacks.onOpenHelp(helpBtn));

  let currentQuery = "";

  // BEHAVIOR_SPEC.md §5: "the preview is read from the file per row". Every
  // preview is read before any row is drawn, so the rows on screen are
  // replaced in one step rather than blanking to placeholders first.
  async function readPreview(id: string): Promise<string> {
    try {
      return extractPreview((await store.read(id)).body);
    } catch {
      return extractPreview(null);
    }
  }

  const guardedFetch = guardLatest(async (query: string): Promise<ListEntry[]> => {
    const matches: SearchMatch[] =
      query === ""
        ? (await store.list()).map((item) => ({ item, snippet: null }))
        : await store.searchWithSnippets(query);
    return Promise.all(
      matches.map(async (match) => ({
        ...match,
        preview: match.snippet?.onFirstLine ? null : await readPreview(match.item.id),
      })),
    );
  });

  async function refresh(): Promise<void> {
    const query = currentQuery;
    const results = await guardedFetch(query);
    if (results === undefined) return; // a newer search superseded this one
    renderRows(results, query);
  }

  function renderRows(entries: ListEntry[], query: string): void {
    if (entries.length === 0) {
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent =
        query === "" ? "No QuKis yet.\nTap + to capture your first thought." : `No results for "${query}".`;
      listBody.replaceChildren(empty);
      return;
    }
    listBody.replaceChildren(...entries.map((entry) => renderRow(entry, query)));
  }

  function renderRow({ item, snippet, preview: previewText }: ListEntry, query: string): HTMLElement {
    const row = document.createElement("div");
    row.className = "list-row";

    const swipeBg = document.createElement("div");
    swipeBg.className = "list-row-swipe-bg";
    swipeBg.setAttribute("aria-hidden", "true");
    swipeBg.append(createIcon(Trash2, 20));

    const content = document.createElement("div");
    content.className = "list-row-content";
    content.setAttribute("role", "button");
    content.tabIndex = 0;

    const main = document.createElement("div");
    main.className = "list-row-main";

    const preview = document.createElement("div");
    preview.className = "list-row-preview";

    const time = document.createElement("div");
    time.className = "list-row-time";
    time.textContent = formatRelativeTime(item.modifiedAt);

    main.append(preview);
    if (snippet && !snippet.onFirstLine) {
      const matchingLine = document.createElement("div");
      matchingLine.className = "list-row-snippet";
      showHighlighted(matchingLine, snippet.text, snippet.highlights);
      main.append(matchingLine);
    }
    main.append(time);
    content.append(main);
    row.append(swipeBg, content);

    if (snippet?.onFirstLine) {
      showHighlighted(preview, snippet.text, snippet.highlights);
    } else {
      const text = previewText ?? extractPreview(null);
      showHighlighted(preview, text, snippet ? findMatches(text, query) : []);
    }

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
