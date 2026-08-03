// Tests for Stage 4's magnifier/loupe (feat/selection-stage4,
// notes/dev/selection.md §3, ADR-36).
//
// Two layers, deliberately kept separate:
//
//  1. Pure geometry tests against computeMagnifierGeometry — no widget
//     pumping at all. This is where the exact correctness invariants from
//     selection.md §3 (horizontal clamped to the CURRENT LINE's own edges,
//     vertical locked to the line's center regardless of the finger's raw y,
//     "jumps" only when the line changes) are asserted precisely, the same
//     way render_model_test.dart asserts exact offset-map values rather than
//     just toPlainText()/length.
//
//  2. Real-gesture widget tests driving an actual handle drag (matching the
//     discipline established by selection_handles_test.dart /
//     selection_autoscroll_test.dart) that prove the WIRING: the magnifier
//     appears only while a handle drag is active (not for a plain tap or a
//     plain content scroll), its fed geometry matches what
//     QuikiRenderEditor.lineBoundsForRendered independently reports, and the
//     actively-dragged handle's own glyph is invisible for exactly the
//     duration of its own drag.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';
import 'package:markdown_live_editor/src/selection_magnifier.dart';

// ---------------------------------------------------------------------------
// Part 1 — pure geometry
// ---------------------------------------------------------------------------

void _geometryTests() {
  group('computeMagnifierGeometry — pure geometry', () {
    const lensSize = Size(80, 40);
    const magnification = 2.0;
    const verticalShift = 50.0;
    // Wide enough that halfSampleWidth (80/2/2.0 = 20) fits comfortably
    // inside it without triggering the "line narrower than one lens-width"
    // fallback, for the tests that don't want that fallback in play.
    const line = Rect.fromLTWH(100, 200, 300, 20); // left=100 right=400

    QuikiMagnifierGeometry geometryFor(Offset gesture, {Rect? lineBounds}) =>
        computeMagnifierGeometry(
          QuikiMagnifierInfo(
              gesturePosition: gesture, lineBounds: lineBounds ?? line),
          lensSize: lensSize,
          magnificationScale: magnification,
          verticalShift: verticalShift,
        );

    test(
        'gesture comfortably inside the line, away from both edges: the '
        'widget is drawn directly above the gesture x, and samples exactly '
        'that x/line-center — no clamping in play', () {
      final g = geometryFor(const Offset(250, 205));
      expect(g.widgetCenter.dx, 250);
      expect(g.widgetCenter.dy, line.center.dy - verticalShift);
      // No horizontal correction needed — sampled x equals gesture x.
      expect(g.focalPointOffset.dx, 0);
      expect(g.focalPointOffset.dy, verticalShift);
    });

    test(
        'gesture past the line\'s RIGHT edge: the widget clamps to the '
        'line\'s own right edge, and the SAMPLED content is additionally '
        'inset so it never shows past that edge', () {
      final g = geometryFor(const Offset(999, 205));
      expect(g.widgetCenter.dx, line.right,
          reason: 'the lens itself must not be drawn past the line');
      final halfSampleWidth = (lensSize.width / 2) / magnification; // 20
      // focalPointOffset.dx = focalX - widgetX; focalX is inset by
      // halfSampleWidth from the line's right edge; widgetX is the line's
      // right edge itself (both derived above) — so the correction is
      // exactly -halfSampleWidth, pulling the sampled image back inward.
      expect(g.focalPointOffset.dx, -halfSampleWidth,
          reason: 'sampled content must be pulled back inward by exactly '
              'half the lens\'s own (descaled) width so no part of the '
              'magnified image extends past the line\'s true right edge');
    });

    test(
        'gesture past the line\'s LEFT edge: the widget clamps to the '
        'line\'s own left edge, and the SAMPLED content is inset the other '
        'way', () {
      final g = geometryFor(const Offset(-500, 205));
      expect(g.widgetCenter.dx, line.left);
      final halfSampleWidth = (lensSize.width / 2) / magnification;
      expect(g.focalPointOffset.dx, halfSampleWidth);
    });

    test(
        'never shows content past the line\'s actual edges: the sampled '
        'x for a gesture pinned at the extreme right edge is strictly '
        'inside [line.left, line.right], not equal to the edge itself', () {
      final g = geometryFor(const Offset(999, 205));
      final sampledX = g.widgetCenter.dx + g.focalPointOffset.dx;
      expect(sampledX, lessThan(line.right));
      expect(sampledX, greaterThan(line.left));
    });

    test(
        'a line narrower than one lens-width of sampled content: does not '
        'throw (the naive clamp(low, high) with low > high would), and '
        'centers the sample on the line instead', () {
      const narrowLine = Rect.fromLTWH(100, 200, 10, 20); // width 10
      expect(
        () => geometryFor(const Offset(105, 205), lineBounds: narrowLine),
        returnsNormally,
      );
      final g = geometryFor(const Offset(999, 205), lineBounds: narrowLine);
      final sampledX = g.widgetCenter.dx + g.focalPointOffset.dx;
      expect(sampledX, narrowLine.left + narrowLine.width / 2);
    });

    test(
        'vertical lock: two gestures at very different y within the SAME '
        'line resolve to the identical widget/sample y — the raw finger y '
        'within a line must never be tracked, only the line\'s own center', () {
      final gTop = geometryFor(Offset(250, line.top + 1));
      final gBottom = geometryFor(Offset(250, line.bottom - 1));
      expect(gTop.widgetCenter.dy, gBottom.widgetCenter.dy);
      final sampledYTop = gTop.widgetCenter.dy + gTop.focalPointOffset.dy;
      final sampledYBottom =
          gBottom.widgetCenter.dy + gBottom.focalPointOffset.dy;
      expect(sampledYTop, sampledYBottom);
      expect(sampledYTop, line.center.dy,
          reason: 'the sampled y must be the LINE\'s own center, not the '
              'gesture\'s raw y');
    });

    test(
        'line jump: two infos with different lineBounds (as if the drag '
        'crossed into a different visual line) resolve to different '
        'widget/sample y, tracking the NEW line\'s own center', () {
      const otherLine = Rect.fromLTWH(100, 260, 300, 20); // a line below
      final g1 = geometryFor(const Offset(250, 205));
      final g2 = geometryFor(const Offset(250, 265), lineBounds: otherLine);
      expect(g1.widgetCenter.dy, isNot(g2.widgetCenter.dy));
      expect(g2.widgetCenter.dy, otherLine.center.dy - verticalShift);
    });
  });
}

