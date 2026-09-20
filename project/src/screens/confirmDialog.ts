export interface ConfirmOptions {
  title: string;
  message?: string;
  confirmLabel: string;
  cancelLabel: string;
  danger?: boolean;
}

export type Confirm = (options: ConfirmOptions) => Promise<boolean>;

/**
 * A minimal reusable modal for the two confirmations chunk 2 needs:
 * Trash's "Restore note?" (BEHAVIOR_SPEC.md §6) and permanent-delete /
 * empty-trash, neither of which the spec gives exact copy for beyond
 * "Restore note?" itself - see the PROPOSAL notes at each call site.
 */
export function createConfirmDialog(container: HTMLElement): Confirm {
  const overlay = document.createElement("div");
  overlay.className = "confirm-overlay";
  overlay.hidden = true;
  overlay.innerHTML = `
    <div class="confirm-dialog" role="alertdialog" aria-modal="true">
      <h2 class="confirm-title"></h2>
      <p class="confirm-message"></p>
      <div class="confirm-actions">
        <button type="button" class="confirm-cancel"></button>
        <button type="button" class="confirm-confirm"></button>
      </div>
    </div>
  `;
  container.appendChild(overlay);

  const titleEl = overlay.querySelector<HTMLHeadingElement>(".confirm-title")!;
  const messageEl = overlay.querySelector<HTMLParagraphElement>(".confirm-message")!;
  const cancelBtn = overlay.querySelector<HTMLButtonElement>(".confirm-cancel")!;
  const confirmBtn = overlay.querySelector<HTMLButtonElement>(".confirm-confirm")!;

  return (options: ConfirmOptions): Promise<boolean> =>
    new Promise<boolean>((resolve) => {
      titleEl.textContent = options.title;
      messageEl.textContent = options.message ?? "";
      messageEl.hidden = !options.message;
      cancelBtn.textContent = options.cancelLabel;
      confirmBtn.textContent = options.confirmLabel;
      confirmBtn.classList.toggle("danger", options.danger === true);

      const cleanup = (result: boolean): void => {
        overlay.hidden = true;
        cancelBtn.removeEventListener("click", onCancel);
        confirmBtn.removeEventListener("click", onConfirm);
        overlay.removeEventListener("click", onOverlayClick);
        resolve(result);
      };
      const onCancel = (): void => cleanup(false);
      const onConfirm = (): void => cleanup(true);
      const onOverlayClick = (e: MouseEvent): void => {
        if (e.target === overlay) cleanup(false);
      };

      cancelBtn.addEventListener("click", onCancel);
      confirmBtn.addEventListener("click", onConfirm);
      overlay.addEventListener("click", onOverlayClick);

      overlay.hidden = false;
      confirmBtn.focus();
    });
}
