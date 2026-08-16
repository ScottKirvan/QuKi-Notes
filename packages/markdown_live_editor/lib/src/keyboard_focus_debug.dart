// ============================================================================
// TEMPORARY DEBUG-ONLY INSTRUMENTATION
// notes/dev/keyboard_focus_state.md — device-verification round only.
//
// Delete this whole file, plus its wiring points, once that doc's
// "Required device verification" checklist is complete:
//   1. packages/markdown_live_editor/lib/src/quiki_editor.dart —
//      connectionClosed() calls KeyboardFocusDebugCounters.instance
//      .recordConnectionClosed(); _openConnection() calls
//      .recordConnectionOpened() on a genuine new attach; _closeConnection()
//      and dispose() each call .recordExplicitClose() when an app-code path
//      (not the platform) tears down an existing connection. Remove those
//      lines + the import.
//   2. lib/features/editor/editor_screen.dart — _EditorScreenState wraps its
//      Scaffold in a Stack with a KeyboardFocusDebugOverlay() in a corner,
//      its onFocusChanged closure records a focus gained/lost event, and
//      initState() registers a MethodChannel handler for
//      'com.quki.quki_notes/lifecycle_debug' that records onNewIntent()
//      calls. Remove the Stack wrapper, the overlay widget, the channel
//      handler, and those lines.
//   3. android/app/src/main/kotlin/com/quki/quki_notes/MainActivity.kt —
//      the lifecycleDebugChannel field, its onNewIntent() override, its
//      onStop()/onStart() overrides, the onCreate() override that registers
//      the ViewTreeObserver.OnGlobalFocusChangeListener, and the
//      findFlutterView() helper (Round 4 additions — see below). Remove all
//      of it.
//
// Round 2 addition: KeyboardFocusDebugOverlay also shows the LIVE current
// value of the platform's keyboard-inset signal — the new ground-truth
// signal cursor/toolbar visibility is now driven by on mobile (see
// quiki_editor.dart's _showCursor() and editor_screen.dart's
// `keyboardVisible`). Read via View.of(context).viewInsets, NOT
// MediaQuery.viewInsetsOf(context) — this overlay sits inside
// editor_screen.dart's Scaffold body, same as the editor itself, so
// MediaQuery would always read 0 there (Scaffold's own
// resizeToAvoidBottomInset zeroes it for body descendants); confirmed
// empirically, not just reasoned about, before shipping this. This is read
// directly in the overlay's own build(), not routed through
// KeyboardFocusDebugCounters — it's a live value, not a count/timestamp
// event, so the existing counter-recording mechanism doesn't fit it.
//
// Round 3 addition (the black-screen-on-resume investigation): the newest
// device-test evidence showed connClosed/focusLost/focusGained all
// unchanged across a backgrounding cycle where the keyboard nonetheless
// reappeared then vanished again — i.e. every event this overlay already
// tracked was invisible to whatever is actually happening. Three new
// signals were added to widen the net rather than guess a fix:
//   - connOpen: a genuine new TextInputConnection attach (_openConnection()
//     actually creating one, not an early-return on an already-attached
//     connection). If a connection is silently being torn down and
//     reopened around the resume moment, this — paired with connClosed and
//     explicitClose — is what would surface it.
//   - explicitClose: this app's OWN code calling _connection?.close()
//     (_closeConnection(), reached only from _onFocusChanged() on a real
//     focus loss — so this should track focusLost 1:1 if that is really
//     the only path — and dispose()). If explicitClose fires without a
//     matching focusLost, that is a real, currently-invisible finding.
//   - onNewIntent: Android's Activity.onNewIntent(), wired from
//     MainActivity.kt over a dedicated MethodChannel. Tests a specific,
//     evidence-backed hypothesis: MainActivity's launchMode="singleTask"
//     (android/app/src/main/AndroidManifest.xml, added in PR #259 for
//     #188 — see `git log` on that file) means Android can route an
//     intent to the already-running activity via onNewIntent() instead of
//     a plain onResume(), on at least one common way of "returning" to a
//     backgrounded app (re-tapping the launcher icon, as distinct from
//     switching back via the Recents/overview UI, which does not deliver a
//     new Intent). singleTask is unusual — most apps use the default
//     `standard` launchMode — which would explain why this app's own
//     comparison ("every other app I tested doesn't do this") points at
//     something specific to this app rather than a general Flutter/Android
//     timing quirk. This is NOT confirmed — onNewIntent() itself does
//     nothing IME-related in Flutter's own embedding (verified by reading
//     FlutterActivityAndFragmentDelegate.onNewIntent() directly), and
//     receive_sharing_intent's onNewIntent handler is a no-op for a
//     non-SEND intent (verified by reading its Kotlin source) — so if this
//     is implicated at all, it would be via a lower-level Android
//     window/IME rebind that happens purely as a side effect of the
//     platform routing a fresh Intent to the activity, not via any Dart or
//     plugin code. This counter is what lets the next real device test
//     confirm or rule out whether onNewIntent() fires at all during the
//     scenario, which the app currently cannot observe any other way.
//
// Round 4 addition (the switcher-reselect investigation): a controlled,
// apples-to-apples repro (tap into a note to open the keyboard, swipe to the
// Recents/app-switcher overview, immediately re-select QuKi-Notes again —
// never actually leaving to a different app) shows the keyboard visibly and
// genuinely closing (viewInsets.bottom really drops to 0, confirmed, not a
// rendering artifact) and not returning — while every one of the six signals
// Rounds 1-3 already track (connClosed, focusLost, focusGained, connOpen,
// explicitClose, onNewIntent) stayed completely unchanged during the
// reproduction. That rules out everything on the Dart<->engine TextInputClient
// boundary this file already watches — whatever is happening is invisible to
// all of it, so it must be happening at the native Android View layer, below
// where any of those six signals would ever fire.
//
// A newly-found, evidence-backed lead: read directly from the Flutter engine
// source (`D:/bin/flutter/engine/src/flutter/shell/platform/android/io/
// flutter/embedding/android/FlutterActivityAndFragmentDelegate.java`,
// confirmed present in Flutter 3.44.0, this project's exact SDK version) —
// `onStop()` (fired on every Activity#onStop(), which real Recents-overview
// backgrounding always triggers) unconditionally calls
// `flutterView.setVisibility(View.GONE)` as a documented workaround for a
// OnePlus black-screen bug (flutter/flutter#93276), restoring the prior
// visibility in the matching `onStart()`. This is STOCK Flutter engine code,
// not anything QuKi-Notes added, and it runs unconditionally on every device
// (no OnePlus-specific gating in the source) every time the Activity
// stops/starts. FlutterView is the View that holds Android's native input
// focus while the keyboard is up (see FlutterView.java: "FlutterView needs
// to be focusable so that the InputMethodManager can interact with it").
// Setting the currently-focused View to GONE is a well-documented trigger for
// Android to clear that View's focus, which can cause the IME bound to it to
// be torn down — entirely at the native View/InputMethodManager layer, with
// no Dart-side TextInputClient callback required to fire, and restoring
// visibility afterward does not, on its own, re-request focus or re-show the
// keyboard. This would explain both why the six existing signals stayed
// silent AND why comparison apps that aren't Flutter apps (i.e. don't share
// this exact engine code path) don't exhibit it. This is NOT confirmed — it
// is a plausible, source-verified mechanism, not a proven cause; the six new
// counters below exist specifically to let the next real device test confirm
// or rule it out, the same way Round 3's counters were added to test its own
// hypothesis rather than assumed correct outright.
//   - activityStop / activityStart: MainActivity.kt's Activity#onStop() and
//     Activity#onStart() overrides (new — this app had neither before Round
//     4), each reporting the FlutterView's `View.getVisibility()` value
//     (found by walking the decor view tree for a view whose class name
//     contains "FlutterView") at the moment of the call, confirming whether
//     the GONE/restore cycle actually happens during the repro and exactly
//     when relative to the keyboard visibly closing.
//   - nativeFocusChange: a `ViewTreeObserver.OnGlobalFocusChangeListener`
//     registered on the window's decor view in `onCreate()`, reporting the
//     simple class name of the view focus moves FROM and TO (or "null" for
//     either) on every native Android focus change — this is Android's own
//     View-level focus, a different, lower-level signal than Flutter's
//     `FocusNode`/`hasFocus` (which Rounds 1-3 already track via
//     focusGained/focusLost and which stayed unchanged during the repro).
//     If FlutterView loses native focus (moves to "null" or another view)
//     during the switcher-reselect window, that is the direct confirmation
//     this hypothesis needs.
//
// Counts and timestamps only — never logs, transmits, or persists QuKi
// content. Nothing here touches shared_preferences or any other persistence;
// state lives only in memory for the current app session.
// ============================================================================

