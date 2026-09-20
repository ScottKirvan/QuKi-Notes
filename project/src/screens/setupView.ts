import type { ElectronSetupApi } from "../electronSetupApi";

export interface SetupViewShowOptions {
  /**
   * First launch has no cancel option - a choice is mandatory
   * (BEHAVIOR_SPEC.md §3). Settings -> Change location reopens the same
   * screen with this set true.
   */
  cancelable: boolean;
  onError?: (message: string) => void;
  /**
   * [Proposed — unconfirmed] Set when this screen is being shown because a
   * previously-chosen storage location is not currently reachable (see
   * project/electron/src/main.ts's app.whenReady() and
   * electronSetupApi.ts's StorageLocationState.unreachablePath) - not
   * BEHAVIOR_SPEC.md §3's genuine first-launch case. Swaps the title/
   * subtitle copy so a returning user isn't told "Where should QuKis be
   * saved? Choose once..." as if their whole library is gone; it almost
   * certainly isn't - the folder just isn't reachable from this launch
   * (unplugged drive, unmounted network share, moved folder).
   */
  recovery?: { unreachablePath: string };
}

export interface SetupView {
  /**
   * Resolves with the newly chosen absolute path, or null if shown
   * cancelable and the user backed out without choosing. Never resolves
   * null when cancelable is false - the caller can only get here by an
   * actual choice being made.
   */
  show(options: SetupViewShowOptions): Promise<string | null>;
}

/**
 * BEHAVIOR_SPEC.md §3's setup screen. Not part of the Navigator push/pop
 * stack (§2/§3: "this replaces the whole app UI until resolved" on first
 * launch) - rendered as a full-screen overlay appended to the shared
 * overlay host, the same layer toast/confirmDialog already use, rather than
 * as one of Navigator's managed view sections.
 */
export function createSetupView(container: HTMLElement, api: ElectronSetupApi): SetupView {
  const overlay = document.createElement("div");
  overlay.className = "setup-overlay";
  overlay.hidden = true;
  overlay.innerHTML = `
    <div class="setup-panel">
      <button type="button" class="back-btn setup-cancel-btn" aria-label="Cancel" hidden>&larr;</button>
      <h1 class="setup-title">Where should QuKis be saved?</h1>
      <p class="setup-subtitle">Choose once. You can change this later in Settings.</p>
      <div class="setup-cards">
        <button type="button" class="setup-card setup-card-filesystem">
          <h2>Filesystem storage</h2>
          <p>Choose a folder on this computer.</p>
        </button>
        <button type="button" class="setup-card setup-card-appstorage">
          <h2>Use app storage</h2>
          <p>QuKis are kept private to this app. They will be removed if you uninstall.</p>
        </button>
      </div>
    </div>
  `;
  container.appendChild(overlay);

  const titleEl = overlay.querySelector<HTMLHeadingElement>(".setup-title")!;
  const subtitleEl = overlay.querySelector<HTMLParagraphElement>(".setup-subtitle")!;
  const cancelBtn = overlay.querySelector<HTMLButtonElement>(".setup-cancel-btn")!;
  const filesystemBtn = overlay.querySelector<HTMLButtonElement>(".setup-card-filesystem")!;
  const appStorageBtn = overlay.querySelector<HTMLButtonElement>(".setup-card-appstorage")!;

  const FIRST_LAUNCH_TITLE = "Where should QuKis be saved?";
  const FIRST_LAUNCH_SUBTITLE = "Choose once. You can change this later in Settings.";

  // [Proposed — unconfirmed] Exact wording isn't specified anywhere in the
  // docs - this is a first attempt, not a confirmed decision. Says plainly
  // what happened (a known folder isn't reachable) and that the QuKis are
  // probably still there, rather than implying a totally fresh, empty app.
  const RECOVERY_TITLE = "Your QuKi location isn't available";
  function recoverySubtitle(unreachablePath: string): string {
    return (
      `QuKi Notes was set up to use "${unreachablePath}", but that location can't be reached right now ` +
      `— for example an unplugged drive or a disconnected network location. Your QuKis are most likely still ` +
      `there. Reconnect it and relaunch, or choose a different location below.`
    );
  }

  function setBusy(busy: boolean): void {
    filesystemBtn.disabled = busy;
    appStorageBtn.disabled = busy;
    cancelBtn.disabled = busy;
  }

  return {
    show(options: SetupViewShowOptions): Promise<string | null> {
      return new Promise<string | null>((resolve) => {
        titleEl.textContent = options.recovery ? RECOVERY_TITLE : FIRST_LAUNCH_TITLE;
        subtitleEl.textContent = options.recovery ? recoverySubtitle(options.recovery.unreachablePath) : FIRST_LAUNCH_SUBTITLE;
        cancelBtn.hidden = !options.cancelable;
        setBusy(false);
        overlay.hidden = false;

        const cleanup = (): void => {
          overlay.hidden = true;
          filesystemBtn.removeEventListener("click", onFilesystem);
          appStorageBtn.removeEventListener("click", onAppStorage);
          cancelBtn.removeEventListener("click", onCancel);
        };

        const onFilesystem = (): void => {
          setBusy(true);
          api.chooseFilesystem().then(
            (path) => {
              setBusy(false);
              // BEHAVIOR_SPEC.md §3: "cancelling leaves the user on this
              // screen" - a null path means the native picker was
              // dismissed, nothing was saved, so this stays open rather
              // than resolving.
              if (path === null) return;
              cleanup();
              resolve(path);
            },
            (error: unknown) => {
              setBusy(false);
              console.error("QuKi setup: chooseFilesystem failed unexpectedly:", error);
              options.onError?.("Could not open the folder picker — an unexpected error occurred.");
            },
          );
        };
        const onAppStorage = (): void => {
          setBusy(true);
          api.chooseAppStorage().then(
            (path) => {
              setBusy(false);
              cleanup();
              resolve(path);
            },
            (error: unknown) => {
              setBusy(false);
              console.error("QuKi setup: chooseAppStorage failed unexpectedly:", error);
              options.onError?.("Could not set up app storage — an unexpected error occurred.");
            },
          );
        };
        const onCancel = (): void => {
          cleanup();
          resolve(null);
        };

        filesystemBtn.addEventListener("click", onFilesystem);
        appStorageBtn.addEventListener("click", onAppStorage);
        cancelBtn.addEventListener("click", onCancel);
      });
    },
  };
}
