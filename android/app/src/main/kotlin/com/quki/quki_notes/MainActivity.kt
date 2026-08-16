package com.quki.quki_notes

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // TEMP DEBUG (notes/dev/keyboard_focus_state.md verification round,
    // Round 3) — see packages/markdown_live_editor/lib/src/
    // keyboard_focus_debug.dart's header comment for the full removal list.
    // Reports Activity.onNewIntent() to the Dart side so the on-screen
    // diagnostic overlay can show whether it fires during an app-resume
    // scenario — testing the hypothesis that this Activity's
    // launchMode="singleTask" (AndroidManifest.xml, added for #188) causes
    // Android to route some resume paths through onNewIntent() rather than
    // a plain onResume().
    private var lifecycleDebugChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        StoragePlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        lifecycleDebugChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.quki.quki_notes/lifecycle_debug"
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        lifecycleDebugChannel?.invokeMethod("onNewIntent", null)
    }
}