import 'package:flutter/material.dart';

/// Shared, in-memory counters for the three events
/// notes/dev/keyboard_focus_state.md's verification round needs visibility
/// into.
///
/// `connectionClosed` is recorded directly at its one real call site
/// (QuikiEditorState.connectionClosed()) — that event doesn't otherwise
/// surface anywhere observable from outside the package.
///
/// `focusGained`/`focusLost` are recorded as a PROXY for
/// requestFocus()/unfocus() calls, driven by MarkdownEditorController's
/// existing onFocusChanged callback + hasActiveBlock, rather than
/// instrumenting each of the ~9-11 requestFocus()/unfocus() call sites
/// individually. On this app's mobile targets, a FocusNode's focus state
/// only ever changes as a direct result of one of those two methods being
/// called (no tab-focus-traversal, no other focus scope competing) — so a
/// gained/lost transition count is an accurate stand-in for "how many times
/// requestFocus()/unfocus() actually took effect," without needing
/// call-site-level attribution. It does NOT distinguish which of the
/// several call sites triggered any individual event.
class KeyboardFocusDebugCounters {
  KeyboardFocusDebugCounters._();

  /// Process-wide singleton — deliberately not scoped to one editor
  /// instance, so it survives across QuKi switches within one app session.
  static final KeyboardFocusDebugCounters instance =
      KeyboardFocusDebugCounters._();

