package com.quki.quki_notes

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
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
            mapOf("flutterViewVisibility" to visibilityName(findFlutterView(window.decorView)))
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
            mapOf("flutterViewVisibility" to visibilityName(findFlutterView(window.decorView)))
        )
    }

    // TEMP DEBUG (Round 4, see onCreate() above for the full explanation).
    // Recursively finds the descendant View whose class simple name contains
    // "FlutterView" — there is no public getter for it from MainActivity,
    // and its exact wrapping (whether it's the decor view's direct child or
    // nested under a splash-screen container) is an internal embedding
    // detail not worth depending on more precisely than this.
    private fun findFlutterView(view: View): View? {
        if (view.javaClass.simpleName.contains("FlutterView")) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findFlutterView(view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

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
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        lifecycleDebugChannel?.invokeMethod(
            "onWindowFocusChanged",
            mapOf("hasFocus" to hasFocus)
        )
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
