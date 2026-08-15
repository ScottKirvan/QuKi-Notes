// ============================================================================
// TEMPORARY DEBUG-ONLY INSTRUMENTATION
// notes/dev/keyboard_focus_state.md — device-verification round only.
//
// Delete this whole file, plus its two wiring points, once that doc's
// "Required device verification" checklist is complete:
//   1. packages/markdown_live_editor/lib/src/quiki_editor.dart —
//      connectionClosed() calls KeyboardFocusDebugCounters.instance
//      .recordConnectionClosed(). Remove that one line + the import.
//   2. lib/features/editor/editor_screen.dart — _EditorScreenState wraps its
//      Scaffold in a Stack with a KeyboardFocusDebugOverlay() in a corner,
//      and its onFocusChanged closure records a focus gained/lost event.
//      Remove the Stack wrapper, the overlay widget, and that one line.
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