  int connectionClosedCount = 0;
  DateTime? lastConnectionClosed;

  int focusGainedCount = 0;
  DateTime? lastFocusGained;

  int focusLostCount = 0;
  DateTime? lastFocusLost;

  /// Round 3: a genuine new [TextInputConnection] attach —
  /// QuikiEditorState._openConnection() actually creating one, not an
  /// early-return on an already-attached connection. See this file's header
  /// comment for why this was added.
  int connectionOpenedCount = 0;
  DateTime? lastConnectionOpened;

  /// Round 3: this app's OWN code closing an existing [TextInputConnection]
  /// (QuikiEditorState._closeConnection() or .dispose()), as opposed to the
  /// platform closing it (which fires connectionClosed() instead — recorded
  /// separately above). See this file's header comment for why this was
  /// added.
  int explicitCloseCount = 0;
  DateTime? lastExplicitClose;

  /// Round 3: Android's Activity.onNewIntent(), reported over a MethodChannel
  /// from MainActivity.kt. See this file's header comment for why this was
  /// added — tests the hypothesis that launchMode="singleTask" causes
  /// onNewIntent() to fire on some app-resume paths.
  int onNewIntentCount = 0;
  DateTime? lastOnNewIntent;

  /// Round 4: Activity#onStop(), reported from MainActivity.kt, paired with
  /// the FlutterView's `View.getVisibility()` at that moment. See this
  /// file's header comment (Round 4 addition) for the hypothesis this tests
  /// — stock Flutter's `FlutterActivityAndFragmentDelegate.onStop()` sets
  /// FlutterView to `View.GONE` unconditionally.
  int activityStopCount = 0;
  DateTime? lastActivityStop;
  String? lastFlutterViewVisibilityAtStop;

  /// Round 4: Activity#onStart(), reported from MainActivity.kt, paired with
  /// the FlutterView's `View.getVisibility()` at that moment (after stock
  /// Flutter's own visibility-restore in the same method). See this file's
  /// header comment (Round 4 addition).
  int activityStartCount = 0;
  DateTime? lastActivityStart;
  String? lastFlutterViewVisibilityAtStart;

