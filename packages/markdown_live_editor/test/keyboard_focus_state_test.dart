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
      expect(find.textContaining('connOpen 0'), findsOneWidget,
          reason: 'Round 3 addition');
      expect(find.textContaining('explicitClose 0'), findsOneWidget,
          reason: 'Round 3 addition');
      expect(find.textContaining('onNewIntent 0'), findsOneWidget,
          reason: 'Round 3 addition');
      expect(find.textContaining('activityStop 0'), findsOneWidget,
          reason: 'Round 4 addition');
      expect(find.textContaining('activityStart 0'), findsOneWidget,
          reason: 'Round 4 addition');
      expect(find.textContaining('nativeFocus 0'), findsOneWidget,
          reason: 'Round 4 addition');
      expect(find.textContaining('windowFocus 0'), findsOneWidget,
          reason: 'Round 5 addition');
      expect(find.textContaining('restoreAttempted 0'), findsOneWidget,
          reason: 'Round 5 addition');
      expect(find.textContaining('nativeIme 0 visible=--'), findsOneWidget,
          reason: 'Round 7 addition');

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

    testWidgets(
        'connOpen increments on a genuine new attach, not on a redundant '
        'open of an already-attached connection — Round 3 addition',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(_buildEditorWithOverlay(
        initialValue: '',
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      // Focus changes apply via a scheduled microtask (see the focus
      // gained/lost test above for the full explanation) — a second pump is
      // needed for the overlay's setState to flush into a rebuilt frame.
      focusNode.requestFocus();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('connOpen 1'), findsOneWidget,
          reason: 'requesting focus attaches a new IME connection');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'explicitClose increments when this app\'s own code closes an '
        'existing connection (a real unfocus via _onFocusChanged -> '
        '_closeConnection), matching focusLost — Round 3 addition',
        (tester) async {
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

      controller.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('connOpen 1'), findsOneWidget);

      controller.unfocus();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('explicitClose 1'), findsOneWidget,
          reason: '_closeConnection() is only reached from _onFocusChanged() '
              'on a real focus loss, so it must fire exactly once alongside '
              'focusLost here');
      expect(find.textContaining('focusLost 1'), findsOneWidget);
      expect(find.textContaining('connClosed 0'), findsOneWidget,
          reason: 'this is an app-driven close, not a platform-driven one — '
              'connectionClosed() must not also have fired');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'activityStop/activityStart/nativeFocus counters increment and are '
        'reflected on screen — Round 4 addition (these are driven from '
        'MainActivity.kt over the lifecycle_debug MethodChannel in '
        'production; this test exercises the counters + overlay directly, '
        'since the native side cannot be exercised from a widget test)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KeyboardFocusDebugOverlay()),
      ));
      await tester.pump();

      KeyboardFocusDebugCounters.instance
          .recordActivityStop(flutterViewVisibility: 'GONE');
      await tester.pump();
      expect(find.textContaining('activityStop 1 (GONE)'), findsOneWidget);

      KeyboardFocusDebugCounters.instance
          .recordActivityStart(flutterViewVisibility: 'VISIBLE');
      await tester.pump();
      expect(find.textContaining('activityStart 1 (VISIBLE)'), findsOneWidget);

      KeyboardFocusDebugCounters.instance
          .recordNativeFocusChange(from: 'FlutterView', to: 'null');
      await tester.pump();
      expect(find.textContaining('nativeFocus 1 (FlutterView -> null)'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'windowFocus/restoreAttempted counters increment and are reflected '
        'on screen — Round 5 addition (windowFocus is driven from '
        'MainActivity.kt over the lifecycle_debug MethodChannel, and '
        'restoreAttempted from editor_screen.dart\'s handler for it, in '
        'production; this test exercises the counters + overlay directly, '
        'since neither the native side nor the app-level MethodChannel '
        'dispatch can be exercised from a widget test — see the '
        'restoreFocusAfterInterruption() group below for coverage of the '
        'actual fix mechanism)', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KeyboardFocusDebugOverlay()),
      ));
      await tester.pump();

      KeyboardFocusDebugCounters.instance
          .recordWindowFocusChanged(hasFocus: false);
      await tester.pump();
      expect(find.textContaining('windowFocus 1 (false)'), findsOneWidget);

      KeyboardFocusDebugCounters.instance
          .recordWindowFocusChanged(hasFocus: true);
      await tester.pump();
      expect(find.textContaining('windowFocus 2 (true)'), findsOneWidget);

      KeyboardFocusDebugCounters.instance.recordFocusRestoreAttempted();
      await tester.pump();
      expect(find.textContaining('restoreAttempted 1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'nativeIme counter increments and shows visibility + the raw bottom '
        'inset converted to logical pixels — Round 7 addition (driven from '
        'MainActivity.kt\'s ViewCompat.setOnApplyWindowInsetsListener over '
        'the lifecycle_debug MethodChannel in production; this test '
        'exercises the counter + overlay directly, since the native side '
        'cannot be exercised from a widget test)', (tester) async {
      // Pinned to 1.0 rather than relying on the ambient default — unlike
      // `viewInsets`, `devicePixelRatio` has no test-harness-wide default of
      // 1.0; TestFlutterView.devicePixelRatio falls back to the actual host
      // display's real ratio when not overridden (confirmed by reading
      // flutter_test's window.dart directly, after this assumption caused a
      // real, host-dependent test failure while writing this). Pinning here
      // makes the 370 -> 370.0 conversion below deterministic across
      // machines. Reset afterward so this doesn't leak into other tests.
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KeyboardFocusDebugOverlay()),
      ));
      await tester.pump();

      // Asserts the raw physical-pixel value is actually divided through the
      // same View.of(context).devicePixelRatio path viewInsets.bottom
      // already uses, not just passed through unconverted.
      KeyboardFocusDebugCounters.instance.recordNativeInsetsChanged(
        imeVisible: true,
        imeBottomPx: 370,
      );
      await tester.pump();

      expect(find.textContaining('nativeIme 1 visible=true bottom=370.0'),
          findsOneWidget,
          reason: 'must show the incremented count, the reported IME '
              'visibility, and the bottom inset converted to logical pixels');

      KeyboardFocusDebugCounters.instance.recordNativeInsetsChanged(
        imeVisible: false,
        imeBottomPx: 0,
      );
      await tester.pump();

      expect(find.textContaining('nativeIme 2 visible=false bottom=0.0'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'a nativeInsets entry appears in sequenceLog alongside windowFocus, '
        'in actual firing order — Round 7 addition: this is what lets the '
        'next device test see directly whether a fresh native inset ever '
        'arrives after the restore chain runs', (tester) async {
      final counters = KeyboardFocusDebugCounters.instance;
      expect(counters.sequenceLog, isEmpty, reason: 'sanity: clean slate');

      counters.recordWindowFocusChanged(hasFocus: true);
      counters.recordNativeInsetsChanged(imeVisible: true, imeBottomPx: 0);

      expect(counters.sequenceLog.length, 2);
      expect(counters.sequenceLog[0], contains('windowFocus(true)'));
      expect(counters.sequenceLog[1],
          contains('nativeInsets(visible=true,bottomPx=0)'));
    });

    testWidgets(
        'sequenceLog records events in the order they actually occurred, '
        'with each event\'s own label — Round 6 addition (cross-app IME '
        'contention): the per-event "last fired" fields above cannot tell a '
        'single clean event cycle apart from two overlapping ones, which is '
        'exactly what the next device test needs to distinguish',
        (tester) async {
      final counters = KeyboardFocusDebugCounters.instance;
      expect(counters.sequenceLog, isEmpty, reason: 'sanity: clean slate');

      counters.recordWindowFocusChanged(hasFocus: false);
      counters.recordFocusRestoreAttempted();
      counters.recordWindowFocusChanged(hasFocus: true);

      expect(counters.sequenceLog.length, 3);
      expect(counters.sequenceLog[0], contains('windowFocus(false)'));
      expect(counters.sequenceLog[1], contains('restoreAttempted'));
      expect(counters.sequenceLog[2], contains('windowFocus(true)'));
    });

    testWidgets(
        'sequenceLog caps at its max size, dropping the oldest entries '
        'first — Round 6 addition: this is a live diagnostic for one '
        'verification session, not an unbounded audit log', (tester) async {
      final counters = KeyboardFocusDebugCounters.instance;

      for (var i = 0; i < 45; i++) {
        counters.recordFocusRestoreAttempted();
      }

      expect(counters.sequenceLog.length, 40,
          reason: 'must cap rather than grow unboundedly');
    });

    testWidgets(
        'resetForTesting clears the sequence log along with every other '
        'counter', (tester) async {
      final counters = KeyboardFocusDebugCounters.instance;
      counters.recordFocusRestoreAttempted();
      expect(counters.sequenceLog, isNotEmpty, reason: 'sanity');

      counters.resetForTesting();

      expect(counters.sequenceLog, isEmpty);
    });

    testWidgets(
        'the overlay renders the most recent sequence entries, newest '
        'first — Round 6 addition', (tester) async {
      final counters = KeyboardFocusDebugCounters.instance;
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: KeyboardFocusDebugOverlay()),
      ));
      await tester.pump();

      counters.recordWindowFocusChanged(hasFocus: false);
      await tester.pump();
      counters.recordWindowFocusChanged(hasFocus: true);
      await tester.pump();

      expect(find.textContaining('— recent —'), findsOneWidget);
      // Newest entry (windowFocus(true)) must render, not just be recorded.
      expect(find.textContaining('windowFocus(true)'), findsOneWidget);
      expect(find.textContaining('windowFocus(false)'), findsOneWidget);

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
      // interruption (see keyboard_focus_debug.dart's header comment) — but
      // it's a real, independently-confirmed reachable state (e.g. the
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
      controller.onFocusChanged = () {
        KeyboardFocusDebugCounters.instance
            .recordFocusChange(hasFocus: controller.hasActiveBlock);
      };
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

      final counters = KeyboardFocusDebugCounters.instance;
      final connOpenBefore = counters.connectionOpenedCount;
      final explicitCloseBefore = counters.explicitCloseCount;
      final connClosedBefore = counters.connectionClosedCount;
      final focusLostBefore = counters.focusLostCount;
      final focusGainedBefore = counters.focusGainedCount;

      // Deliberately NOT simulating tester.testTextInput.closeConnection()
      // here — the confirmed device evidence for the actual bug this fixes
      // is that NONE of the TextInputClient-level signals change during a
      // real backgrounding interruption (connectionClosed() itself never
      // fires — see keyboard_focus_debug.dart's header comment). The only
      // thing that silently breaks is native View-level focus, underneath
      // where any Dart-level API can observe or simulate it directly. So the
      // accurate starting state to exercise restoreFocusAfterInterruption()
      // against is exactly what's already true after the requestFocus()
      // above: focus true, connection still open and (as far as Flutter's
      // own bookkeeping is concerned) still attached — restoreFocusAfterInterruption()
      // must force a genuine close+reopen regardless, without needing a
      // prior real close to react to.
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
      expect(counters.explicitCloseCount, explicitCloseBefore + 1,
          reason: 'the forced unfocus() must have genuinely committed — '
              'closing the still-open connection via the real '
              '_onFocusChanged -> _closeConnection path');
      expect(counters.connectionOpenedCount, connOpenBefore + 1,
          reason: 'the forced requestFocus() must have genuinely committed '
              'too — opening a brand new connection via the real '
              '_onFocusChanged -> _openConnection path, not silently no-op '
              "the way a bare requestFocus() alone does (see the control "
              'case test above)');
      expect(counters.connectionClosedCount, connClosedBefore,
          reason: 'connectionClosed() (the platform-driven TextInputClient '
              'callback) must NOT have fired — this whole mechanism is '
              "driven by this app's own _onFocusChanged listener, matching "
              'the real device evidence that connectionClosed() never fires '
              'during the actual bug being fixed');
      expect(counters.focusLostCount, focusLostBefore + 1,
          reason: 'the host app\'s onFocusChanged callback must see the '
              'transient unfocus too, not just this package\'s internal '
              'connection bookkeeping');
      expect(counters.focusGainedCount, focusGainedBefore + 1);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