// ---------------------------------------------------------------------------
// Part 2 — real-gesture widget tests
// ---------------------------------------------------------------------------

const _startHandleKey = ValueKey('quiki-selection-handle-start');
const _endHandleKey = ValueKey('quiki-selection-handle-end');

Widget buildEditor({
  required String initialValue,
  MarkdownEditorController? controller,
  double? width,
}) {
  final body =
      MarkdownEditor(initialValue: initialValue, controller: controller);
  return MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: width == null ? body : SizedBox(width: width, child: body),
    ),
  );
}

QuikiRenderEditor renderEditorOf(WidgetTester tester) =>
    tester.renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));

QuikiEditorState editorStateOf(WidgetTester tester) =>
    tester.state<QuikiEditorState>(find.byType(QuikiEditor));

Offset globalPositionForSourceOffset(
  WidgetTester tester,
  QuikiRenderEditor ro,
  int sourceOffset,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: sourceOffset));
  final local = Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + local;
}

/// Independently computes the GLOBAL line-bounds rect
/// QuikiRenderEditor.lineBoundsForRendered reports for source offset
/// [sourceOffset] — reproduces (does not call) the same
/// padding-shift + localToGlobal conversion QuikiEditorState's private
/// _magnifierInfoFor performs, so this stays an independent check on the
/// WIRING between a drag event and the magnifier's fed geometry, not a
/// second call into the exact same private code path.
Rect independentLineBoundsGlobal(
  WidgetTester tester,
  QuikiRenderEditor ro,
  int sourceOffset,
) {
  final ri = ro.renderModel.renderedForSource(sourceOffset);
  final local = ro.lineBoundsForRendered(ri).shift(ro.localPadding.topLeft);
  final topLeft =
      tester.getTopLeft(find.byType(QuikiRenderWidget)) + local.topLeft;
  return topLeft & local.size;
}

Future<QuikiRenderEditor> pumpWithSelection(
  WidgetTester tester, {
  required String source,
  required MarkdownEditorController controller,
  required TextSelection selection,
  double? width,
}) async {
  QuikiEditorState.debugForceMobile = true;
  await tester.pumpWidget(
      buildEditor(initialValue: source, controller: controller, width: width));
  await tester.pump();
  controller.setSelectionForTesting(selection);
  await tester.pump();
  return renderEditorOf(tester);
}

