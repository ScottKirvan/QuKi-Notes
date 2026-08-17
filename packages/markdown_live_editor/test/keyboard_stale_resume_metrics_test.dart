// Regression tests for notes/dev/keyboard_focus_state.md's Round 11 —
// suppressing a stale post-resume didChangeMetrics() reading (issue #394).
//
// Background: Round 10's on-screen telemetry captured, on a real device,
// didChangeMetrics() firing TWICE after the app resumes from the
// cross-app-IME-contention scenario — once correctly (viewInsets.bottom=0.0,
// 6ms after resume), then again 328ms later with a WRONG value that exactly
// matches the pre-interruption open keyboard height. QuikiEditorState.
// _showCursor() reflects whichever reading is most recent, so the second,
// stale-looking call is what wins, leaving the toolbar/cursor stuck visible
// over a keyboard that is genuinely, confirmedly closed.
//
// #394's actual root cause (why that second call fires at all) is NOT
// understood and is not what this file tests. This file tests the pragmatic
// workaround: once a genuine viewInsets.bottom==0 reading is confirmed
// shortly after an AppLifecycleState.resumed transition, a short grace
// window suppresses any further nonzero reading from flipping cursor/
// toolbar visibility back on — UNLESS the user takes a genuine, deliberate
// action (a tap into the editor) that legitimately reopens the keyboard.
//
// AppLifecycleState.resumed is simulated via
// WidgetsBinding.instance.handleAppLifecycleStateChanged(...) — Flutter
// test's own real simulation of an app-lifecycle transition, the same
// pattern already used elsewhere in this repo (test/features/setup/
// storage_setup_screen_test.dart). viewInsets changes are simulated via
// tester.view.viewInsets = FakeViewPadding(...), matching
// keyboard_viewinsets_test.dart's established convention.
//
// The suppression window is Timer-based (not DateTime.now() delta
// comparisons), specifically so it is deterministically drivable from a
// widget test via tester.pump(duration) — the same reasoning already
// documented for the Stage 3 auto-scroll Timer.periodic
// (selection_autoscroll_test.dart) and restated in quiki_editor.dart's own
// Round 11 doc comment.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
// Reaches into the package's implementation library rather than its public
// barrel to get at QuikiEditor/QuikiEditorState (debugForceMobile,
// showsCursorForTesting) directly — the same convention already used by
// keyboard_viewinsets_test.dart and keyboard_focus_state_test.dart.
// KeyboardFocusDebugCounters is already re-exported from the public barrel.
import 'package:markdown_live_editor/src/quiki_editor.dart';

// A fresh Key per pumpWidget call forces a real unmount + remount rather
// than an in-place widget update — see notes/dev/testing.md's pumpWidget-
// reuse gotcha.
Widget _buildEditor({
  required String initialValue,
  required FocusNode focusNode,
  MarkdownEditorController? controller,
}) {
  return MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: MarkdownEditor(
        initialValue: initialValue,
        controller: controller,
        focusNode: focusNode,
      ),
    ),
  );
}

QuikiEditorState _quikiStateOf(WidgetTester tester) =>
    tester.state<QuikiEditorState>(find.byType(QuikiEditor));

