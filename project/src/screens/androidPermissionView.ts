import { FolderCheck } from "lucide";

import type { StorageAccessState } from "../androidStorageAccess.js";
import { setIconButton } from "./icons";

export interface AndroidPermissionView {
  /**
   * Reflects a StorageAccessGate state onto the screen. "granted" hides it;
   * "checking" leaves whatever is currently shown alone, so the brief
   * recheck after a foreground resume doesn't flicker the panel away and
   * back; "needs-permission"/"waiting-for-settings" show it with the
   * button enabled/disabled accordingly.
   */
  render(state: StorageAccessState): void;
}

/**
 * [Proposed — unconfirmed] BEHAVIOR_SPEC.md §3 only specifies the Android
 * all-files-access *flow*, not this screen's copy — there is no reference
 * app equivalent (storage_setup_screen.dart never shows an explanatory
 * screen; it silently loops between the permission check and the system
 * settings screen). This is a first attempt at wording, not a confirmed
 * decision: explain plainly why the permission is needed and what to do,
 * distinguish "not yet granted" from "waiting for you to come back," and
 * never leave the user looking at a dead end if they back out of Settings
 * without granting it.
 *
 * Rendered into the same shared overlay host setupView.ts/confirmDialog.ts
 * use, as a full-screen panel that replaces the whole app UI until
 * resolved — this runs before any backend, QuKiStore or editor exists, the
 * same ordering setupView.ts's first-launch case requires on Electron.
 */
export function createAndroidPermissionView(container: HTMLElement, onRequestAccess: () => void): AndroidPermissionView {
  const overlay = document.createElement("div");
  overlay.className = "android-permission-overlay";
  overlay.hidden = true;
  overlay.innerHTML = `
    <div class="android-permission-panel">
      <h1 class="android-permission-title">QuKi Notes needs access to your files</h1>
      <p class="android-permission-body">
        To save your QuKis as files in your device's Documents folder, QuKi Notes needs
        "Allow management of all files" permission. Grant it on the next screen, then switch back to QuKi Notes.
      </p>
      <button type="button" class="android-permission-btn"></button>
      <p class="android-permission-waiting" hidden>Waiting for you to grant access in Settings&hellip;</p>
    </div>
  `;
  container.appendChild(overlay);

  const button = overlay.querySelector<HTMLButtonElement>(".android-permission-btn")!;
  const waitingEl = overlay.querySelector<HTMLParagraphElement>(".android-permission-waiting")!;
  setIconButton(button, FolderCheck, "Grant access", 24);

  button.addEventListener("click", () => onRequestAccess());

  return {
    render(state: StorageAccessState): void {
      if (state === "granted") {
        overlay.hidden = true;
        return;
      }
      if (state === "checking") return;

      overlay.hidden = false;
      const waiting = state === "waiting-for-settings";
      button.disabled = waiting;
      waitingEl.hidden = !waiting;
    },
  };
}