  /// Round 4: a native Android `ViewTreeObserver.OnGlobalFocusChangeListener`
  /// firing, reported from MainActivity.kt as "from -> to" simple class
  /// names ("null" for either side). This is Android's own View-level focus,
  /// distinct from Flutter's `FocusNode.hasFocus` (tracked separately above
  /// as focusGained/focusLost). See this file's header comment (Round 4
  /// addition).
  int nativeFocusChangeCount = 0;
  DateTime? lastNativeFocusChangeTime;
  String? lastNativeFocusChange;

  /// Ticks on every recorded event so [KeyboardFocusDebugOverlay] can
  /// rebuild without polling.
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  void recordConnectionClosed() {
    connectionClosedCount++;
    lastConnectionClosed = DateTime.now();
    tick.value++;
  }

  void recordFocusChange({required bool hasFocus}) {
    if (hasFocus) {
      focusGainedCount++;
      lastFocusGained = DateTime.now();
    } else {
      focusLostCount++;
      lastFocusLost = DateTime.now();
    }
    tick.value++;
  }

  void recordConnectionOpened() {
    connectionOpenedCount++;
    lastConnectionOpened = DateTime.now();
    tick.value++;
  }

  void recordExplicitClose() {
    explicitCloseCount++;
    lastExplicitClose = DateTime.now();
    tick.value++;
  }

  void recordOnNewIntent() {
    onNewIntentCount++;
    lastOnNewIntent = DateTime.now();
    tick.value++;
  }

  /// Round 4: see this file's header comment (Round 4 addition).
  void recordActivityStop({required String flutterViewVisibility}) {
    activityStopCount++;
    lastActivityStop = DateTime.now();
    lastFlutterViewVisibilityAtStop = flutterViewVisibility;
    tick.value++;
  }

  /// Round 4: see this file's header comment (Round 4 addition).
  void recordActivityStart({required String flutterViewVisibility}) {
    activityStartCount++;
    lastActivityStart = DateTime.now();
    lastFlutterViewVisibilityAtStart = flutterViewVisibility;
    tick.value++;
  }

  /// Round 4: see this file's header comment (Round 4 addition).
  void recordNativeFocusChange({required String from, required String to}) {
    nativeFocusChangeCount++;
    lastNativeFocusChangeTime = DateTime.now();
    lastNativeFocusChange = '$from -> $to';
    tick.value++;
  }

  /// Test-only: resets all counters so widget tests get a clean slate
  /// regardless of test execution order (this is a process-wide singleton).
  @visibleForTesting
  void resetForTesting() {
    connectionClosedCount = 0;
    lastConnectionClosed = null;
    focusGainedCount = 0;
    lastFocusGained = null;
    focusLostCount = 0;
    lastFocusLost = null;
    connectionOpenedCount = 0;
    lastConnectionOpened = null;
    explicitCloseCount = 0;
    lastExplicitClose = null;
    onNewIntentCount = 0;
    lastOnNewIntent = null;
    activityStopCount = 0;
    lastActivityStop = null;
    lastFlutterViewVisibilityAtStop = null;
    activityStartCount = 0;
    lastActivityStart = null;
    lastFlutterViewVisibilityAtStart = null;
    nativeFocusChangeCount = 0;
    lastNativeFocusChangeTime = null;
    lastNativeFocusChange = null;
  }
}

/// Small, persistent on-screen corner badge showing
/// [KeyboardFocusDebugCounters.instance]'s current counts and last-fired
/// timestamps.
///
/// Deliberately persistent, not a transient flash/snackbar: the scenario of
/// interest for this verification round (backgrounding the app with the
/// keyboard open, then foregrounding it) happens while the screen isn't
/// being watched, so the state must still be readable immediately on
/// return — a flash shown only at the moment of the event would be missed.
class KeyboardFocusDebugOverlay extends StatefulWidget {
  const KeyboardFocusDebugOverlay({super.key});

  @override
  State<KeyboardFocusDebugOverlay> createState() =>
      _KeyboardFocusDebugOverlayState();
}

