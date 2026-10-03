import type { ToastAction } from "./toast";

export interface SaveStatusBanner {
  show: (message: string, action?: ToastAction) => void;
  hide: () => void;
}

/**
 * The persistent "Could not save…" / conflict banner (main.ts's #save-status)
 * and, since the fix for a startup failure leaving a blank window, the
 * "QuKi Notes could not start…" banner too - both are "stays until explicitly
 * cleared or replaced" messages, unlike screens/toast.ts's auto-dismissing
 * toast. Extracted out of main.ts (which used to build this inline) so the
 * mechanism itself - not just its call sites - can be unit tested without a
 * real browser, the same way screens/icons.test.ts tests DOM-touching code
 * with a hand-rolled document stub rather than a jsdom dependency.
 *
 * `container` is nullable because main.ts queries it with
 * `document.querySelector`, which can return null; every method becomes a
 * no-op in that case, matching the guard the inline version had.
 */
export function createSaveStatusBanner(container: HTMLElement | null): SaveStatusBanner {
  let messageEl: HTMLSpanElement | null = null;
  let actionBtn: HTMLButtonElement | null = null;

  function ensureChildren(): void {
    if (!container || messageEl) return;
    messageEl = document.createElement("span");
    container.appendChild(messageEl);
    actionBtn = document.createElement("button");
    actionBtn.type = "button";
    actionBtn.className = "save-status-action";
    actionBtn.hidden = true;
    container.appendChild(actionBtn);
  }

  return {
    show(message: string, action?: ToastAction): void {
      if (!container) return;
      ensureChildren();
      messageEl!.textContent = message;
      container.hidden = false;

      if (action) {
        actionBtn!.textContent = action.label;
        actionBtn!.hidden = false;
        actionBtn!.onclick = (): void => action.onClick();
      } else {
        actionBtn!.hidden = true;
        actionBtn!.textContent = "";
        actionBtn!.onclick = null;
      }
    },
    hide(): void {
      if (!container) return;
      container.hidden = true;
      if (actionBtn) {
        actionBtn.hidden = true;
        actionBtn.onclick = null;
      }
    },
  };
}
