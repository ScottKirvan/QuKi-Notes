import { ArrowLeft } from "lucide";

import type { StorageAccessState } from "../androidStorageAccess.js";
import type { BackDismissStack } from "../backDismissStack";
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
 *
 * [Proposed — unconfirmed] The back button is a fix for a real dead end: a
 * user who declines "All files access" (or the API <30 runtime permission
 * dialog) had no way off this screen at all before this. It mirrors
 * setupView.ts's own cancel button (ArrowLeft, top-left) rather than
 * completing "use app storage" itself — returning control to
 * onUseAppStorageInstead (main.ts) makes the in-flight chooseFilesystem()
 * resolve null, exactly like a dismissed folder picker, which lands the
 * user back on setupView.ts's own two-card choice screen where "Use app
 * storage" already lives. No reference app equivalent exists to confirm
 * wording or placement against.
 */
export function createAndroidPermissionView(
  container: HTMLElement,
  onRequestAccess: () => void,
  onUseAppStorageInstead: () => void,
  backDismiss?: BackDismissStack,
): AndroidPermissionView {
  const overlay = document.createElement("div");
  overlay.className = "android-permission-overlay";
  overlay.hidden = true;
  overlay.innerHTML = `
    <div class="android-permission-panel">
      <button type="button" class="back-btn android-permission-back-btn"></button>
      <h1 class="android-permission-title">QuKi Notes needs access to your files</h1>
      <p class="android-permission-body">
        To save your QuKis as files in your device's Documents folder, QuKi Notes needs
        "Allow management of all files" permission. Grant it on the next screen, then switch back to QuKi Notes.
      </p>
      <button type="button" class="android-permission-btn">Grant access</button>
      <p class="android-permission-waiting" hidden>Waiting for you to grant access in Settings&hellip;</p>
    </div>
  `;
  container.appendChild(overlay);

  const backBtn = overlay.querySelector<HTMLButtonElement>(".android-permission-back-btn")!;
  setIconButton(backBtn, ArrowLeft, "Use app storage instead");
  const button = overlay.querySelector<HTMLButtonElement>(".android-permission-btn")!;
  const waitingEl = overlay.querySelector<HTMLParagraphElement>(".android-permission-waiting")!;

  button.addEventListener("click", () => onRequestAccess());
  let unregisterBack: (() => void) | null = null;
  const setShown = (shown: boolean): void => {
    overlay.hidden = !shown;
    if (shown && !unregisterBack) unregisterBack = backDismiss?.push(useAppStorageInstead) ?? null;
    if (!shown && unregisterBack) {
      unregisterBack();
      unregisterBack = null;
    }
  };
  const useAppStorageInstead = (): void => {
    // Hidden here rather than left to the next render(state) call: cancel()
    // (androidStorageAccess.ts) leaves ready() pending forever once already
    // settled granted/cancelled once, so no further state change is
    // guaranteed to arrive and hide this overlay on its own.
    setShown(false);
    onUseAppStorageInstead();
  };
  backBtn.addEventListener("click", useAppStorageInstead);

  return {
    render(state: StorageAccessState): void {
      if (state === "granted") {
        setShown(false);
        return;
      }
      if (state === "checking") return;

      setShown(true);
      const waiting = state === "waiting-for-settings";
      button.disabled = waiting;
      waitingEl.hidden = !waiting;
    },
  };
}
