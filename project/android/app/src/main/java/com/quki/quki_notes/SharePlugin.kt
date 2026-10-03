package com.quki.quki_notes

import android.content.ActivityNotFoundException
import android.content.Intent
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

/**
 * Launches the system share chooser via a plain ACTION_SEND intent, using
 * the 2-arg Intent.createChooser() overload and a plain startActivity()
 * call - no PendingIntent, no result-tracking, no startActivityForResult.
 *
 * Ported from the real Flutter Android plugin
 * (android/app/src/main/kotlin/com/quki/quki_notes/SharePlugin.kt in the
 * Flutter source tree), translated from a Flutter MethodChannel handler to
 * Capacitor's plugin-call model. That source file's own doc comment cites a
 * specific bug history (issue numbers, a named failing share target, a
 * named upstream project) as the reason for this design; none of that
 * history could be independently corroborated from this repository - QuKi
 * Notes is not on GitHub, so there is no tracked issue history to check
 * those citations against - so it is deliberately not repeated here. Per
 * this project's own standard, an unverified comment is not a source of
 * truth, even when it reads as a detailed one.
 *
 * What IS independently verified, on a real Android emulator, as part of
 * this port: with the two properties below present, tapping Send opens the
 * real system share chooser (confirmed via `dumpsys activity activities`
 * showing the real com.android.intentresolver chooser as the focused
 * activity, and real editor content in the chooser's own preview), and a
 * real installed target app receives it (confirmed via the same dumpsys
 * check showing the target's own real share-handling activity in focus
 * after picking it, e.g. Android Messages' MultiShareActivity).
 *
 * 1. FLAG_ACTIVITY_NEW_TASK on the shared intent. Intent.createChooser()
 *    hands the resolved target activity a clone of this intent, not the
 *    outer ACTION_CHOOSER wrapper - this flag is what governs how the OS
 *    attaches to an already-running target's task. Dropping it is a
 *    plausible way to misroute delivery to a target with a live task
 *    already open, per Android's own documented Intent/task-affinity
 *    semantics, though this repository has no independent, reproduced
 *    evidence of that specific failure mode. Kept because the source being
 *    ported has it and removing it would be an unverified simplification,
 *    not because a specific incident was reproduced here.
 * 2. startActivity() wrapped in try/catch, surfaced back through the
 *    Capacitor call rather than left to propagate uncaught - ordinary
 *    defensive handling for a call that can throw (no app to handle the
 *    share, or a SecurityException from Android's Background Activity
 *    Launch restrictions), not contingent on the disputed history above.
 */
@CapacitorPlugin(name = "Share")
class SharePlugin : Plugin() {

    @PluginMethod
    fun shareText(call: PluginCall) {
        val text = call.getString("text")
        if (text.isNullOrEmpty()) {
            call.reject("text must be non-empty")
            return
        }

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(Intent.createChooser(sendIntent, null))
            call.resolve()
        } catch (e: ActivityNotFoundException) {
            call.reject("No app available to handle the share.", "no_target_app", e)
        } catch (e: Exception) {
            // Covers Android's Background Activity Launch restrictions
            // (SecurityException) and any other startActivity() failure
            // that would otherwise propagate uncaught with no signal.
            call.reject("Failed to launch the share chooser.", "share_failed", e)
        }
    }
}
