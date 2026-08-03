// Tests for Stage 4's haptic feedback (feat/selection-stage4,
// notes/dev/selection.md §5, ADR-36).
//
// Flutter's HapticFeedback API is a thin static wrapper over
// SystemChannels.platform.invokeMethod('HapticFeedback.vibrate', ...) — the
// SAME method name is used for every haptic "flavor"; only the (optional)
// string argument distinguishes a bare HapticFeedback.vibrate() call from a
// HapticFeedback.selectionClick() call. This file installs a mock handler on
// SystemChannels.platform (the standard flutter_test interception mechanism
// — see clipboard_toolbar_test.dart / html_paste_test.dart for the same
// pattern already used elsewhere in this suite) and asserts on the recorded
// MethodCalls' arguments, not just their count.
//
// Mapping (see quiki_editor.dart's doc comments on
// _fireBoundaryCrossingHapticIfChanged and the two _onLongPressStart /
// _onDoubleTapDown call sites for the full reasoning):
//   - entity selection trigger (long-press / double-tap landing on a real
//     word/entity) -> HapticFeedback.vibrate() (bare, arguments == null) —
//     documented by Flutter itself as simulating Android's LONG_PRESS
//     constant, matching selection.md §5's "same category of feedback as a
//     long-press anywhere else in Android."
//   - handle-drag character-boundary crossing -> HapticFeedback.
//     selectionClick() (arguments == 'HapticFeedbackType.selectionClick') —
//     the exact same call Flutter's own stock TextSelectionOverlay fires at
//     the identical moment (a handle-drag boundary changing) for its own
//     built-in selection handles (widgets/text_selection.dart).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Haptic call recorder
// ---------------------------------------------------------------------------

class _HapticRecorder {
  final List<MethodCall> calls = [];

  Future<Object?> handleMethodCall(MethodCall call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      calls.add(call);
    }
    return null;
  }

  /// Calls whose argument is null — i.e. a bare HapticFeedback.vibrate().
  List<MethodCall> get bareVibrateCalls =>
      calls.where((c) => c.arguments == null).toList();

  /// Calls carrying the selectionClick type argument.
  List<MethodCall> get selectionClickCalls => calls
      .where((c) => c.arguments == 'HapticFeedbackType.selectionClick')
      .toList();

  void reset() => calls.clear();
}

// ---------------------------------------------------------------------------
// Helpers — mirrors selection_test.dart / selection_handles_test.dart.
// ---------------------------------------------------------------------------

const _endHandleKey = ValueKey('quiki-selection-handle-end');

Widget buildEditor({
  required String initialValue,
  MarkdownEditorController? controller,
}) {
  return MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: MarkdownEditor(initialValue: initialValue, controller: controller),
    ),
  );
}

QuikiRenderEditor renderEditorOf(WidgetTester tester) =>
    tester.renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));

Offset globalPositionForSourceOffset(
  WidgetTester tester,
  QuikiRenderEditor ro,
  int sourceOffset,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: sourceOffset));
  final local = Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + local;
}

