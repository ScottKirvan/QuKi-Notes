package com.quki.quki_notes

import android.content.Intent
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.annotation.CapacitorPlugin

/**
 * Receives Android share-in intents (BEHAVIOR_SPEC.md §8: shared text
 * becomes a new QuKi immediately). handleOnNewIntent() is the single native
 * hook for both paths the spec requires - a share arriving while the app
 * was closed, and one arriving while it's already running - because
 * @capacitor/android's BridgeActivity calls its own onNewIntent() from both
 * its onCreate() (cold start, using the launch intent) and its own
 * onNewIntent() override (already running); both route through
 * Bridge.onNewIntent(), which calls this on every registered plugin. Read
 * directly from project/node_modules/@capacitor/android/capacitor/src/main/java/com/getcapacitor/
 * (Plugin.java's handleOnNewIntent hook at line 968, Bridge.java's
 * onNewIntent around line 1309) as part of this port; the on-device
 * behavior for both paths still needs its own confirmation, not assumed
 * from having read this.
 *
 * This activity's manifest ACTION_SEND intent-filters only declare the
 * text/plain and text-wildcard data types, mirroring the Flutter app's own
 * manifest, and register no ACTION_SEND_MULTIPLE filter - so
 * Intent.EXTRA_TEXT (a single string) is the only shared-text extra this
 * app can ever receive; there is no multi-item text intent for Android to
 * deliver here.
 *
 * retainUntilConsumed = true on notifyListeners is Plugin.java's own
 * documented mechanism (same file, line 665's overload) for replaying an
 * event fired before any JS listener has attached - used here so a
 * cold-start share isn't lost in the gap between this intent arriving and
 * the web app finishing its boot and registering its own listener.
 */
@CapacitorPlugin(name = "ShareIn")
class ShareInPlugin : Plugin() {

    override fun handleOnNewIntent(intent: Intent) {
        super.handleOnNewIntent(intent)
        if (intent.action != Intent.ACTION_SEND) return
        val type = intent.type ?: return
        if (!type.startsWith("text/")) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (text.isNullOrEmpty()) return

        val data = JSObject()
        data.put("text", text)
        notifyListeners("sharedTextReceived", data, true)
    }
}
