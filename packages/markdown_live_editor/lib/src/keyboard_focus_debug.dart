// ============================================================================
// TEMPORARY DEBUG-ONLY INSTRUMENTATION — Rounds 10-11
// notes/dev/keyboard_focus_state.md — device-verification round only.
//
// This file is a fresh, narrowly-scoped recreation of the overlay pattern
// Rounds 1-7 used and removed after Round 7 (see git history for the full
// prior instrumentation, which tracked many more signals across the whole
// investigation). It is NOT a restoration of that file — Round 10 added it
// to answer one specific question, stated in Round 9's own report:
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
// Round 10's answer, captured on-device: yes, it fires TWICE — once
// correctly, then again 328ms later with a stale value matching the
// pre-interruption open height. Filed as issue #394; root cause NOT
// understood. Round 11 added a pragmatic workaround for the visible symptom
// (quiki_editor.dart's _kStaleMetricsGraceWindow suppression) WITHOUT fixing
// #394's actual root cause — see that file's doc comment. This overlay's
// job changed accordingly: it is no longer just a one-question diagnostic to
// retire once answered, it is now the ONLY way (given the project owner's
// GitHub Actions -> sideload build workflow, no attached console) to confirm
// on a real device that the workaround is actually triggering, and to
// notice if #394's underlying cause ever silently goes away on its own.
//
// Do NOT delete this file, or its wiring, until #394 itself is closed (root
// cause identified, and either fixed at the source or confirmed permanently
// gone) — at that point quiki_editor.dart's Round 11 suppression logic and
// this overlay can be removed together. Removing this overlay alone, while
// the Round 11 suppression workaround still exists in quiki_editor.dart,
// would leave that workaround masking #394 with no way to see it happening.
//
// Wiring points, if/when the whole thing is ever removed together:
//   1. packages/markdown_live_editor/lib/src/quiki_editor.dart —
//      QuikiEditorState.didChangeMetrics() calls
//      KeyboardFocusDebugCounters.instance.recordDidChangeMetrics(...) and
//      (Round 11) .recordSuppressedStaleMetrics(...). Remove those calls +
//      the import + the whole Round 11 suppression mechanism (see that
//      file's own doc comments for its own wiring points — it is the actual
//      fix's job to have found #394's root cause by then, not this file's).
//      Do NOT remove the surrounding didChangeMetrics() override itself, or
//      the `if (!_isMobile) return;` guard, or the setState(()) call after
//      it — those are Round 2's real, load-bearing mechanism, not
//      diagnostic.
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
// Three signals, tracked independently, plus a combined chronological log so
// the actual firing order between them is directly visible:
//   - didChangeMetrics: every invocation of QuikiEditorState's
//     WidgetsBindingObserver override, with the View.of(context)
//     .viewInsets.bottom value (converted to logical pixels) read at that
//     exact moment — Round 10's core signal.
//   - windowFocusChanged: every native Activity#onWindowFocusChanged()
//     dispatch reaching editor_screen.dart's MethodChannel handler
//     (MainActivity.kt's dispatch itself is untouched — Round 6/9's kept
//     deferred-post mechanism — this only records the value Dart already
//     receives from it), so it can be correlated against didChangeMetrics'
//     timing without needing native-side changes this round.
//   - suppressedStaleMetrics (Round 11, #394): every time the stale-post-
//     resume-metrics workaround in quiki_editor.dart actually triggers —
//     i.e. a didChangeMetrics reading arriving inside the grace window that
//     follows a confirmed-good post-resume zero reading, and getting
//     distrusted rather than shown. This is the counter that keeps #394's
//     continued presence visible on-device now that its symptom is masked.
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

  /// Round 11 (notes/dev/keyboard_focus_state.md, #394) — every time
  /// [QuikiEditorState]'s post-resume stale-metrics suppression workaround
  /// actually triggers: a [didChangeMetrics] reading arriving inside the
  /// short grace window that follows a confirmed-good post-resume
  /// viewInsets.bottom==0 reading, treated as suspicious and prevented from
  /// making the cursor/toolbar reappear. #394's own root cause (why that
  /// second, stale call fires at all) is NOT understood — this counter
  /// exists so that fact stays visible on-device even after this
  /// workaround masks its visible symptom, rather than silently vanishing
  /// behind the fix. If this counter ever stops incrementing on a device
  /// that used to reproduce #394, that's independent evidence the
  /// underlying root cause may have gone away on its own.
  int suppressedStaleMetricsCount = 0;
  DateTime? lastSuppressedStaleMetrics;
  double? lastSuppressedStaleMetricsValue;

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

  /// Round 11 (#394) — see [suppressedStaleMetricsCount]'s doc comment.
  void recordSuppressedStaleMetrics({required double viewInsetsBottom}) {
    suppressedStaleMetricsCount++;
    lastSuppressedStaleMetrics = DateTime.now();
    lastSuppressedStaleMetricsValue = viewInsetsBottom;
    _logSequence(
      'suppressedStaleMetrics(viewInsets.bottom='
      '${viewInsetsBottom.toStringAsFixed(1)})',
    );
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
    suppressedStaleMetricsCount = 0;
    lastSuppressedStaleMetrics = null;
    lastSuppressedStaleMetricsValue = null;
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
                // Round 11 (#394) — count/last-fired/last-value for the
                // stale-post-resume-metrics suppression workaround actually
                // triggering. See suppressedStaleMetricsCount's doc comment
                // for why this must stay visible rather than be assumed.
                Text(
                  'suppressedStaleMetrics '
                  '${_counters.suppressedStaleMetricsCount} '
                  'insets.bottom='
                  '${_counters.lastSuppressedStaleMetricsValue?.toStringAsFixed(1) ?? '--'} '
                  '@ ${_fmt(_counters.lastSuppressedStaleMetrics)}',
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
