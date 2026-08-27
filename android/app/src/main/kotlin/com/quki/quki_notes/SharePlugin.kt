package com.quki.quki_notes

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Launches the system share chooser via a plain ACTION_SEND intent, using
 * the 2-arg Intent.createChooser() overload and a plain startActivity() call
 * -- no PendingIntent, no result-tracking, no startActivityForResult.
 *
 * This exists because share_plus (the cross-platform share plugin this app
 * otherwise uses) unconditionally routes Android shares through a
 * result-tracking chooser (3-arg createChooser + PendingIntent +
 * startActivityForResult) so it can report back which target app the user
 * picked. QuKi-Notes never reads that result -- ShareSheetTransport already
 * discards it entirely (see #92: share_plus reports a false "dismissed"
 * even on success). That unused mechanism is implicated in some targets
 * (Bluesky, confirmed via on-device A/B against a minimal native app using
 * a plain chooser) silently failing to receive the shared content at all --
 * see notes/dev/android_share_sheet.md for the full investigation.
 *
 * The #337 fix above (plain chooser) did not fully resolve delivery: a
 * follow-on repro chain found delivery still intermittent, specifically
 * correlated with whether the target app is already running. Two changes
 * here, both present in FossifyOrg/Notes' actively-maintained equivalent
 * (Activity.shareTextIntent()) and absent from the #337 version:
 *
 * 1. FLAG_ACTIVITY_NEW_TASK on the shared intent. Intent.createChooser()
 *    hands the resolved target activity a clone of this intent (not the
 *    outer ACTION_CHOOSER wrapper), so this flag is what actually governs
 *    how the OS attaches to an *already-running* target task -- exactly the
 *    variable the repro chain isolates. Without it, launching into a target
 *    that already has a live task can land the intent somewhere other than
 *    that task's normal onNewIntent()/share-handling path.
 * 2. startActivity() wrapped in try/catch, reported back through the
 *    MethodChannel via result.error() rather than left to propagate
 *    uncaught. Android's Background Activity Launch restrictions can throw
 *    SecurityException here, and any other startActivity() failure
 *    previously vanished with no visible signal -- exactly the "opens but
 *    does nothing" symptom this bug reports as. The Dart side
 *    (ShareSheetTransport.transport(), uncaught) already lets this surface
 *    to EditorScreen's existing generic "Send failed" retry snackbar -- no
 *    new UX needed here.
 *
 * Not yet confirmed to fully close the bug -- see the PR/session report for
 * exactly what is and isn't verified.
 */
class SharePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.quki.quki_notes/share"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareText" -> {
                val text = call.argument<String>("text")
                if (text.isNullOrEmpty()) {
                    result.error("invalid_argument", "text must be non-empty", null)
                    return
                }

                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                try {
                    context.startActivity(Intent.createChooser(sendIntent, null))
                    result.success(null)
                } catch (e: ActivityNotFoundException) {
                    result.error(
                        "no_target_app",
                        "No app available to handle the share.",
                        e.toString()
                    )
                } catch (e: Exception) {
                    // Covers Android's Background Activity Launch restrictions
                    // (SecurityException) and any other startActivity() failure
                    // that would otherwise propagate uncaught with no signal.
                    result.error(
                        "share_failed",
                        "Failed to launch the share chooser.",
                        e.toString()
                    )
                }
            }

            else -> result.notImplemented()
        }
    }
}
