export interface BackDismissStack {
  /** Registers an open dialog's cancel action; returns the function that unregisters it once the dialog closes. */
  push(dismiss: () => void): () => void;
  /**
   * Runs the cancel action of the most recently opened dialog still open.
   * Returns false when none is open. The dialog stays registered until it
   * unregisters itself, so one that ignores the cancel (busy) still swallows Back.
   */
  dismissTop(): boolean;
}

export function createBackDismissStack(): BackDismissStack {
  const open: Array<() => void> = [];

  return {
    push(dismiss) {
      const entry = (): void => dismiss();
      open.push(entry);
      return () => {
        const index = open.indexOf(entry);
        if (index !== -1) open.splice(index, 1);
      };
    },
    dismissTop() {
      const top = open[open.length - 1];
      if (top === undefined) return false;
      top();
      return true;
    },
  };
}
