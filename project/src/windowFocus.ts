import { registerPlugin, type PluginListenerHandle } from "@capacitor/core";
import type { WindowSignals } from "./editMode.js";

interface WindowFocusChangedEvent {
  hasFocus: boolean;
}

/** The custom "WindowFocus" plugin (android/.../WindowFocusPlugin.kt): the activity window's focus. */
interface AndroidWindowFocusPlugin {
  addListener(
    eventName: "windowFocusChanged",
    listenerFunc: (event: WindowFocusChangedEvent) => void,
  ): Promise<PluginListenerHandle>;
}

const AndroidWindowFocus = registerPlugin<AndroidWindowFocusPlugin>("WindowFocus");

/** The real WindowSignals: the native window focus on Android, the page's visibility everywhere. */
export function createWindowSignals(): WindowSignals {
  return {
    now: () => Date.now(),
    isPageVisible: () => document.visibilityState === "visible",
    onWindowFocusChanged: (callback) => {
      const handle = AndroidWindowFocus.addListener("windowFocusChanged", (event) => callback(event.hasFocus));
      return () => void handle.then((h) => h.remove());
    },
    onPageHidden: (callback) => {
      const listener = (): void => {
        if (document.visibilityState === "hidden") callback();
      };
      document.addEventListener("visibilitychange", listener);
      return () => document.removeEventListener("visibilitychange", listener);
    },
  };
}