void _wiringTests() {
  tearDown(() {
    QuikiEditorState.debugForceMobile = false;
  });

  group('Magnifier — appears only while dragging a handle', () {
    testWidgets(
        'not shown before a drag, appears the instant a handle drag starts, '
        'and disappears the instant the drag ends', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('beta');
      final endOffset = startOffset + 'beta'.length;
      await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: endOffset),
      );

      final state = editorStateOf(tester);
      expect(state.isMagnifierShownForTesting, isFalse);

      final handleCenter = tester.getCenter(find.byKey(_endHandleKey));
      final gesture = await tester.startGesture(handleCenter,
          kind: PointerDeviceKind.touch);
      await tester.pump();
      expect(state.isMagnifierShownForTesting, isTrue,
          reason: 'the magnifier must appear the moment a handle drag starts');

      await gesture.moveTo(handleCenter + const Offset(10, 0));
      await tester.pump();
      expect(state.isMagnifierShownForTesting, isTrue);

      await gesture.up();
      await tester.pump();
      expect(state.isMagnifierShownForTesting, isFalse,
          reason: 'the magnifier must disappear the moment the drag ends');
    });

    testWidgets(
        'does NOT appear for an ordinary tap, nor for a plain content-scroll '
        'drag that is not on a handle at all', (tester) async {
      final source = List.generate(40, (i) => 'line $i alpha beta').join('\n');
      final controller = MarkdownEditorController();
      await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection: const TextSelection.collapsed(offset: 0),
        width: 300,
      );

      final state = editorStateOf(tester);

      await tester.tapAt(tester.getCenter(find.byType(QuikiRenderWidget)));
      // Drain DoubleTapGestureRecognizer's internal timer — any pointer down
      // through the main editor's GestureDetector arms it, tap or not (see
      // selection_test.dart's doubleTapAt for the full mechanism).
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.isMagnifierShownForTesting, isFalse,
          reason: 'a plain tap must never show the magnifier');

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -100));
      await tester.pump();
      expect(state.isMagnifierShownForTesting, isFalse,
          reason: 'an ordinary content scroll (not a handle drag) must '
              'never show the magnifier');
      // Drain the timer this drag's own pointer-down event armed too (same
      // mechanism as above).
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('Magnifier — fed geometry matches the render object independently', () {
    testWidgets(
        'while dragging within a single line, the magnifier\'s reported '
        'line bounds match QuikiRenderEditor.lineBoundsForRendered exactly, '
        'and stay constant across several updates on that same line',
        (tester) async {
      const source = 'alpha beta gamma delta epsilon zeta';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('beta');
      final endOffset = startOffset + 'beta'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: endOffset),
      );
      final state = editorStateOf(tester);

      final handleCenter = tester.getCenter(find.byKey(_endHandleKey));
      final gesture = await tester.startGesture(handleCenter,
          kind: PointerDeviceKind.touch);
      await tester.pump();

      final expectedLineBounds =
          independentLineBoundsGlobal(tester, ro, endOffset);
      var info = state.magnifierInfoForTesting;
      expect(info.lineBounds.topLeft, expectedLineBounds.topLeft);
      expect(info.lineBounds.bottomRight, expectedLineBounds.bottomRight);

      // Move within the same line — the reported line bounds (in particular
      // the vertical extent) must not change.
      final target = source.indexOf('gamma') + 2;
      final targetGlobal = globalPositionForSourceOffset(tester, ro, target);
      await gesture.moveTo(targetGlobal);
      await tester.pump();

      info = state.magnifierInfoForTesting;
      expect(info.lineBounds.top, expectedLineBounds.top);
      expect(info.lineBounds.bottom, expectedLineBounds.bottom);

      await gesture.up();
      await tester.pump();
    });

    testWidgets(
        'dragging across a line boundary changes the reported line bounds '
        'to the new line\'s own bounds (a "jump"), not a blend of the two',
        (tester) async {
      const source = 'alpha beta gamma\ndelta epsilon zeta';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('beta');
      final endOffset = startOffset + 'beta'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: endOffset),
      );
      final state = editorStateOf(tester);

      final handleCenter = tester.getCenter(find.byKey(_endHandleKey));
      final gesture = await tester.startGesture(handleCenter,
          kind: PointerDeviceKind.touch);
      await tester.pump();
      final lineOneBounds = state.magnifierInfoForTesting.lineBounds;

      final targetOnLineTwo = source.indexOf('epsilon');
      // Matches selection_handles_test.dart's own multi-line convention: the
      // finger's target sits one preferredLineHeight below the text position
      // it should end up controlling, mirroring how a real handle drag is
      // always resolved (see _sourceOffsetForGlobal's doc comment).
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOnLineTwo) +
              Offset(0, ro.preferredLineHeight);
      await gesture.moveTo(targetGlobal);
      await tester.pump();

      final lineTwoBounds = state.magnifierInfoForTesting.lineBounds;
      expect(lineTwoBounds.top, isNot(lineOneBounds.top),
          reason: 'crossing a line boundary must change the reported line, '
              'not keep showing the line the drag started on');

      final expectedLineTwoBounds =
          independentLineBoundsGlobal(tester, ro, targetOnLineTwo);
      expect(lineTwoBounds.top, expectedLineTwoBounds.top);
      expect(lineTwoBounds.bottom, expectedLineTwoBounds.bottom);

      await gesture.up();
      await tester.pump();
    });

    testWidgets(
        'for a wrapped (soft-broken) paragraph, offsets on different visual '
        'lines resolve to line bounds with different vertical positions and '
        'narrower-than-the-run horizontal extents — proves this resolves '
        'the current VISUAL line, not the whole (single, multi-row) block',
        (tester) async {
      // A long, unbroken run of single-character tokens in a narrow
      // viewport forces several soft wraps.
      final source = List.generate(60, (i) => 'w').join(' ');
      final controller = MarkdownEditorController();
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection: const TextSelection.collapsed(offset: 0),
        width: 100,
      );

      final riFirst = ro.renderModel.renderedForSource(0);
      final riLast = ro.renderModel.renderedForSource(source.length - 1);
      final firstLineBounds = ro.lineBoundsForRendered(riFirst);
      final lastLineBounds = ro.lineBoundsForRendered(riLast);

      expect(firstLineBounds.top, isNot(lastLineBounds.top),
          reason: 'the first and last characters of this long paragraph '
              'must land on different visual lines, or this test\'s premise '
              '(that the paragraph actually wraps in a 100px-wide viewport) '
              'does not hold');
      // Each is its own single row, not the multi-row block's total height.
      expect(firstLineBounds.height,
          lessThan(lastLineBounds.top - firstLineBounds.top + 1),
          reason: 'a single visual line\'s own bounds must be one row tall, '
              'not span down to (or past) a later visual line — i.e. this '
              'resolved the WRAPPED sub-line containing offset 0, not the '
              'whole multi-row run/block');
    });
  });

  group('Magnifier — the actively-dragged handle\'s glyph is hidden', () {
    testWidgets(
        'the dragged handle becomes fully transparent for the exact '
        'duration of its own drag, and opaque again once released; the '
        'OTHER (untouched) handle stays visible throughout', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('beta');
      final endOffset = startOffset + 'beta'.length;
      await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: endOffset),
      );

      double opacityOf(Key key) => tester
          .widget<Opacity>(find.descendant(
            of: find.byKey(key),
            matching: find.byType(Opacity),
          ))
          .opacity;

      expect(opacityOf(_startHandleKey), 1.0);
      expect(opacityOf(_endHandleKey), 1.0);

      final handleCenter = tester.getCenter(find.byKey(_endHandleKey));
      final gesture = await tester.startGesture(handleCenter,
          kind: PointerDeviceKind.touch);
      await tester.pump();

      expect(opacityOf(_endHandleKey), 0.0,
          reason: 'the DRAGGED handle must be invisible during its own drag');
      expect(opacityOf(_startHandleKey), 1.0,
          reason: 'the untouched handle must stay visible during the other '
              'handle\'s drag');

      await gesture.moveTo(handleCenter + const Offset(10, 0));
      await tester.pump();
      expect(opacityOf(_endHandleKey), 0.0);

      await gesture.up();
      await tester.pump();
      expect(opacityOf(_endHandleKey), 1.0,
          reason: 'the handle must become visible again once the drag ends');
      expect(opacityOf(_startHandleKey), 1.0);
    });
  });
}

void main() {
  _geometryTests();
  _wiringTests();
}