/// Settles a raw FocusNode.requestFocus()/.unfocus() call — see
/// keyboard_viewinsets_test.dart's identically-named helper for the full
/// explanation (two pumps: one for FocusManager's own scheduled microtask,
/// one for this editor's setState() reacting to it).
Future<void> _settleFocus(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Settles the delayed single-tap resolution this editor's GestureDetector
/// always has — see keyboard_focus_state_test.dart's identically-named
/// helper (a double-tap recognizer unconditionally shares the gesture
/// arena, deferring onTapDown until kDoubleTapTimeout elapses with no
/// second tap).
Future<void> _settleSingleTap(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

void main() {
  setUp(() {
    QuikiEditorState.debugForceMobile = true;
    KeyboardFocusDebugCounters.instance.resetForTesting();
  });

  tearDown(() {
    QuikiEditorState.debugForceMobile = false;
    KeyboardFocusDebugCounters.instance.resetForTesting();
  });

  testWidgets(
      'a stale-looking reading arriving ~328ms after a confirmed post-'
      'resume zero reading is suppressed — the exact #394 repro',
      (tester) async {
    final focusNode = FocusNode();
    await tester.pumpWidget(_buildEditor(
      initialValue: 'hello',
      focusNode: focusNode,
    ));
    await tester.pump();

    // Note was open with the keyboard visible before the interruption.
    focusNode.requestFocus();
    await _settleFocus(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 370);
    await tester.pump();
    expect(_quikiStateOf(tester).showsCursorForTesting, isTrue,
        reason: 'sanity: keyboard visibly up before the interruption');

    // App backgrounds and resumes (Round 2's hard rule: this must not
    // itself touch focus — confirmed unaffected here since nothing calls
    // requestFocus()/unfocus() as part of this simulated resume).
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // The genuine, correct post-resume reading (#394's "6ms" call): the
    // keyboard really did close.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(_quikiStateOf(tester).showsCursorForTesting, isFalse,
        reason: 'sanity: the confirmed-correct zero reading itself must '
            'still hide the cursor immediately');
    expect(KeyboardFocusDebugCounters.instance.suppressedStaleMetricsCount, 0,
        reason: 'sanity: nothing suspicious has happened yet');

    // 328ms later — #394's measured gap — the stale call arrives,
    // reporting the exact pre-interruption open height.
    await tester.pump(const Duration(milliseconds: 328));
    tester.view.viewInsets = const FakeViewPadding(bottom: 370);
    await tester.pump();

    expect(_quikiStateOf(tester).showsCursorForTesting, isFalse,
        reason: 'the stale reading, arriving inside the grace window, must '
            'not be allowed to flip the cursor/toolbar back to visible');
    expect(KeyboardFocusDebugCounters.instance.suppressedStaleMetricsCount, 1,
        reason: 'the suppression must be recorded, not silently swallowed — '
            '#394 must stay visible on-device even while its symptom is '
            'masked');
    // recordDidChangeMetrics/recordSuppressedStaleMetrics both convert the
    // raw physical-pixel viewInsets.bottom to logical pixels via
    // devicePixelRatio (matching production's own conversion) before
    // recording — so the expected value must go through the same division,
    // not assume physical == logical.
    expect(
      KeyboardFocusDebugCounters.instance.lastSuppressedStaleMetricsValue,
      370.0 / tester.view.devicePixelRatio,
      reason: 'the actual suspicious value must be captured, not just the '
          'fact that something was suppressed',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetViewInsets();
  });

  testWidgets(
      'a genuine user tap immediately after resume reopens the keyboard '
      'right away — the suppression window must never block a deliberate '
      'reopen', (tester) async {
    final focusNode = FocusNode();
    await tester.pumpWidget(_buildEditor(
      initialValue: 'hello',
      focusNode: focusNode,
    ));
    await tester.pump();

    focusNode.requestFocus();
    await _settleFocus(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 370);
    await tester.pump();
    expect(_quikiStateOf(tester).hasConnectionForTesting, isTrue,
        reason: 'sanity: focus held, connection attached before resume — '
            'the confirmed-common case where focus is never actually lost '
            'across a real backgrounding interruption');

    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // Confirmed-correct post-resume reading arms the suppression window.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(_quikiStateOf(tester).showsCursorForTesting, isFalse);

    // The user, seeing no keyboard, taps back into the editor to keep
    // typing — well within what would otherwise be the suppression grace
    // window. Focus is already true here, so this exercises _onTapDown's
    // "already focused" (_connection!.show()) branch, NOT _onFocusChanged's
    // focus-gain branch — the one case where cancellation must not depend
    // on a focus transition that never actually happens.
    await tester.tap(find.byType(QuikiEditor));
    await _settleSingleTap(tester);

    // The OS actually raises the keyboard in response to the tap.
    tester.view.viewInsets = const FakeViewPadding(bottom: 370);
    await tester.pump();

    expect(_quikiStateOf(tester).showsCursorForTesting, isTrue,
        reason: 'a deliberate tap-driven reopen must show the cursor '
            'immediately, not be held hidden by the still-open grace '
            'window from the earlier confirmed-zero reading');
    expect(KeyboardFocusDebugCounters.instance.suppressedStaleMetricsCount, 0,
        reason: 'this reading is a genuine reopen, not a suppression — it '
            'must never be counted as one');

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetViewInsets();
  });

  testWidgets(
      'ordinary keyboard open/close during active use, with no resume '
      'ever occurring, is completely unaffected by the Round 11 mechanism',
      (tester) async {
    final focusNode = FocusNode();
    await tester.pumpWidget(_buildEditor(
      initialValue: 'hello',
      focusNode: focusNode,
    ));
    await tester.pump();

    focusNode.requestFocus();
    await _settleFocus(tester);
    expect(_quikiStateOf(tester).showsCursorForTesting, isFalse);

    // Keyboard opens.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(_quikiStateOf(tester).showsCursorForTesting, isTrue);

    // Keyboard closes (e.g. the Android dismiss icon), then reopens a
    // moment later — well within what would be a Round 11 grace window if
    // one had ever been armed, but no AppLifecycleState.resumed transition
    // has occurred anywhere in this test, so no confirmed-zero reading was
    // ever eligible to arm suppression in the first place.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(_quikiStateOf(tester).showsCursorForTesting, isFalse);

    await tester.pump(const Duration(milliseconds: 200));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(_quikiStateOf(tester).showsCursorForTesting, isTrue,
        reason: 'a same-session reopen with no preceding resume must track '
            'the live viewInsets exactly as before Round 11 — nothing here '
            'should ever be suppressed');
    expect(KeyboardFocusDebugCounters.instance.suppressedStaleMetricsCount, 0,
        reason: 'the suppression mechanism must never trigger without a '
            'preceding AppLifecycleState.resumed transition');

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetViewInsets();
  });

  testWidgets(
      'suppression naturally expires once the grace window elapses — a '
      'reading arriving after the window is trusted normally', (tester) async {
    final focusNode = FocusNode();
    await tester.pumpWidget(_buildEditor(
      initialValue: 'hello',
      focusNode: focusNode,
    ));
    await tester.pump();

    focusNode.requestFocus();
    await _settleFocus(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 370);
    await tester.pump();

    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(_quikiStateOf(tester).showsCursorForTesting, isFalse);

    // Let the 800ms grace window fully elapse with nothing else happening.
    await tester.pump(const Duration(milliseconds: 850));

    // A nonzero reading arriving now is outside the grace window and must
    // be trusted like any ordinary reading (this app has no way to tell it
    // apart from a real one — that's the accepted, documented limit of
    // this workaround, not a gap this test is meant to paper over).
    tester.view.viewInsets = const FakeViewPadding(bottom: 370);
    await tester.pump();

    expect(_quikiStateOf(tester).showsCursorForTesting, isTrue,
        reason: 'a reading arriving after the grace window has closed must '
            'not be suppressed — the window is short and tightly scoped, '
            'not a general dampening of _showCursor()');
    expect(KeyboardFocusDebugCounters.instance.suppressedStaleMetricsCount, 0,
        reason: 'a reading outside the grace window is not a suppression '
            'event');

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetViewInsets();
  });

  testWidgets(
      'a nonzero reading after resume, with no confirmed zero reading in '
      'between, is never suppressed — arming requires the genuine-zero '
      'reading, not resume alone', (tester) async {
    final focusNode = FocusNode();
    await tester.pumpWidget(_buildEditor(
      initialValue: 'hello',
      focusNode: focusNode,
    ));
    await tester.pump();

    focusNode.requestFocus();
    await _settleFocus(tester);

    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // Straight to nonzero — no zero reading ever arrived to arm anything.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();

    expect(_quikiStateOf(tester).showsCursorForTesting, isTrue,
        reason: 'with no confirmed-zero reading to arm the grace window, '
            'a nonzero reading must be trusted immediately');
    expect(KeyboardFocusDebugCounters.instance.suppressedStaleMetricsCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetViewInsets();
  });
}
