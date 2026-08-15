// Regression tests for notes/dev/keyboard_focus_state.md's Round 2 pivot:
// cursor visibility must be driven by the OS's own live keyboard-visible
// signal (View.of(context).viewInsets.bottom on mobile) — NOT
// FocusNode.hasFocus.
//
// Background: Round 1 (connectionClosed() no longer forcing unfocus, see
// keyboard_focus_state_test.dart) was verified on a real device and produced
// conclusive proof that FocusNode.hasFocus never goes false even when the
// keyboard visibly disappears via the Android keyboard's own dismiss icon or
// the system back gesture — cursor/toolbar stayed stuck visible in both
// cases. This file tests the fix: QuikiEditorState._showCursor() now reads
// the platform's live keyboard-inset signal on mobile instead.
//
// viewInsets changes are simulated via tester.view.viewInsets = FakeViewPadding(...)
// — Flutter test's own real simulation of the OS reporting inset changes —
// not by toggling an internal boolean directly, matching this suite's
// established rigor bar (see keyboard_focus_state_test.dart, checkbox_toggle_scroll_test.dart).
//
// "Mobile" is forced via QuikiEditorState.debugForceMobile, the same
// established pattern used throughout this suite (selection_handles_test.dart,
// selection_autoscroll_test.dart, etc.) to exercise mobile-only branches on a
// desktop/CI test host where Platform.isAndroid is always false.
//
// Pump-count note: a raw FocusNode.requestFocus()/.unfocus() call applies via
// a scheduled microtask (FocusManager.applyFocusChangesIfNeeded), and this
// editor's own render-object rebuild in response to that (via
// QuikiEditorState._onFocusChanged()'s setState()) needs a SECOND pump to
// actually flush into a rebuilt frame that a GlobalKey-based render-object
// read (showsCursorForTesting) will see — confirmed empirically here the
// same way keyboard_focus_state_test.dart already documents for a different
// setState() chain (the debug overlay's). Every test below settles focus
// with two pumps before asserting on showsCursorForTesting for this reason.
// A subsequent viewInsets-only change (focus already settled, nothing about
// focus itself changing again) does NOT carry this same tax — confirmed by
// the "no extra frame of lag" test below, which deliberately isolates that
// claim from focus-settling latency.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
// Reaches into the package's implementation library rather than its public
// barrel to get at QuikiEditor/QuikiEditorState directly (for
// debugForceMobile and showsCursorForTesting) — the same convention already
// used by keyboard_focus_state_test.dart and reading_mode_safety_test.dart.
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

