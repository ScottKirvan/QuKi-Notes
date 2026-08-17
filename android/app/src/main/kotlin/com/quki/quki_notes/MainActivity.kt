package com.quki.quki_notes

import android.content.Intent
import android.os.Bundle
import android.view.View
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

    // TEMP DEBUG (notes/dev/keyboard_focus_state.md verification round,
    // Round 4 — the switcher-reselect investigation) — see
    // packages/markdown_live_editor/lib/src/keyboard_focus_debug.dart's
    // header comment (Round 4 addition) for the full hypothesis and removal
    // list. Registers a native Android `OnGlobalFocusChangeListener` on the
    // window's decor view, reporting every native View-level focus change —
    // a different, lower-level signal than Flutter's own `FocusNode`, which
    // Round 1-3's `focusGained`/`focusLost` already track and which stayed
    // unchanged during the switcher-reselect repro. Registered here (not in
    // configureFlutterEngine) because it needs `window.decorView`, which is
    // only guaranteed to exist once `super.onCreate()` has run.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.viewTreeObserver.addOnGlobalFocusChangeListener { oldFocus, newFocus ->
            lifecycleDebugChannel?.invokeMethod(
                "onNativeFocusChanged",
                mapOf(
                    "from" to (oldFocus?.javaClass?.simpleName ?: "null"),
                    "to" to (newFocus?.javaClass?.simpleName ?: "null")
                )
            )
        }
    }

    // TEMP DEBUG (Round 4, see onCreate() above for the full explanation).
    // Reports Activity#onStop() together with the FlutterView's own
    // View.getVisibility() at that moment — called AFTER super.onStop(), so
    // this reads the value stock Flutter's own onStop() workaround
    // (FlutterActivityAndFragmentDelegate.java, confirmed against the local
    // Flutter 3.44.0 engine source) has already set it to, if that workaround
    // is what's firing.
    override fun onStop() {
        super.onStop()
        lifecycleDebugChannel?.invokeMethod(
            "onActivityStop",
            mapOf("flutterViewVisibility" to visibilityName(findFlutterView()))
        )
    }

    // TEMP DEBUG (Round 4, see onCreate() above for the full explanation).
    // Reports Activity#onStart() together with the FlutterView's own
    // View.getVisibility() at that moment — called AFTER super.onStart(), so
    // this reads the value AFTER stock Flutter's own visibility-restore in
    // the same method has already run.
    override fun onStart() {
        super.onStart()
        lifecycleDebugChannel?.invokeMethod(
            "onActivityStart",
            mapOf("flutterViewVisibility" to visibilityName(findFlutterView()))
        )
    }

    // TEMP DEBUG (Round 4, see onCreate() above for the full explanation).
    // Round 7 fix (notes/dev/keyboard_focus_state.md) — this previously
    // walked the decor view tree by hand looking for a descendant View whose
    // class simple name contains "FlutterView". Two fresh Round 6 device
    // tests (see keyboard_focus_debug.dart's header comment, Round 6/7
    // additions) both reported "(not-found)" here on a full-stop scenario
    // that Round 4's own device testing had previously found successfully
    // (real GONE/VISIBLE values) — a genuine regression in this diagnostic,
    // blinding exactly the check the next device test needs.
    //
    // The exact mechanism of that regression is NOT confirmed — it could not
    // be reproduced or root-caused from source alone (there is no code-level
    // reason this recursive walk should fail to find a view that
    // `FlutterActivity.onCreate()` sets as this Activity's own content view
    // via `setContentView(createFlutterView())`, confirmed by reading
    // FlutterActivity.java directly), and this round has no device access to
    // test it further. Rather than guess at the cause, this replaces the
    // fragile mechanism outright with the one Flutter's own source
    // documents as the intended way to do this exact lookup:
    // `FlutterActivity.FLUTTER_VIEW_ID`, a public constant whose doc comment
    // reads verbatim "This ID can be used to lookup FlutterView in the
    // Android view hierarchy" (FlutterActivity.java, confirmed present in
    // this project's exact Flutter 3.44.0 engine source) — set on the
    // FlutterView via `flutterView.setId(flutterViewId)` in
    // FlutterActivityAndFragmentDelegate.onCreateView(), also confirmed by
    // reading that source directly, not assumed from the constant's name
    // alone. `findViewById()` is Android's own cached, ID-based view lookup
    // rather than a hand-rolled string-matching tree walk, so this is a
    // genuine robustness improvement regardless of the previous mechanism's
    // exact failure cause — the same "real, independently-correct
    // improvement, not yet confirmed as fixing the specific symptom"
    // framing this investigation has used before (see Round 1's
    // connectionClosed() fix). The next device test will show directly
    // whether this reports a real value again.
    private fun findFlutterView(): View? = findViewById(FlutterActivity.FLUTTER_VIEW_ID)

    // Round 5 (notes/dev/keyboard_focus_state.md, the resume-after-
    // interruption fix) — see keyboard_focus_debug.dart's header comment
    // (Round 5 addition) for the full evidence and reasoning. Unlike the
    // Round 3/4 additions above, this override is NOT purely diagnostic:
    // Activity#onWindowFocusChanged() is the standard, documented Android
    // signal for this window gaining/losing focus, and — confirmed by two
    // real device tests — is the only signal available (of everything
    // tracked through Round 4) that has a chance of firing during a fast
    // "swipe to Recents, immediately re-select this app" peek, which never
    // triggers a full onStop()/onStart() cycle at all. editor_screen.dart's
    // MethodChannel handler uses the false->true pair this reports as the
    // actual trigger for forcing the editor to re-establish real native
    // focus (MarkdownEditorController.restoreFocusAfterInterruption() in
    // markdown_editor.dart) — do not remove this override as part of a
    // future diagnostics-only cleanup pass.
    //
    // Round 6 (cross-app IME contention) — see keyboard_focus_debug.dart's
    // header comment (Round 6 addition) for the full device evidence and
    // citations. The dispatch below is now deferred via
    // `window.decorView.post {}` instead of sent inline — this deferral is
    // itself part of the fix, not incidental, matching Android's own
    // documented behavior: InputMethodManager does not finish marking this
    // window ready to receive showSoftInput() calls (its internal
    // mServedView, set by ViewRootImpl.checkFocusNoStartInput()) until
    // AFTER Activity#onWindowFocusChanged() returns, within the handling of
    // this SAME window-focus message. Dispatching inline risked starting
    // the whole Dart-side restore chain (which ends, several async hops
    // later, in Flutter's own TextInputPlugin.showTextInput() calling
    // InputMethodManager.showSoftInput()) before that internal state was
    // ready — the official Android fix for this exact race
    // (developer.android.com, "Handle input method visibility") is to post
    // a Runnable from onWindowFocusChanged so the dependent call runs on
    // the next iteration of the UI message loop instead. Do not revert this
    // to an inline dispatch as part of a future diagnostics-only cleanup.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        window.decorView.post {
            lifecycleDebugChannel?.invokeMethod(
                "onWindowFocusChanged",
                mapOf("hasFocus" to hasFocus)
            )
        }
    }

    // TEMP DEBUG (Round 4, see onCreate() above for the full explanation).
    private fun visibilityName(view: View?): String {
        if (view == null) return "not-found"
        return when (view.visibility) {
            View.VISIBLE -> "VISIBLE"
            View.INVISIBLE -> "INVISIBLE"
            View.GONE -> "GONE"
            else -> "unknown(${view.visibility})"
        }
    }
}
