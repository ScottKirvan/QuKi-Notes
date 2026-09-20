import { registerPlugin, type PluginListenerHandle } from "@capacitor/core";

export interface SharedTextEvent {
  text: string;
}

/**
 * The native surface of the custom Capacitor "ShareIn" plugin
 * (project/android/app/src/main/java/com/quki/quki_notes/ShareInPlugin.kt),
 * a from-scratch Capacitor port of the real Flutter Android share-in path
 * (receive_sharing_intent - see lib/features/share_in/share_handler.dart
 * and lib/app.dart's _ShareAwareHome for what's being ported). Distinct
 * from the "Share" plugin (androidShare.ts), which is the outgoing
 * direction - this plugin has no callable methods of its own, it only ever
 * emits the "sharedTextReceived" event.
 */
export interface AndroidShareInPlugin {
  addListener(eventName: "sharedTextReceived", listenerFunc: (event: SharedTextEvent) => void): Promise<PluginListenerHandle>;
}

/**
 * registerPlugin resolves against whatever native plugin is registered
 * under this name at runtime (MainActivity.registerPlugin(ShareInPlugin::class.java)
 * on Android); it is safe to call outside a Capacitor native context - the
 * proxy it returns is only ever actually wired up when the caller has
 * already confirmed Capacitor.getPlatform() === "android" (see main.ts).
 */
export const AndroidShareIn = registerPlugin<AndroidShareInPlugin>("ShareIn");

/**
 * Wraps AndroidShareIn.addListener the same way editMode.ts wraps
 * Keyboard.addListener - the established pattern in this codebase for
 * consuming a Capacitor plugin's event stream from TS.
 */
export function onSharedTextReceived(callback: (text: string) => void): Promise<PluginListenerHandle> {
  return AndroidShareIn.addListener("sharedTextReceived", (event) => callback(event.text));
}
