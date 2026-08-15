// Regression tests for notes/dev/keyboard_focus_state.md's one substantive
// code change: QuikiEditorState.connectionClosed() must stop calling
// widget.focusNode.unfocus(). Root cause this fixes: this app's own
// connectionClosed() forced EVERY reason the platform tears down the IME
// connection into a visible reading-mode transition (cursor/toolbar hidden),
// including reasons that are not a deliberate user dismissal (confirmed via
// a source-level trace against the Flutter SDK — see that doc for the full
// citations) — most importantly, something in this app's own stack was
// apparently triggering connectionClosed() on backgrounding, a scenario
// stock Flutter's Android embedding never generates a connectionClosed()
// call for at all.
//
// Connection closure is simulated via tester.testTextInput.closeConnection()
// — Flutter test's own built-in simulation of "the platform closed the IME
// connection" (e.g. Android's own dismiss control, or backgrounding) — rather
// than calling QuikiEditorState.connectionClosed() directly, so these tests
// exercise the exact same dispatch path (TextInput._currentConnection
// .._client.connectionClosed()) production code goes through.
//
// Also covers the temporary on-screen diagnostic overlay
// (keyboard_focus_debug.dart) added for this same verification round: a
// basic smoke test that it renders and its counters increment on the
// relevant events. This instrumentation is temporary and should be removed
// once notes/dev/keyboard_focus_state.md's device-verification checklist is
// complete — see that file's header comment for the full removal list.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
// Reaches into the package's implementation library rather than its public
// barrel to get at QuikiEditor/QuikiEditorState directly (for the
// @visibleForTesting hasConnectionForTesting getter) — the same convention
// already used by reading_mode_safety_test.dart (for
// QuikiRenderEditor/QuikiRenderWidget) and elsewhere in this suite.
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

/// Mirrors the production layout (MarkdownEditor inside an Expanded Column
/// child) so the KeyboardFocusDebugOverlay tests below don't hit an
/// unbounded-height layout failure — QuikiEditor's internal Stack needs a
/// bounded height, which a bare Column does not provide to its children.
Widget _buildEditorWithOverlay({
  required String initialValue,
  required FocusNode focusNode,
  required MarkdownEditorController controller,
}) {
  return MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: MarkdownEditor(
                  initialValue: initialValue,
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ],
          ),
          const KeyboardFocusDebugOverlay(),
        ],
      ),
    ),
  );
}

QuikiEditorState _quikiStateOf(WidgetTester tester) =>
    tester.state<QuikiEditorState>(find.byType(QuikiEditor));

