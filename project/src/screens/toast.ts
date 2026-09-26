export interface ToastAction {
  label: string;
  onClick: () => void;
}

export type ShowToast = (message: string, durationMs: number, action?: ToastAction) => void;

/**
 * The transient "QuKi moved to Trash." / "Copied to clipboard." messages
 * (BEHAVIOR_SPEC.md §4, §7). A single host element is reused for every
 * call; a new call while one is already showing replaces the message and
 * restarts its own timer rather than stacking multiple toasts.
 *
 * The optional action (BEHAVIOR_SPEC.md §4 Send: "with Retry offered when
 * the failure is retryable") is the one extension beyond a plain message -
 * added here rather than as a second, parallel notification mechanism.
 * Clicking it dismisses the toast immediately, cancelling its own timer,
 * before running the caller's handler.
 */
export function createToast(container: HTMLElement): ShowToast {
  const el = document.createElement("div");
  el.className = "toast";
  el.setAttribute("role", "status");
  el.setAttribute("aria-live", "polite");
  el.hidden = true;

  const messageEl = document.createElement("span");
  el.appendChild(messageEl);

  const actionBtn = document.createElement("button");
  actionBtn.type = "button";
  actionBtn.className = "toast-action";
  actionBtn.hidden = true;
  el.appendChild(actionBtn);

  container.appendChild(el);

  let hideTimer: ReturnType<typeof setTimeout> | null = null;

  return (message: string, durationMs: number, action?: ToastAction): void => {
    if (hideTimer !== null) clearTimeout(hideTimer);
    messageEl.textContent = message;
    el.hidden = false;

    if (action) {
      actionBtn.textContent = action.label;
      actionBtn.hidden = false;
      actionBtn.onclick = (): void => {
        if (hideTimer !== null) {
          clearTimeout(hideTimer);
          hideTimer = null;
        }
        el.hidden = true;
        action.onClick();
      };
    } else {
      actionBtn.hidden = true;
      actionBtn.textContent = "";
      actionBtn.onclick = null;
    }

    hideTimer = setTimeout(() => {
      el.hidden = true;
      hideTimer = null;
    }, durationMs);
  };
}