/// Settles a raw FocusNode.requestFocus()/.unfocus() call — see this file's
/// header comment for why two pumps are required.
Future<void> _settleFocus(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  tearDown(() {
    QuikiEditorState.debugForceMobile = false;
  });

  group('mobile: cursor follows viewInsets.bottom, not FocusNode.hasFocus', () {
    setUp(() => QuikiEditorState.debugForceMobile = true);

    testWidgets(
        'cursor is hidden while focused if viewInsets.bottom is 0 — the '
        "exact reported bug (keyboard visibly gone via Android's own "
        'dismiss icon or back gesture, but focus stays true)', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
      ));
      await tester.pump();

      focusNode.requestFocus();
      await _settleFocus(tester);

      expect(focusNode.hasFocus, isTrue, reason: 'sanity: focus was granted');
      expect(tester.view.viewInsets.bottom, 0.0,
          reason: 'sanity: no keyboard inset simulated yet');
      expect(_quikiStateOf(tester).showsCursorForTesting, isFalse,
          reason: 'focus alone must not be enough to show the cursor on '
              'mobile — this is the whole point of the Round 2 pivot');

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });

    testWidgets(
        'cursor becomes visible once viewInsets.bottom > 0 while focused',
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

      // Simulate the OS actually raising the keyboard, as happens
      // asynchronously and separately from the focus request itself.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      expect(_quikiStateOf(tester).showsCursorForTesting, isTrue,
          reason: 'viewInsets.bottom > 0 while focused must show the cursor');

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });

    testWidgets(
        'cursor hides again when viewInsets.bottom returns to 0 while focus '
        'remains true — mirrors connectionClosed() no longer force-'
        "unfocusing, and Round 1's one open risk (Android's own keyboard-"
        'dismiss icon not clearing focus)', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
      ));
      await tester.pump();

      focusNode.requestFocus();
      await _settleFocus(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(_quikiStateOf(tester).showsCursorForTesting, isTrue);

      // Keyboard dismissed by the OS (e.g. the Android dismiss icon) without
      // anything in this app calling unfocus() — focus stays true.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();

      expect(focusNode.hasFocus, isTrue,
          reason: 'sanity: nothing in this scenario touched focus directly');
      expect(_quikiStateOf(tester).showsCursorForTesting, isFalse,
          reason: 'cursor must hide when the keyboard visibly goes away, '
              'even though FocusNode.hasFocus is still true');

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });

    testWidgets(
        'no extra frame of lag: once focus has fully settled, a SINGLE pump '
        'after a viewInsets change already reflects the new cursor state — '
        'isolated from focus-settling latency itself (guards against this '
        "implementation introducing its own staleness; see #340's prior, "
        'unrelated viewInsets staleness bug on StreamScreen for why this is '
        'worth guarding explicitly, even though that bug is a different '
        'consumer entirely)', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
      ));
      await tester.pump();
      focusNode.requestFocus();
      await _settleFocus(tester);
      expect(_quikiStateOf(tester).showsCursorForTesting, isFalse,
          reason: 'sanity: focus is fully settled and viewInsets is still 0');

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump(); // exactly one pump — no settle window
      expect(_quikiStateOf(tester).showsCursorForTesting, isTrue,
          reason: 'once focus itself is no longer in flux, a viewInsets '
              'change read via MediaQuery-equivalent live state must reflect '
              'on the very next frame, not one frame later');

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump(); // exactly one pump
      expect(_quikiStateOf(tester).showsCursorForTesting, isFalse,
          reason: 'the same must hold for the inset dropping back to zero');

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });

    testWidgets(
        'requestFocus()/connection-attach mechanics are unaffected by '
        'viewInsets — a tap still attaches the IME connection regardless of '
        'the keyboard-visible signal used for cursor paint (non-regression)',
        (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
      ));
      await tester.pump();

      expect(_quikiStateOf(tester).hasConnectionForTesting, isFalse);

      focusNode.requestFocus();
      await tester.pump();

      expect(focusNode.hasFocus, isTrue,
          reason: 'requestFocus() mechanics are completely untouched by '
              'this pivot');
      expect(_quikiStateOf(tester).hasConnectionForTesting, isTrue,
          reason: 'the IME connection attaches on focus exactly as before, '
              'independent of viewInsets — cursor paint is the only thing '
              'that changed, not what makes a keyboard appear at all');

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });

    testWidgets(
        'existing note reopen still lands with no cursor visible — must '
        'not regress the one thing Round 1 already had working reliably',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'existing note body',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();
      // Mirrors _onActiveQukiChanged's unfocus() call for an existing QuKi —
      // no keyboard inset is ever simulated in this scenario, matching a
      // real cold open where no keyboard has been requested.
      controller.unfocus();
      await _settleFocus(tester);

      expect(focusNode.hasFocus, isFalse);
      expect(_quikiStateOf(tester).showsCursorForTesting, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });

    testWidgets(
        'new note creation still shows the cursor once the keyboard comes '
        'up — must not regress the other reliable Round 1 scenario',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      // Mirrors _onActiveQukiChanged's requestFocus() call for a brand-new
      // QuKi, followed by the OS actually raising the keyboard in response.
      controller.requestFocus();
      await _settleFocus(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
      expect(_quikiStateOf(tester).showsCursorForTesting, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });
  });

  group('desktop: cursor still follows FocusNode.hasFocus (non-regression)',
      () {
    // debugForceMobile deliberately left false (the default) — this group
    // exercises the fallback branch real desktop builds take, which has no
    // software keyboard and therefore never raises viewInsets.bottom above
    // 0. If cursor visibility unconditionally switched to viewInsets on
    // every platform, the cursor would never show at all on Windows/Linux.

    testWidgets(
        'cursor shows on focus alone, with viewInsets.bottom pinned at 0 '
        '(no software keyboard exists on desktop)', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
      ));
      await tester.pump();

      expect(tester.view.viewInsets.bottom, 0.0,
          reason: 'sanity: desktop never raises this');

      focusNode.requestFocus();
      await _settleFocus(tester);

      expect(_quikiStateOf(tester).showsCursorForTesting, isTrue,
          reason: 'on desktop, focus alone must still be sufficient — '
              'there is no OS keyboard inset to wait for');

      focusNode.unfocus();
      await _settleFocus(tester);

      expect(_quikiStateOf(tester).showsCursorForTesting, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
