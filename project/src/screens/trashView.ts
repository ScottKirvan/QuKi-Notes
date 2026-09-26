import { ArrowLeft, Trash2 } from "lucide";
import type { QuKiStore, TrashedQuKiSummary } from "quki-core";

import { extractPreview } from "../preview";
import { formatRelativeTime } from "../relativeTime";
import type { Confirm } from "./confirmDialog";
import { createIcon, setIconButton } from "./icons";
import { attachSwipeToDelete } from "./swipeToDelete";
import type { ShowToast } from "./toast";

export interface TrashViewCallbacks {
  onBack: () => void;
  showToast: ShowToast;
  confirm: Confirm;
}

export interface TrashView {
  element: HTMLElement;
  /** BEHAVIOR_SPEC.md §6: "Refreshes on open." */
  open: () => Promise<void>;
}

/**
 * PROPOSAL: the permanent-delete confirmation copy ("Delete forever?" /
 * "This permanently deletes the QuKi. This can't be undone.") is not given
 * verbatim anywhere in the spec - only "Restore note?" is. This is a
 * reasonable placeholder, not settled copy.
 *
 * PROPOSAL: "Empty Trash" also gets a confirmation, on the same reasoning
 * as permanent single delete - it's irreversible and bulk. The spec is
 * silent on whether this one needs a confirmation at all.
 */
export function createTrashView(store: QuKiStore, container: HTMLElement, callbacks: TrashViewCallbacks): TrashView {
  container.innerHTML = `
    <header class="view-header">
      <button type="button" class="back-btn"></button>
      <h1>Trash</h1>
      <div class="view-actions">
        <button type="button" class="empty-trash-btn">Empty Trash</button>
      </div>
    </header>
    <div class="list-body"></div>
  `;

  const backBtn = container.querySelector<HTMLButtonElement>(".back-btn")!;
  const emptyTrashBtn = container.querySelector<HTMLButtonElement>(".empty-trash-btn")!;
  const listBody = container.querySelector<HTMLDivElement>(".list-body")!;

  setIconButton(backBtn, ArrowLeft, "Back to Settings");

  async function refresh(): Promise<void> {
    const items = await store.listTrash();
    render(items);
  }

  function render(items: TrashedQuKiSummary[]): void {
    listBody.innerHTML = "";
    if (items.length === 0) {
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "No notes in Trash.";
      listBody.appendChild(empty);
      return;
    }
    for (const item of items) listBody.appendChild(renderRow(item));
  }

  function renderRow(item: TrashedQuKiSummary): HTMLElement {
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
    preview.textContent = "…";

    const time = document.createElement("div");
    time.className = "list-row-time";
    time.textContent = formatRelativeTime(item.modifiedAt);

    main.append(preview, time);
    content.append(main);
    row.append(swipeBg, content);

    store.readTrash(item.id).then(
      (detail) => {
        preview.textContent = extractPreview(detail.body);
      },
      () => {
        preview.textContent = extractPreview(null);
      },
    );

    const restore = async (): Promise<void> => {
      const confirmed = await callbacks.confirm({
        title: "Restore note?",
        confirmLabel: "Restore",
        cancelLabel: "Cancel",
      });
      if (!confirmed) return;
      await store.restore(item.id);
      await refresh();
      callbacks.onBack();
    };

    content.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        void restore();
      }
    });

    // BEHAVIOR_SPEC.md §6: "Swipe → confirmation, then permanent deletion"
    // - unlike the list, the swipe alone doesn't delete; it leads to the
    // same confirmation the row's permanent-delete affordance always used.
    // Declining re-renders the list, which puts the row back since nothing
    // was actually deleted.
    attachSwipeToDelete(content, {
      onTap: () => void restore(),
      onCommit: () => {
        void (async () => {
          const confirmed = await callbacks.confirm({
            title: "Delete forever?",
            message: "This permanently deletes the QuKi. This can't be undone.",
            confirmLabel: "Delete",
            cancelLabel: "Cancel",
            danger: true,
          });
          if (!confirmed) {
            await refresh();
            return;
          }
          await store.permanentlyDelete(item.id);
          await refresh();
        })();
      },
    });

    return row;
  }

  backBtn.addEventListener("click", () => callbacks.onBack());
  emptyTrashBtn.addEventListener("click", () => {
    void (async () => {
      const confirmed = await callbacks.confirm({
        title: "Empty Trash?",
        message: "This permanently deletes everything in Trash. This can't be undone.",
        confirmLabel: "Empty Trash",
        cancelLabel: "Cancel",
        danger: true,
      });
      if (!confirmed) return;
      await store.emptyTrash();
      await refresh();
    })();
  });

  return {
    element: container,
    open: refresh,
  };
}
