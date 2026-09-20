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

export interface AppStateListenerHandle {
  remove(): void;
}

export interface StorageAccessDeps {
  isExternalStorageManager(): Promise<boolean>;
  requestAllFilesAccess(): Promise<void>;
  /** Wraps Capacitor's App.addListener("appStateChange", ...): fires callback(isActive) on every app foreground/background transition. */
  onAppStateChange(callback: (isActive: boolean) => void): AppStateListenerHandle;
}

export interface StorageAccessGate {
  getState(): StorageAccessState;
  /** Call when the user taps the explanatory screen's action. Sends them to the system permission screen. */
  requestAccess(): Promise<void>;
  /** Resolves once access is confirmed granted, whether immediately (fast path) or after a settings round trip. */
  ready(): Promise<void>;
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
  let resolveReady: () => void = () => {};
  const readyPromise = new Promise<void>((resolve) => {
    resolveReady = resolve;
  });

  function setState(next: StorageAccessState): void {
    current = next;
    onStateChange(next);
  }

  async function recheck(): Promise<void> {
    setState("checking");
    const granted = await deps.isExternalStorageManager();
    if (granted) {
      setState("granted");
      resolveReady();
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
      waitingForSettings = true;
      setState("waiting-for-settings");
      await deps.requestAllFilesAccess();
    },
    ready: () => readyPromise,
    destroy: () => listenerHandle.remove(),
  };
}
