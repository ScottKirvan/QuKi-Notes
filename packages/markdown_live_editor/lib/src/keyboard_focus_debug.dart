// ============================================================================
// TEMPORARY DEBUG-ONLY INSTRUMENTATION — Round 10
// notes/dev/keyboard_focus_state.md — device-verification round only.
//
// This file is a fresh, narrowly-scoped recreation of the overlay pattern
// Rounds 1-7 used and removed after Round 7 (see git history for the full
// prior instrumentation, which tracked many more signals across the whole
// investigation). It is NOT a restoration of that file — it exists to
// answer exactly one still-open question, stated in Round 9's own report:
//
//   Round 8's adb logcat capture proved Android's own automatic
//   hide-on-resume genuinely and unambiguously completes (onHidden) after
//   this app's forced-show request loses a ~1ms race against it. Round 9
//   stopped the app from forcing that show, so the automatic hide should no
//   longer be contested. Round 9's own device test still showed the stuck
//   toolbar/cursor/blank-keyboard-area symptom. That means
//   QuikiEditorState._showCursor()'s ground-truth signal —
//   View.of(context).viewInsets.bottom > 0, refreshed only via
//   didChangeMetrics() — is not correctly following that real, confirmed
//   hide. Does didChangeMetrics() even fire after this exact resume
//   sequence, and if so, with what viewInsets.bottom value?
//
// Delete this whole file, plus its two wiring points, once that question is
// answered and the resulting fix (or next diagnostic round) has landed:
//   1. packages/markdown_live_editor/lib/src/quiki_editor.dart —
//      QuikiEditorState.didChangeMetrics() calls
//      KeyboardFocusDebugCounters.instance.recordDidChangeMetrics(...) with
//      the exact viewInsets.bottom value it reads at that moment. Remove
//      that call + the import. Do NOT remove the surrounding
//      didChangeMetrics() override itself, or the `if (!_isMobile) return;`
//      guard, or the setState(()) call after it — those are Round 2's real,
//      load-bearing mechanism, not this round's diagnostic.
//   2. lib/features/editor/editor_screen.dart — _EditorScreenState's
//      MethodChannel handler for 'onWindowFocusChanged' calls
//      KeyboardFocusDebugCounters.instance.recordWindowFocusChanged(...)
//      before its existing (unchanged, Round 9) _pendingFocusRestore logic.
//      Remove that one call + the import. Do NOT touch the
//      _pendingFocusRestore false->true pairing logic itself — that's
//      Round 5/9's kept plumbing, not this round's diagnostic. Also remove
//      the Stack wrapper around the editor body (restoring SafeArea's direct
//      Column child) and the KeyboardFocusDebugOverlay() widget within it.
//
// Two signals, tracked independently, plus a combined chronological log so
// the actual firing order between them is directly visible:
//   - didChangeMetrics: every invocation of QuikiEditorState's
//     WidgetsBindingObserver override, with the View.of(context)
//     .viewInsets.bottom value (converted to logical pixels) read at that
//     exact moment — the core new signal this round exists to capture.
//   - windowFocusChanged: every native Activity#onWindowFocusChanged()
//     dispatch reaching editor_screen.dart's MethodChannel handler
//     (MainActivity.kt's dispatch itself is untouched — Round 6/9's kept
//     deferred-post mechanism — this only records the value Dart already
//     receives from it), so it can be correlated against didChangeMetrics'
//     timing without needing native-side changes this round.
//
// Counts and timestamps (and the bare numeric inset value) only — never
// logs, transmits, or persists QuKi content. Nothing here touches
// shared_preferences or any other persistence; state lives only in memory
// for the current app session, same discipline as every prior round.
// ============================================================================

import 'package:flutter/material.dart';

/// Shared, in-memory counters for the two events this round's
/// notes/dev/keyboard_focus_state.md verification pass needs visibility
/// into. See this file's header comment for the full context.
class KeyboardFocusDebugCounters {
  KeyboardFocusDebugCounters._();

  /// Process-wide singleton — deliberately not scoped to one editor
  /// instance, so it survives across QuKi switches within one app session.
  static final KeyboardFocusDebugCounters instance =
      KeyboardFocusDebugCounters._();

  /// [QuikiEditorState.didChangeMetrics] firing, with the
  /// `View.of(context).viewInsets.bottom` value (logical pixels) read at
  /// that exact moment. This is the core signal this round exists to
  /// capture — see this file's header comment.
  int didChangeMetricsCount = 0;
  DateTime? lastDidChangeMetrics;
  double? lastDidChangeMetricsViewInsetsBottom;

