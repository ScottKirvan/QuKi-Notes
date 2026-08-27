package com.quki.quki_notes

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
                }
                context.startActivity(Intent.createChooser(sendIntent, null))
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