/// Mirrors selection_test.dart's doubleTapAt exactly (see that file's doc
/// comment for why the trailing pump is longer than kDoubleTapTimeout).
Future<void> doubleTapAt(WidgetTester tester, Offset location) async {
  await tester.tapAt(location);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(location);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final recorder = _HapticRecorder();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      recorder.handleMethodCall,
    );
    recorder.reset();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    QuikiEditorState.debugForceMobile = false;
  });

  group('Entity-selection haptic — long-press', () {
    testWidgets(
        'long-pressing a plain word fires exactly one bare '
        'HapticFeedback.vibrate() call', (tester) async {
      const source = 'hello world';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(
          buildEditor(initialValue: source, controller: controller));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final pos = globalPositionForSourceOffset(
          tester, ro, source.indexOf('world') + 2);
      await tester.longPressAt(pos);
      await tester.pump();

      expect(recorder.bareVibrateCalls, hasLength(1),
          reason: 'a long-press that lands on and selects a real word must '
              'fire exactly one long-press-category haptic');
      expect(recorder.selectionClickCalls, isEmpty,
          reason: 'the entity-selection trigger must use the bare vibrate() '
              'call, not selectionClick()');
    });

    testWidgets(
        'long-pressing whitespace (no word/entity under the finger, '
        'selection stays collapsed) fires NO haptic at all', (tester) async {
      const source = 'hello   world';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(
          buildEditor(initialValue: source, controller: controller));
      await tester.pump();
      final ro = renderEditorOf(tester);

      // Land squarely inside the run of spaces between the two words — no
      // word, email, or numeric pattern matches whitespace, so
      // _selectEntityAt falls back to a collapsed cursor.
      final pos =
          globalPositionForSourceOffset(tester, ro, source.indexOf('   ') + 1);
      await tester.longPressAt(pos);
      await tester.pump();

      expect(controller.selectionForTesting.isCollapsed, isTrue,
          reason: 'test premise: this position must not resolve to a '
              'non-collapsed entity selection, or this test proves nothing');
      expect(recorder.calls, isEmpty,
          reason: 'no haptic should fire when the gesture did not actually '
              'trigger a word/entity selection');
    });
  });

  group('Entity-selection haptic — double-tap', () {
    testWidgets(
        'double-tapping a plain word fires exactly one bare '
        'HapticFeedback.vibrate() call, the same as long-press',
        (tester) async {
      const source = 'hello world';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(
          buildEditor(initialValue: source, controller: controller));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final pos = globalPositionForSourceOffset(
          tester, ro, source.indexOf('world') + 2);
      await doubleTapAt(tester, pos);

      expect(recorder.bareVibrateCalls, hasLength(1));
      expect(recorder.selectionClickCalls, isEmpty);
    });
  });

  group('Handle-drag boundary-crossing haptic', () {
    testWidgets(
        'dragging a handle across several distinct characters fires one '
        'selectionClick() haptic per DISTINCT resolved character — not '
        'once per pointer-move event', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      QuikiEditorState.debugForceMobile = true;
      await tester.pumpWidget(
          buildEditor(initialValue: source, controller: controller));
      await tester.pump();
      final startOffset = source.indexOf('beta');
      final initialEnd = startOffset + 'beta'.length;
      controller.setSelectionForTesting(
        TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );
      await tester.pump();
      final ro = renderEditorOf(tester);

      final handleCenter = tester.getCenter(find.byKey(_endHandleKey));
      final gesture = await tester.startGesture(handleCenter,
          kind: PointerDeviceKind.touch);
      await tester.pump();
      recorder.reset(); // pan-start itself must not fire a boundary haptic.

      // Move to 3 DISTINCT character offsets, each visited via two
      // moveTo calls (the second a no-op repeat of the same resolved
      // position) — 6 pointer-move events total, but only 3 genuine
      // character-boundary crossings.
      final targets = [
        source.indexOf('gamma') + 1,
        source.indexOf('gamma') + 3,
        source.indexOf('delta') + 1,
      ];
      for (final t in targets) {
        final g = globalPositionForSourceOffset(tester, ro, t);
        await gesture.moveTo(g);
        await tester.pump();
        await gesture.moveTo(g); // exact repeat — must not fire again
        await tester.pump();
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(recorder.selectionClickCalls, hasLength(3),
          reason: 'expected exactly one haptic per distinct character '
              'crossing (3), not one per pointer-move event (6) — actual '
              'calls: ${recorder.calls.map((c) => c.arguments).toList()}');
      expect(recorder.bareVibrateCalls, isEmpty,
          reason: 'a handle drag must never fire the entity-selection '
              'flavor of haptic');
    });

    testWidgets(
        'a drag that starts and ends without ever changing the resolved '
        'character fires no boundary-crossing haptic at all', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      QuikiEditorState.debugForceMobile = true;
      await tester.pumpWidget(
          buildEditor(initialValue: source, controller: controller));
      await tester.pump();
      final startOffset = source.indexOf('beta');
      final initialEnd = startOffset + 'beta'.length;
      controller.setSelectionForTesting(
        TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );
      await tester.pump();

      final handleCenter = tester.getCenter(find.byKey(_endHandleKey));
      final gesture = await tester.startGesture(handleCenter,
          kind: PointerDeviceKind.touch);
      await tester.pump();
      recorder.reset();

      // A sub-pixel jiggle that must resolve to the same character every
      // time (a single glyph is many pixels wide at test-default font
      // sizes).
      await gesture.moveTo(handleCenter + const Offset(0.2, 0));
      await tester.pump();
      await gesture.moveTo(handleCenter + const Offset(0.4, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(recorder.selectionClickCalls, isEmpty);
    });
  });
}