  /// Native `Activity#onWindowFocusChanged()`, reported from
  /// MainActivity.kt over the existing (Round 5/6/9) lifecycle_debug
  /// channel. Recorded here purely to correlate against
  /// [didChangeMetricsCount] in [sequenceLog] — the underlying dispatch and
  /// `_pendingFocusRestore` handling are unchanged from Round 9.
  int windowFocusChangedCount = 0;
  DateTime? lastWindowFocusChangedTime;
  bool? lastWindowFocusChangedValue;

  /// A rolling, millisecond-timestamped log of every event recorded below,
  /// in the actual order they occur — the per-event "last fired" fields
  /// above can only show the most recent occurrence of each signal in
  /// isolation, not their relative order or gaps, which is exactly what
  /// answers whether didChangeMetrics fires at all post-resume, fires late,
  /// or fires with a stale value. Capped at [_maxSequenceLogEntries] —
  /// oldest entries drop off — since this is a live diagnostic aid for one
  /// verification session, not a persisted audit log.
  static const _maxSequenceLogEntries = 40;
  final List<String> _sequenceLog = [];

  /// Most recent entries last (chronological order) — see [_sequenceLog].
  List<String> get sequenceLog => List.unmodifiable(_sequenceLog);

  void _logSequence(String label) {
    final t = DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    _sequenceLog.add('$hh:$mm:$ss.$ms $label');
    if (_sequenceLog.length > _maxSequenceLogEntries) {
      _sequenceLog.removeAt(0);
    }
  }

  /// Ticks on every recorded event so [KeyboardFocusDebugOverlay] can
  /// rebuild without polling.
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  void recordDidChangeMetrics({required double viewInsetsBottom}) {
    didChangeMetricsCount++;
    lastDidChangeMetrics = DateTime.now();
    lastDidChangeMetricsViewInsetsBottom = viewInsetsBottom;
    _logSequence(
      'didChangeMetrics(viewInsets.bottom=${viewInsetsBottom.toStringAsFixed(1)})',
    );
    tick.value++;
  }

  void recordWindowFocusChanged({required bool hasFocus}) {
    windowFocusChangedCount++;
    lastWindowFocusChangedTime = DateTime.now();
    lastWindowFocusChangedValue = hasFocus;
    _logSequence('windowFocus($hasFocus)');
    tick.value++;
  }

  /// Test-only: resets all counters so widget tests get a clean slate
  /// regardless of test execution order (this is a process-wide singleton).
  @visibleForTesting
  void resetForTesting() {
    didChangeMetricsCount = 0;
    lastDidChangeMetrics = null;
    lastDidChangeMetricsViewInsetsBottom = null;
    windowFocusChangedCount = 0;
    lastWindowFocusChangedTime = null;
    lastWindowFocusChangedValue = null;
    _sequenceLog.clear();
  }
}

/// Small, persistent on-screen corner badge showing
/// [KeyboardFocusDebugCounters.instance]'s current counts and last-fired
/// values/timestamps.
///
/// Deliberately persistent, not a transient flash/snackbar: the scenario of
/// interest for this verification round (backgrounding the app with the
/// keyboard open, switching to another app with its own keyboard, then
/// switching back) happens while the screen isn't being watched, so the
/// state must still be readable immediately on return — a flash shown only
/// at the moment of the event would be missed.
class KeyboardFocusDebugOverlay extends StatefulWidget {
  const KeyboardFocusDebugOverlay({super.key});

  @override
  State<KeyboardFocusDebugOverlay> createState() =>
      _KeyboardFocusDebugOverlayState();
}

class _KeyboardFocusDebugOverlayState
    extends State<KeyboardFocusDebugOverlay> {
  final _counters = KeyboardFocusDebugCounters.instance;

  @override
  void initState() {
    super.initState();
    _counters.tick.addListener(_onTick);
  }

  @override
  void dispose() {
    _counters.tick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
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
                  'didChangeMetrics ${_counters.didChangeMetricsCount} '
                  'insets.bottom='
                  '${_counters.lastDidChangeMetricsViewInsetsBottom?.toStringAsFixed(1) ?? '--'} '
                  '@ ${_fmt(_counters.lastDidChangeMetrics)}',
                  style: _textStyle,
                ),
                Text(
                  'windowFocus ${_counters.windowFocusChangedCount} '
                  '(${_counters.lastWindowFocusChangedValue ?? '--'}) '
                  '@ ${_fmt(_counters.lastWindowFocusChangedTime)}',
                  style: _textStyle,
                ),
                // Most-recent-first, capped to the last 16 so the overlay
                // doesn't grow unboundedly tall on a long session — the
                // full (longer) history is still in
                // KeyboardFocusDebugCounters.instance.sequenceLog for
                // anything that needs more than the on-screen view.
                if (_counters.sequenceLog.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text('— recent —', style: _textStyle),
                  ..._counters.sequenceLog.reversed
                      .take(16)
                      .map((e) => Text(e, style: _textStyle)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
