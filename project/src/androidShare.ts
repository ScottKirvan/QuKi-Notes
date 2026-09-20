import { registerPlugin } from "@capacitor/core";

/**
 * The native surface of the custom Capacitor "Share" plugin
 * (project/android/app/src/main/java/com/quki/quki_notes/SharePlugin.kt),
 * a from-scratch Capacitor port of the real Flutter Android SharePlugin -
 * see that Kotlin file's doc comment for what design choices are ported
 * as-is versus independently verified, and why this is a plain native
 * chooser intent rather than a Capacitor share plugin (none is installed
 * in this project; see package.json). Distinct
 * from the "Storage" plugin (capacitorBackend.ts) the same way Flutter
 * keeps SharePlugin and the storage channel as separate MethodChannels -
 * share is a separate concern from file I/O.
 */
export interface AndroidSharePlugin {
  shareText(options: { text: string }): Promise<void>;
}

/**
 * registerPlugin resolves against whatever native plugin is registered
 * under this name at runtime (MainActivity.registerPlugin(SharePlugin::class.java)
 * on Android); it is safe to call outside a Capacitor native context; the
 * proxy it returns is only ever actually invoked when the caller has
 * already confirmed Capacitor.getPlatform() === "android".
 */
export const AndroidShare = registerPlugin<AndroidSharePlugin>("Share");

/**
 * The Android transport passed to sendQuKi() in place of a clipboard
 * writer - same `(text: string) => Promise<void>` shape, so sendQuKi's
 * empty-body guard and error handling apply unchanged. Any rejection from
 * the native side (no target app, launch failure) propagates as a thrown
 * error, which sendQuKi already catches and reports as a retryable
 * "Send failed" - no separate error handling needed here.
 */
export async function shareTextViaAndroid(text: string): Promise<void> {
  await AndroidShare.shareText({ text });
}
