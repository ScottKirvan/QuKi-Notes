/**
 * BEHAVIOR_SPEC.md §3's Android paragraph: "if all-files access is already
 * granted, resolve a fixed path... and continue. If not, send the user to
 * the system permission screen and resume the flow when the app comes back
 * to the foreground — the permission grant returns no result, so app
 * lifecycle is the only signal." This is the granted/not-granted/resume-
 * check decision flow, kept free of Capacitor and DOM so it can be unit
 * tested directly; main.ts wires it to the real plugins and to
 * androidPermissionView.ts.
 */
export type StorageAccessState = "checking" | "granted" | "needs-permission" | "waiting-for-settings";

/**
 * What requestAllFilesAccess() actually did, since that differs by API
 * level (see StoragePlugin.kt's requestAllFilesAccess doc comment):
 * - "opened-settings" (API 30+): a real app-switch to the system Settings
 *   screen was started. The gate must wait for a foreground resume before
 *   rechecking - the permission grant itself returns no result.
 * - "granted"/"denied" (API <30): the classic runtime permission dialog
 *   already ran and resolved in-process. There is no Settings screen and no
 *   app-lifecycle transition to wait for, so the gate must treat this as
 *   final immediately.
 */
export type RequestAllFilesAccessOutcome = "opened-settings" | "granted" | "denied";

export interface AppStateListenerHandle {
  remove(): void;
}

export interface StorageAccessDeps {
  isExternalStorageManager(): Promise<boolean>;
  requestAllFilesAccess(): Promise<RequestAllFilesAccessOutcome>;
  /** Wraps Capacitor's App.addListener("appStateChange", ...): fires callback(isActive) on every app foreground/background transition. */
  onAppStateChange(callback: (isActive: boolean) => void): AppStateListenerHandle;
}

export interface StorageAccessGate {
  getState(): StorageAccessState;
  /** Call when the user taps the explanatory screen's action. Sends them to the system permission screen, or (API <30) shows the runtime permission dialog directly. */
  requestAccess(): Promise<void>;
  /**
   * Resolves `true` once access is confirmed granted, whether immediately
   * (fast path), after a settings round trip (API 30+), or after an
   * in-process runtime permission dialog (API <30). Resolves `false`
   * instead if `cancel()` is called first — e.g. the user backs out to
   * choose app storage instead. Never rejects.
   */
  ready(): Promise<boolean>;
  /**
   * Call when the user backs out of the permission screen without granting
   * access. Makes `ready()` resolve `false`; safe to call at most once, and
   * a no-op if `ready()` has already settled.
   */
  cancel(): void;
  /** Removes the underlying app-state listener. Safe to call once access is granted or the gate is no longer needed. */
  destroy(): void;
}

/**
 * Starts an immediate permission check. If already granted, `ready()`
 * resolves right away and `onStateChange` never reports anything but
 * "checking" then "granted" — the caller's UI stays hidden for that path
 * (BEHAVIOR_SPEC.md: "must stay fast with no extra UI shown").
 *
 * If not granted, state becomes "needs-permission" and `ready()` stays
 * pending until `requestAccess()` is called and the app is later observed
 * returning to the foreground with access now granted. A foreground
 * transition that arrives before `requestAccess()` was ever called, or
 * while the app is going *to* the background, is ignored — only a resume
 * that follows this gate's own request counts as the resume-from-settings
 * signal the spec describes.
 */
export function createStorageAccessGate(
  deps: StorageAccessDeps,
  onStateChange: (state: StorageAccessState) => void,
): StorageAccessGate {
  let current: StorageAccessState = "checking";
  let waitingForSettings = false;
  let settled = false;
  let resolveReady: (granted: boolean) => void = () => {};
  const readyPromise = new Promise<boolean>((resolve) => {
    resolveReady = resolve;
  });

  function setState(next: StorageAccessState): void {
    current = next;
    onStateChange(next);
  }

  function settle(granted: boolean): void {
    if (settled) return;
    settled = true;
    resolveReady(granted);
  }

  async function recheck(): Promise<void> {
    setState("checking");
    const granted = await deps.isExternalStorageManager();
    if (granted) {
      setState("granted");
      settle(true);
    } else {
      setState("needs-permission");
    }
  }

  const listenerHandle = deps.onAppStateChange((isActive) => {
    if (!isActive || !waitingForSettings) return;
    waitingForSettings = false;
    void recheck();
  });

  void recheck();

  return {
    getState: () => current,
    requestAccess: async () => {
      setState("waiting-for-settings");
      const outcome = await deps.requestAllFilesAccess();
      if (outcome === "opened-settings") {
        // API 30+: no result yet - wait for the foreground-resume signal
        // (the onAppStateChange listener above) before rechecking.
        waitingForSettings = true;
        return;
      }
      // API <30: the runtime permission dialog already resolved in-process,
      // with no Settings screen and no app-lifecycle transition coming.
      if (outcome === "granted") {
        setState("granted");
        settle(true);
      } else {
        setState("needs-permission");
      }
    },
    ready: () => readyPromise,
    cancel: () => settle(false),
    destroy: () => listenerHandle.remove(),
  };
}
