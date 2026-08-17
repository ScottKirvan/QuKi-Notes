package com.quki.quki_notes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // notes/dev/keyboard_focus_state.md, Round 5 (resume-after-interruption
    // fix) — carries onWindowFocusChanged() events to editor_screen.dart's
    // MethodChannel handler, which uses the false->true pair as the trigger
    // for MarkdownEditorController.restoreFocusAfterInterruption().
    private var lifecycleDebugChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        StoragePlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        lifecycleDebugChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.quki.quki_notes/lifecycle_debug"
        )
    }

    // notes/dev/keyboard_focus_state.md, Round 5 (resume-after-interruption
    // fix) — Activity#onWindowFocusChanged() is the standard, documented
    // Android signal for this window gaining/losing focus, and — confirmed
    // by device testing — is the only signal that reliably fires during a
    // fast "swipe to Recents, immediately re-select this app" peek, which
    // never triggers a full onStop()/onStart() cycle at all. Do not remove
    // this override.
    //
    // Round 6 (cross-app IME contention) — the dispatch below is deferred via
    // `window.decorView.post {}` instead of sent inline; this deferral is
    // itself part of the fix, not incidental, matching Android's own
    // documented behavior: InputMethodManager does not finish marking this
    // window ready to receive showSoftInput() calls (its internal
    // mServedView, set by ViewRootImpl.checkFocusNoStartInput()) until AFTER
    // Activity#onWindowFocusChanged() returns, within the handling of this
    // SAME window-focus message. Dispatching inline risked starting the
    // whole Dart-side restore chain (which ends, several async hops later,
    // in Flutter's own TextInputPlugin.showTextInput() calling
    // InputMethodManager.showSoftInput()) before that internal state was
    // ready — the official Android fix for this exact race
    // (developer.android.com, "Handle input method visibility") is to post
    // a Runnable from onWindowFocusChanged so the dependent call runs on the
    // next iteration of the UI message loop instead. Do not revert this to
    // an inline dispatch.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        window.decorView.post {
            lifecycleDebugChannel?.invokeMethod(
                "onWindowFocusChanged",
                mapOf("hasFocus" to hasFocus)
            )
        }
    }
}
