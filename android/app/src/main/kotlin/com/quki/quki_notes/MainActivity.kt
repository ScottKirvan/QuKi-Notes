package com.quki.quki_notes

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        StoragePlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        SharePlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)

        // TEMPORARY DIAGNOSTIC (see Agents/quiki-dev/CLAUDE.md "Android Share
        // Sheet delivery is intermittent"). Records this Activity instance's
        // identity at the moment SharePlugin captures it as its `context`.
        // Compare against SharePlugin's "shareText" log at share time: if the
        // identity hash ever differs, this Activity instance was recreated
        // between registration and Send being tapped without SharePlugin being
        // re-registered — that would confirm the "stale Activity context" lead.
        // If it always matches, that lead is refuted for the captured attempts.
        // Grep "TEMPORARY DIAGNOSTIC" to find and remove every part of this.
        Log.d(
            "QuKiShareDiag",
            "configureFlutterEngine: contextIdentity=${System.identityHashCode(this)} " +
                "elapsedRealtimeMs=${android.os.SystemClock.elapsedRealtime()}"
        )
    }
}
