import { ArrowLeft } from "lucide";

import { setIconButton } from "./icons";
import type { ShowToast } from "./toast";

export interface StorageLocationInfo {
  path: string;
  isAppStorage: boolean;
}

export interface SettingsStorageCallbacks {
  /** Reads the current storage location fresh each time (main.ts's setup IPC is the source of truth, not a value cached at construction). */
  getCurrentPath: () => Promise<StorageLocationInfo>;
  /**
   * Reopens the setup screen in its cancelable mode and, if the user
   * actually changes the location, does whatever the app needs to do to
   * reflect that (BEHAVIOR_SPEC.md §3: "Returning from it refreshes the
   * QuKi list"). Resolves once that's all settled, whether or not the
   * user actually changed anything.
   */
  onChangeLocation: () => Promise<void>;
}

export interface SettingsViewCallbacks {
  onBack: () => void;
  onOpenTrash: () => void;
  showToast: ShowToast;
  /**
   * Present only on Electron, where there's a real folder to show and
   * change. Absent entirely on the web build - per STORAGE_CONTRACT.md the
   * web app is OPFS-only with no folder picker and no storage-location
   * onboarding at all, so that build keeps showing the generic STORAGE_NOTE
   * below unchanged.
   */
  storage?: SettingsStorageCallbacks;
}

export interface SettingsView {
  element: HTMLElement;
}

/**
 * PROPOSAL: the web build's Storage section copy. The original app's
 * "current location" / "Change location" language doesn't apply there -
 * per STORAGE_CONTRACT.md, the web app is OPFS-only with no folder picker
 * and no storage-location onboarding at all. This wording is adapted, not
 * spec'd verbatim.
 */
const STORAGE_NOTE =
  "QuKis are stored in this browser, not in a folder you choose. Clearing this site's browser data will delete them.";

// Ported verbatim from lib/features/settings/settings_screen.dart's Storage
// ListTile, which switches title and (colour-coded) subtitle on isAppStorage
// rather than always showing a plain path.
//
// isAppStorage reflects the resolved storage path's actual guarantees
// (survives uninstall or not, visible outside the app or not), not which
// setup-screen card the user happened to click - see electron/src/main.ts's
// getState handler (always false: Electron has no private storage tier at
// all) and androidSetupApi.ts's isUnderPrivateStorage (true for any path
// inside the app's real private data directory, including one reached via
// Flutter migration rather than the "Use app storage" card). So the
// private/uninstall-removal copy below only ever renders where it's
// actually true.
const FILESYSTEM_STORAGE_TITLE = "Filesystem storage";
const APP_STORAGE_TITLE = "App storage (private)";
const APP_STORAGE_SUBTITLE = "Files will be removed on uninstall. Change location.";

export function createSettingsView(container: HTMLElement, callbacks: SettingsViewCallbacks): SettingsView {
  const storageSectionHtml = callbacks.storage
    ? `
      <section class="settings-section">
        <h2>Storage</h2>
        <div class="settings-row settings-row-stacked storage-status">
          <span class="storage-status-title"></span>
          <span class="storage-status-subtitle storage-location-value">…</span>
        </div>
        <button type="button" class="settings-row settings-link change-location-btn">
          <span>Change location</span>
        </button>
      </section>
    `
    : `
      <section class="settings-section">
        <h2>Storage</h2>
        <p class="settings-note">${STORAGE_NOTE}</p>
      </section>
    `;

  container.innerHTML = `
    <header class="view-header">
      <button type="button" class="back-btn"></button>
      <h1>Settings</h1>
    </header>
    <div class="settings-body">
      <section class="settings-section">
        <h2>Appearance</h2>
        <div class="settings-row">
          <span>Theme</span>
          <span class="settings-value">System</span>
        </div>
      </section>
      ${storageSectionHtml}
      <section class="settings-section">
        <h2>Notes</h2>
        <button type="button" class="settings-row settings-link trash-btn">
          <span>Trash</span>
        </button>
      </section>
      <section class="settings-section">
        <h2>About</h2>
        <div class="settings-row">
          <span>QuKi Notes</span>
        </div>
        <button type="button" class="settings-row settings-link version-btn">
          <span>Version</span>
          <span class="settings-value">${__APP_VERSION__}</span>
        </button>
      </section>
    </div>
  `;

  const backBtn = container.querySelector<HTMLButtonElement>(".back-btn")!;
  setIconButton(backBtn, ArrowLeft, "Back");
  const trashBtn = container.querySelector<HTMLButtonElement>(".trash-btn")!;
  const versionBtn = container.querySelector<HTMLButtonElement>(".version-btn")!;

  backBtn.addEventListener("click", () => callbacks.onBack());
  trashBtn.addEventListener("click", () => callbacks.onOpenTrash());

  if (callbacks.storage) {
    const storage = callbacks.storage;
    const statusTitleEl = container.querySelector<HTMLElement>(".storage-status-title")!;
    const locationValueEl = container.querySelector<HTMLElement>(".storage-location-value")!;
    const changeLocationBtn = container.querySelector<HTMLButtonElement>(".change-location-btn")!;

    const refreshLocation = (): void => {
      void storage.getCurrentPath().then(
        ({ path, isAppStorage }) => {
          statusTitleEl.textContent = isAppStorage ? APP_STORAGE_TITLE : FILESYSTEM_STORAGE_TITLE;
          locationValueEl.textContent = isAppStorage ? APP_STORAGE_SUBTITLE : path;
          locationValueEl.classList.toggle("storage-status-warning", isAppStorage);
        },
        () => {
          statusTitleEl.textContent = FILESYSTEM_STORAGE_TITLE;
          locationValueEl.textContent = "Unknown";
          locationValueEl.classList.remove("storage-status-warning");
        },
      );
    };
    refreshLocation();

    changeLocationBtn.addEventListener("click", () => {
      void (async () => {
        changeLocationBtn.disabled = true;
        try {
          await storage.onChangeLocation();
        } finally {
          changeLocationBtn.disabled = false;
        }
        refreshLocation();
      })();
    });
  }

  // BEHAVIOR_SPEC.md §7: "Tapping copies the version string to the
  // clipboard and confirms with 'Copied to clipboard.'" (the same copy
  // used by the Help dialog's version tap, which is out of scope here).
  versionBtn.addEventListener("click", () => {
    void (async () => {
      try {
        await navigator.clipboard.writeText(__APP_VERSION__);
        callbacks.showToast("Copied to clipboard.", 2000);
      } catch (error) {
        console.error("QuKi version copy-to-clipboard failed:", error);
      }
    })();
  });

  return { element: container };
}