/// Settles the delayed single-tap resolution this editor's GestureDetector
/// always has — see reading_mode_safety_test.dart's identically-named
/// helper for the full explanation (a double-tap recognizer unconditionally
/// shares the gesture arena, deferring onTapDown until kDoubleTapTimeout
/// elapses with no second tap).
Future<void> _settleSingleTap(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

void main() {
  group('connectionClosed() no longer forces an unfocus', () {
    testWidgets(
        'focus remains true after the platform closes the IME connection — '
        'regression: notes/dev/keyboard_focus_state.md', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue, reason: 'sanity: focus was granted');
      expect(_quikiStateOf(tester).hasConnectionForTesting, isTrue,
          reason: 'sanity: requesting focus opened a connection');

      tester.testTextInput.closeConnection();
      await tester.pump();

      expect(focusNode.hasFocus, isTrue,
          reason: 'connectionClosed() must not itself call unfocus() — '
              'connection teardown and focus loss are no longer the same '
              "event forced together by this app's own code");
      expect(_quikiStateOf(tester).hasConnectionForTesting, isFalse,
          reason: 'the connection itself must still be recognized as gone — '
              'this fix only stops the SIDE EFFECT of unfocusing, not the '
              'connection teardown itself');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('_onTapDown reconnect fallback (non-regression)', () {
    testWidgets(
        'a tap after the connection closes reopens it and accepts IME '
        'input, with focus true and connection null in between',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      focusNode.requestFocus();
      await tester.pump();

      // Simulate the platform tearing down the IME connection (e.g. the
      // Android keyboard's own dismiss control) without the user otherwise
      // doing anything that would independently unfocus the editor.
      tester.testTextInput.closeConnection();
      await tester.pump();

      // The exact state this fallback branch in _onTapDown must handle:
      // focus still true, but no attached connection.
      expect(focusNode.hasFocus, isTrue);
      expect(_quikiStateOf(tester).hasConnectionForTesting, isFalse,
          reason: 'sanity: the connection must be genuinely gone, or this '
              'test would not actually exercise the reconnect branch');

      // A tap anywhere in the editor body should hit the "connection == "
      // "null, reconnect" branch of _onTapDown (focusNode.hasFocus is "
      // "already true, so the "request focus" branch is not the one taken).
      await tester.tap(find.byType(QuikiEditor));
      await _settleSingleTap(tester);

      expect(_quikiStateOf(tester).hasConnectionForTesting, isTrue,
          reason: 'a tap while focused-but-disconnected must reopen the IME '
              'connection (the _onTapDown fallback branch)');

      // The reopened connection must actually accept input — not just
      // exist.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello!',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, 'hello!',
          reason: 'the reopened connection must accept real IME input, not '
              'just report as attached');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('KeyboardFocusDebugOverlay (temporary verification-round instrument)',
      () {
    setUp(() => KeyboardFocusDebugCounters.instance.resetForTesting());

    testWidgets('renders without error and shows zeroed counters initially',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KeyboardFocusDebugOverlay()),
      ));
      await tester.pump();

      expect(find.byType(KeyboardFocusDebugOverlay), findsOneWidget);
      expect(find.textContaining('connClosed 0'), findsOneWidget);
      expect(find.textContaining('focusLost 0'), findsOneWidget);
      expect(find.textContaining('focusGained 0'), findsOneWidget);
      expect(find.textContaining('viewInsets.bottom 0.0'), findsOneWidget,
          reason: 'Round 2 addition — the overlay must also show the live '
              'viewInsets.bottom value, starting at 0 with no keyboard '
              'inset simulated');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'shows the live viewInsets.bottom value and updates when it changes '
        '— regression: this overlay sits inside editor_screen.dart\'s '
        'Scaffold body, the exact position where MediaQuery.viewInsetsOf '
        'would always read 0 (Scaffold.resizeToAvoidBottomInset zeroes it '
        'for body descendants) — View.of(context).viewInsets must be used '
        'instead, confirmed here via a real simulated inset change, not '
        'just reasoned about', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KeyboardFocusDebugOverlay()),
      ));
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      expect(find.textContaining('viewInsets.bottom 0.0'), findsNothing,
          reason: 'must reflect the nonzero simulated inset, not the '
              'always-0 value MediaQuery would give at this tree position');

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();

      expect(find.textContaining('viewInsets.bottom 0.0'), findsOneWidget,
          reason: 'must also reflect the inset returning to 0');

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetViewInsets();
    });

    testWidgets('connectionClosed count increments and is reflected on screen',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(_buildEditorWithOverlay(
        initialValue: '',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      focusNode.requestFocus();
      await tester.pump();

      tester.testTextInput.closeConnection();
      await tester.pump();

      expect(find.textContaining('connClosed 1'), findsOneWidget,
          reason: 'the overlay must reflect a real connectionClosed() fire');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'focus gained/lost counts increment as a proxy for '
        'requestFocus()/unfocus()', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      controller.onFocusChanged = () {
        KeyboardFocusDebugCounters.instance
            .recordFocusChange(hasFocus: controller.hasActiveBlock);
      };
      await tester.pumpWidget(_buildEditorWithOverlay(
        initialValue: '',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      // Focus changes are applied via a scheduled microtask
      // (FocusManager.applyFocusChangesIfNeeded, scheduled from
      // _markNextFocus), not synchronously — a second pump is needed for the
      // overlay's setState (triggered from within that microtask) to
      // actually flush into a rebuilt frame. Confirmed empirically: a single
      // pump left the on-screen text stale at the prior count even though
      // the underlying counter had already incremented.
      controller.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('focusGained 1'), findsOneWidget);

      controller.unfocus();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('focusLost 1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
