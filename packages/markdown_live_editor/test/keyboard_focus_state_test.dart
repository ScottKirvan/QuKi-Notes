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
// Also covers MarkdownEditorController.restoreFocusAfterInterruption() —
// notes/dev/keyboard_focus_state.md's Round 5 fix for the resume-after-
// interruption bug, which forces a genuine unfocus->refocus cycle (verified
// against the platform-channel call log Flutter's own test framework
// records, TestTextInput.log) rather than relying on a bare requestFocus(),
// which is a confirmed no-op when FocusManager already believes the node is
// focused.

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

  group(
      'MarkdownEditorController.restoreFocusAfterInterruption() — Round 5 '
      'fix (notes/dev/keyboard_focus_state.md, resume-after-interruption)', () {
    testWidgets(
        'is a no-op when the editor does not currently hold focus — must '
        'never grant focus the editor did not have before an interruption',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      expect(focusNode.hasFocus, isFalse, reason: 'sanity: starts unfocused');

      controller.restoreFocusAfterInterruption();
      await tester.pump();
      await tester.pump();

      expect(focusNode.hasFocus, isFalse,
          reason: 'must not grant focus the editor never had');
      expect(_quikiStateOf(tester).hasConnectionForTesting, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'a bare requestFocus() call on an already-"focused" node is a '
        'no-op — control case proving the naive fix this method avoids '
        'really is insufficient, not just assumed to be', (tester) async {
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
      await tester.pump();
      expect(_quikiStateOf(tester).hasConnectionForTesting, isTrue,
          reason: 'sanity: focus granted a real connection');

      // Construct "connection gone, focus still true" the same way the
      // connectionClosed()-no-longer-unfocuses tests above do (platform
      // closes the connection; FocusNode.hasFocus is untouched by design —
      // see notes/dev/keyboard_focus_state.md's root fix). This is not
      // itself a simulation of the resume-after-interruption bug this round
      // fixes — confirmed device evidence for THAT bug is that
      // connectionClosed() never fires at all during a real backgrounding
      // interruption (see notes/dev/keyboard_focus_state.md's "Investigation
      // rounds" section, Round 1) — but it's a real, independently-confirmed
      // reachable state (e.g. the
      // Android keyboard's own dismiss control) that happens to share the
      // exact "focus true, connection gone" shape this control case needs to
      // demonstrate the general FocusManager no-op claim.
      tester.testTextInput.closeConnection();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue,
          reason: 'sanity: FocusNode is untouched by a platform-driven '
              'connection close');
      expect(_quikiStateOf(tester).hasConnectionForTesting, isFalse,
          reason: 'sanity: the connection is genuinely gone');

      // The naive fix: a bare requestFocus() on a node the manager still
      // believes is already the primary focus.
      focusNode.requestFocus();
      await tester.pump();
      await tester.pump();

      expect(_quikiStateOf(tester).hasConnectionForTesting, isFalse,
          reason: 'a bare requestFocus() on an already-"focused" node must '
              'NOT reopen the connection — FocusManager treats the request '
              'as a no-op since nothing in its own bookkeeping believes '
              'focus ever changed, so no notification is ever fired '
              '(confirmed by tracing FocusManager._markNextFocus in the '
              'Flutter SDK source, not assumed)');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'forces a genuine unfocus->refocus transition and reopens the '
        'connection, when the editor held focus before an interruption '
        'that left FocusNode.hasFocus untouched', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      controller.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(_quikiStateOf(tester).hasConnectionForTesting, isTrue,
          reason: 'sanity: focus granted a real connection');

      // Verified via the platform-channel call log Flutter's own test
      // framework already records (TestTextInput.log), rather than any
      // app-specific instrumentation — a genuine close+reopen shows up as
      // real TextInput.clearClient / TextInput.setClient invocations, not
      // just an unchanged Dart-side hasConnectionForTesting reading.
      tester.testTextInput.log.clear();

      // Deliberately NOT simulating tester.testTextInput.closeConnection()
      // here — the confirmed device evidence for the actual bug this fixes
      // is that NONE of the TextInputClient-level signals change during a
      // real backgrounding interruption (connectionClosed() itself never
      // fires — see notes/dev/keyboard_focus_state.md's "Investigation
      // rounds" section, Rounds 4-5). The only thing that silently breaks is
      // native View-level focus, underneath where any Dart-level API can
      // observe or simulate it directly. So the accurate starting state to
      // exercise restoreFocusAfterInterruption() against is exactly what's
      // already true after the requestFocus() above: focus true, connection
      // still open and (as far as Flutter's own bookkeeping is concerned)
      // still attached — restoreFocusAfterInterruption() must force a
      // genuine close+reopen regardless, without needing a prior real close
      // to react to.
      controller.restoreFocusAfterInterruption();
      await tester.pump();
      await tester.pump();

      expect(focusNode.hasFocus, isTrue,
          reason: 'ends focused — this restores a focus state that was '
              'genuinely active, it does not leave the editor unfocused');
      expect(_quikiStateOf(tester).hasConnectionForTesting, isTrue,
          reason: 'a brand new IME connection must have been opened — this '
              'is the actual fix: a fresh TextInputConnection.show() call '
              'reaches Android\'s TextInputPlugin.showTextInput(), which '
              'calls the hosting View\'s requestFocus() (confirmed by '
              'reading the Flutter engine source directly), re-establishing '
              'the native focus signal device diagnostics showed getting '
              'stuck cleared');

      final methodNames =
          tester.testTextInput.log.map((call) => call.method).toList();
      final clearIndex = methodNames.indexOf('TextInput.clearClient');
      final setIndex = methodNames.lastIndexOf('TextInput.setClient');
      expect(clearIndex, isNot(-1),
          reason: 'the forced unfocus() must have genuinely committed — '
              'closing the still-open connection via the real '
              '_onFocusChanged -> _closeConnection path, reaching the '
              'platform channel (TextInput.clearClient), not just updating '
              "Dart-side bookkeeping");
      expect(setIndex, isNot(-1),
          reason: 'the forced requestFocus() must have genuinely committed '
              'too — opening a brand new connection via the real '
              '_onFocusChanged -> _openConnection path (TextInput.setClient '
              'on the platform channel), not silently no-op the way a bare '
              'requestFocus() alone does (see the control case test above)');
      expect(clearIndex < setIndex, isTrue,
          reason: 'the close must genuinely precede the reopen — a real '
              'unfocus -> refocus cycle, not a reopen that happens to be '
              'followed by an unrelated close');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
