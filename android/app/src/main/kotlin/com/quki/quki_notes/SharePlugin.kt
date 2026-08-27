package com.quki.quki_notes

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
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

                // TEMPORARY DIAGNOSTIC (see Agents/quiki-dev/CLAUDE.md "Android
                // Share Sheet delivery is intermittent"). Records the Activity's
                // identity/lifecycle state at the exact moment startActivity()
                // fires, so it can be correlated against the registration-time
                // log in MainActivity.configureFlutterEngine() and against the
                // Dart-side timestamps in android_share_channel.dart /
                // editor_screen.dart. Logs no QuKi content (ADR-12). Grep
                // "TEMPORARY DIAGNOSTIC" to find and remove every part of this
                // once the project owner has captured enough real attempts.
                val activity = context as? Activity
                Log.d(
                    "QuKiShareDiag",
                    "shareText: contextIdentity=${System.identityHashCode(context)} " +
                        "isActivity=${activity != null} " +
                        "isFinishing=${activity?.isFinishing} " +
                        "isDestroyed=${activity?.isDestroyed} " +
                        "hasWindowFocus=${activity?.hasWindowFocus()} " +
                        "elapsedRealtimeMs=${android.os.SystemClock.elapsedRealtime()}"
                )

                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                context.startActivity(Intent.createChooser(sendIntent, null))

                // TEMPORARY DIAGNOSTIC — confirms startActivity() returned
                // without throwing, and when. A silent/no-op background-activity
                // restriction throws no exception, so a matching "before" log
                // with no crash reported back to Dart is expected either way —
                // this line exists only to bound the timing.
                Log.d(
                    "QuKiShareDiag",
                    "shareText: startActivity() returned normally " +
                        "elapsedRealtimeMs=${android.os.SystemClock.elapsedRealtime()}"
                )

                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