class _KeyboardFocusDebugOverlayState extends State<KeyboardFocusDebugOverlay>
    with WidgetsBindingObserver {
  final _counters = KeyboardFocusDebugCounters.instance;

  @override
  void initState() {
    super.initState();
    _counters.tick.addListener(_onTick);
    // Mirrors QuikiEditorState's own didChangeMetrics() observer (see its
    // doc comment for the full explanation): this overlay is wired into
    // editor_screen.dart's Scaffold body, same as the editor itself, so
    // MediaQuery.viewInsetsOf(context) would always read 0 here too —
    // Scaffold's default resizeToAvoidBottomInset zeroes viewInsets.bottom
    // for its body's descendants. Reading View.of(context).viewInsets
    // instead bypasses that, but doesn't rebuild on its own, hence this
    // observer.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _counters.tick.removeListener(_onTick);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  static String _fmt(DateTime? t) {
    if (t == null) return '--:--:--';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static const _textStyle = TextStyle(
    color: Colors.white,
    fontSize: 10,
    fontFamily: 'monospace',
    height: 1.3,
  );

  @override
  Widget build(BuildContext context) {
    // Read directly here (not via KeyboardFocusDebugCounters) so this is the
    // actual live value, not a count/timestamp snapshot. View.of(context),
    // NOT MediaQuery.viewInsetsOf(context) — see this file's header comment
    // for why MediaQuery would always read 0 at this exact position in the
    // tree. View.of doesn't rebuild its dependents on its own, which is why
    // this State mixes in WidgetsBindingObserver / didChangeMetrics(). This
    // line is what the Round 2 device-verification pass needs to watch —
    // it's the new ground truth quiki_editor.dart's _showCursor() and
    // editor_screen.dart's `keyboardVisible` make their real decisions from.
    //
    // View.viewInsets is in PHYSICAL pixels (unlike MediaQuery's logical-
    // pixel EdgeInsets) — divided by devicePixelRatio below so the displayed
    // number is directly comparable to every other logical-pixel measurement
    // in this codebase (contentPadding, etc.), even though only its sign
    // (>0 or ==0) actually drives _showCursor()'s decision.
    final view = View.of(context);
    final viewInsetsBottom = view.viewInsets.bottom / view.devicePixelRatio;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topRight,
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.only(top: 4, right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'viewInsets.bottom ${viewInsetsBottom.toStringAsFixed(1)}',
                  style: _textStyle,
                ),
                Text(
                  'connClosed ${_counters.connectionClosedCount} '
                  '@ ${_fmt(_counters.lastConnectionClosed)}',
                  style: _textStyle,
                ),
                Text(
                  'focusLost ${_counters.focusLostCount} '
                  '@ ${_fmt(_counters.lastFocusLost)}',
                  style: _textStyle,
                ),
                Text(
                  'focusGained ${_counters.focusGainedCount} '
                  '@ ${_fmt(_counters.lastFocusGained)}',
                  style: _textStyle,
                ),
                Text(
                  'connOpen ${_counters.connectionOpenedCount} '
                  '@ ${_fmt(_counters.lastConnectionOpened)}',
                  style: _textStyle,
                ),
                Text(
                  'explicitClose ${_counters.explicitCloseCount} '
                  '@ ${_fmt(_counters.lastExplicitClose)}',
                  style: _textStyle,
                ),
                Text(
                  'onNewIntent ${_counters.onNewIntentCount} '
                  '@ ${_fmt(_counters.lastOnNewIntent)}',
                  style: _textStyle,
                ),
                Text(
                  'activityStop ${_counters.activityStopCount} '
                  '(${_counters.lastFlutterViewVisibilityAtStop ?? '--'}) '
                  '@ ${_fmt(_counters.lastActivityStop)}',
                  style: _textStyle,
                ),
                Text(
                  'activityStart ${_counters.activityStartCount} '
                  '(${_counters.lastFlutterViewVisibilityAtStart ?? '--'}) '
                  '@ ${_fmt(_counters.lastActivityStart)}',
                  style: _textStyle,
                ),
                Text(
                  'nativeFocus ${_counters.nativeFocusChangeCount} '
                  '(${_counters.lastNativeFocusChange ?? '--'}) '
                  '@ ${_fmt(_counters.lastNativeFocusChangeTime)}',
                  style: _textStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
