// Tests for Stage 3 auto-scroll while dragging a selection handle near a
// viewport edge (feat/selection-stage3, notes/dev/selection.md §4, ADR-36).
//
// Every drag here is a REAL simulated gesture on the actual handle widget
// (tester.startGesture / moveTo / up), matching the discipline established
// by selection_handles_test.dart's Stage 2 suite. What Stage 3 adds beyond
// that suite is HOLDING the pointer stationary near a viewport edge across
// many auto-scroll ticks and asserting the resulting selection/handle
// position stays correct on intermediate ticks — not just once the
// document settles at its final scroll position. That distinction matters:
// a test that only checks the state after auto-scroll finishes could pass
// even if every INTERMEDIATE tick briefly resolved against a stale paint
// transform, exactly the class of bug Stage 2 Round 1 needed a real device
// to catch for the simpler (single scroll event) case.
//
// The STARTING selection in each test is established via
// controller.setSelectionForTesting rather than a real long-press/
// double-tap gesture, for the same reason selection_handles_test.dart's
// suite does this — see that file's doc comment.
//
// Auto-scroll is driven by a plain Timer.periodic (see quiki_editor.dart's
// _autoScrollTimer doc comment for why). flutter_test runs test bodies
// inside a FakeAsync zone, so that timer only fires when the test
// explicitly advances virtual time via tester.pump(duration) — this file
// pumps in explicit _autoScrollInterval-sized steps (matching the timer's
// own period) so exactly one timer tick, and exactly one resulting frame,
// happens per pump call. That is what makes it possible to assert on
// intermediate ticks deterministically, with no reliance on real wall-clock
// timing this suite has no way to control.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _startHandleKey = ValueKey('quiki-selection-handle-start');
const _endHandleKey = ValueKey('quiki-selection-handle-end');
const _viewportContainerKey = ValueKey('autoscroll-viewport-container');

/// Matches quiki_editor.dart's own _autoScrollInterval. Kept as a literal
/// here (not imported — that constant is private) rather than derived, so a
/// future change to the production constant is forced to also touch this
/// file's assumption explicitly rather than silently drifting.
const _autoScrollInterval = Duration(milliseconds: 16);

/// A viewport-sized (below-the-fold-having) document: enough lines that a
/// 300px-tall viewport shows only a fraction of it, in both directions from
/// the middle.
String _buildLongSource({int lines = 80}) =>
    List.generate(lines, (i) => 'line $i alpha beta gamma delta').join('\n');

QuikiRenderEditor renderEditorOf(WidgetTester tester) =>
    tester.renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));

ScrollableState scrollableOf(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first);

/// Independently computes where a handle's visible glyph should be centered
/// on screen for [sourceOffset] — reimplemented from scratch here (mirrors
/// selection_handles_test.dart's identically-named/reasoned helper) rather
/// than trusting the handle widget's own reported position, so it can serve
/// as a genuine external check.
Offset independentHandleCenter(
  QuikiRenderEditor ro, {
  required int sourceOffset,
  required bool isStart,
}) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: sourceOffset)) +
      ro.localPadding.topLeft;
  final anchorLocal = Offset(caret.dx, caret.dy + ro.preferredLineHeight);
  final anchorGlobal = ro.localToGlobal(anchorLocal);
  const inset = 12.0;
  const diameter = 20.0;
  const hitBoxCenter = Offset(22.0, 22.0);
  final pointLocal = isStart
      ? const Offset(inset + diameter, inset)
      : const Offset(inset, inset);
  final topLeft = anchorGlobal - pointLocal;
  return topLeft + hitBoxCenter;
}

/// Independently resolves the source offset a handle drag touching
/// [globalPosition] should currently produce — reimplements
/// QuikiEditorState._sourceOffsetForGlobal's exact math (globalToLocal, then
/// subtract one preferredLineHeight to undo the handle's below-line paint
/// offset, then positionForOffset) from public API only, so it stays an
/// independent check rather than exercising the same private code path
/// twice.
int independentSourceOffsetForGlobal(
  QuikiRenderEditor ro,
  Offset globalPosition,
) {
  final local = ro.globalToLocal(globalPosition);
  final corrected = local - Offset(0, ro.preferredLineHeight);
  return ro.positionForOffset(corrected).offset;
}

/// Explicitly scrolls the viewport so [sourceOffset] lands roughly
/// [marginFromTop]px below the viewport's own top edge.
///
/// Needed because production's own "keep the caret visible on load" logic
/// (_scheduleScrollToCaret in quiki_editor.dart) only acts on a COLLAPSED
/// selection — it deliberately no-ops for a non-collapsed one (an active
/// handle drag's selection is never collapsed, so this guard matters
/// throughout Stage 2/3, not just here). A non-collapsed selection set
/// programmatically deep in a long document therefore does NOT scroll into
/// view on its own, so any test needing the viewport pre-positioned at a
/// specific spot (e.g. to test auto-scrolling back UP toward the document
/// start, which requires the viewport to have started away from the top)
/// must position it explicitly, exactly as this helper does.
void scrollSoOffsetIsVisible(
  QuikiRenderEditor ro,
  ScrollableState scrollable,
  int sourceOffset, {
  double marginFromTop = 150,
}) {
  final targetY = ro.getOffsetForCaret(TextPosition(offset: sourceOffset)).dy +
      ro.localPadding.top;
  final desired =
      (targetY - marginFromTop).clamp(0.0, scrollable.position.maxScrollExtent);
  scrollable.position.jumpTo(desired);
}

Future<void> moveGestureInSteps(
  WidgetTester tester,
  TestGesture gesture,
  Offset from,
  Offset to, {
  int steps = 5,
}) async {
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump();
  }
}

/// Pumps a fixed-height (300px) viewport around a long document, with
/// handles forced visible and an initial selection set programmatically.
Future<QuikiRenderEditor> pumpTallDocument(
  WidgetTester tester, {
  required String source,
  required MarkdownEditorController controller,
  required TextSelection selection,
  double viewportHeight = 300,
}) async {
  QuikiEditorState.debugForceMobile = true;
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: SizedBox(
        key: _viewportContainerKey,
        height: viewportHeight,
        child: MarkdownEditor(initialValue: source, controller: controller),
      ),
    ),
  ));
  await tester.pump();
  controller.setSelectionForTesting(selection);
  await tester.pump();
  return renderEditorOf(tester);
}

void main() {
  tearDown(() {
    QuikiEditorState.debugForceMobile = false;
  });

  group('Auto-scroll — extends selection into off-screen content', () {
    testWidgets(
        'holding a drag near the BOTTOM edge with more content below '
        'extends the selection into content that was not visible when the '
        'drag started, and the boundary stays correct on an intermediate '
        'tick — not just once scrolling settles', (tester) async {
      final source = _buildLongSource();
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('line 1 ');
      final initialEnd = startOffset + 'line 1'.length;

      final ro = await pumpTallDocument(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      final viewportRect = tester.getRect(find.byKey(_viewportContainerKey));
      final bottomEdgeTouch =
          Offset(viewportRect.center.dx, viewportRect.bottom - 5);

      final handleStart = tester.getCenter(find.byKey(_endHandleKey));
      final gesture =
          await tester.startGesture(handleStart, kind: PointerDeviceKind.touch);
      await moveGestureInSteps(tester, gesture, handleStart, bottomEdgeTouch);

      final scrollable = scrollableOf(tester);
      final offsetAtDragStart = scrollable.position.pixels;

      double? midTickOffset;
      for (var i = 0; i < 20; i++) {
        await tester.pump(_autoScrollInterval);
        if (i == 9) {
          // Mid-sequence check, deliberately not at the end of the loop:
          // the selection boundary must already match an independently
          // recomputed offset for the CURRENT scroll position.
          midTickOffset = scrollable.position.pixels;
          final expected =
              independentSourceOffsetForGlobal(ro, bottomEdgeTouch);
          expect(controller.selectionForTesting.end, expected,
              reason: 'mid-drag (tick $i): the selection boundary must '
                  'already match the independently-recomputed offset for '
                  'the pointer at the CURRENT scroll position, not a stale '
                  'earlier one (scroll pixels=$midTickOffset)');
        }
      }

      await gesture.up();
      await tester.pump();

      final finalOffset = scrollable.position.pixels;
      expect(finalOffset, greaterThan(offsetAtDragStart),
          reason: 'holding near the bottom edge must have scrolled the '
              'viewport downward');
      expect(midTickOffset, isNotNull);
      expect(midTickOffset, greaterThan(offsetAtDragStart),
          reason: 'scrolling must already have progressed partway through '
              'the hold, proving it is continuous across ticks rather than '
              'a single jump');
      expect(midTickOffset, lessThan(finalOffset),
          reason: 'scroll offset must keep increasing across further ticks '
              'while the pointer stays held in the edge zone');

      final sel = controller.selectionForTesting;
      expect(sel.start, startOffset,
          reason: 'auto-scrolling the END handle must not move the start '
              'boundary');
      expect(sel.end, greaterThan(initialEnd),
          reason: 'the selection must have extended further into the '
              'document than what was visible when the drag started');
    });

    testWidgets(
        'holding a drag near the TOP edge with more content above extends '
        'the selection backward into content that was not visible when the '
        'drag started, and the boundary stays correct on an intermediate '
        'tick — not just once scrolling settles', (tester) async {
      final source = _buildLongSource();
      final controller = MarkdownEditorController();
      // Selection deep enough into the document that the viewport, on
      // first pump, is scrolled well past the top — see
      // _scheduleScrollToCaret, which keeps a fresh selection's caret
      // visible on load.
      final lineStart = source.indexOf('line 60');
      final wordStart = source.indexOf('gamma', lineStart);
      final wordEnd = wordStart + 'gamma'.length;

      final ro = await pumpTallDocument(
        tester,
        source: source,
        controller: controller,
        selection: TextSelection(baseOffset: wordStart, extentOffset: wordEnd),
      );
      // Selection is non-collapsed, so production's own scroll-into-view
      // logic does not apply (see scrollSoOffsetIsVisible's doc comment) —
      // position the viewport explicitly so it starts away from the top,
      // which this test's premise requires.
      final scrollableForSetup = scrollableOf(tester);
      scrollSoOffsetIsVisible(ro, scrollableForSetup, wordStart);
      await tester.pump();
      // A scroll change's handle-overlay reposition is itself deferred one
      // extra frame (see quiki_editor.dart's _onScrollChangedForHandles doc
      // comment — Stage 2 Round 1) — a single pump() after this manual setup
      // scroll leaves find.byKey(_startHandleKey) still reporting its
      // PRE-scroll (here: unscrolled, off-viewport) position. Querying the
      // handle's center for the drag's start point before this settles would
      // start the gesture somewhere the handle isn't actually painted/hit-
      // testable, so nothing would grab it. One more zero-duration pump lets
      // that deferred reposition land before this test reads the handle's
      // position.
      await tester.pump();

      final viewportRect = tester.getRect(find.byKey(_viewportContainerKey));
      final topEdgeTouch = Offset(viewportRect.center.dx, viewportRect.top + 5);

      final handleStart = tester.getCenter(find.byKey(_startHandleKey));
      final gesture =
          await tester.startGesture(handleStart, kind: PointerDeviceKind.touch);
      await moveGestureInSteps(tester, gesture, handleStart, topEdgeTouch);

      final scrollable = scrollableOf(tester);
      final offsetAtDragStart = scrollable.position.pixels;
      expect(offsetAtDragStart, greaterThan(0),
          reason: 'test premise: the viewport must already be scrolled '
              'away from the top for this test to exercise anything');

      double? midTickOffset;
      for (var i = 0; i < 20; i++) {
        await tester.pump(_autoScrollInterval);
        if (i == 9) {
          midTickOffset = scrollable.position.pixels;
          final expected = independentSourceOffsetForGlobal(ro, topEdgeTouch);
          expect(controller.selectionForTesting.start, expected,
              reason: 'mid-drag (tick $i): the selection boundary must '
                  'already match the independently-recomputed offset for '
                  'the pointer at the CURRENT scroll position');
        }
      }

      await gesture.up();
      await tester.pump();

      final finalOffset = scrollable.position.pixels;
      expect(finalOffset, lessThan(offsetAtDragStart),
          reason: 'holding near the top edge must have scrolled the '
              'viewport upward');
      expect(midTickOffset, isNotNull);
      expect(midTickOffset, lessThan(offsetAtDragStart));
      expect(midTickOffset, greaterThan(finalOffset),
          reason: 'scroll offset must keep decreasing across further ticks '
              'while the pointer stays held in the edge zone');

      final sel = controller.selectionForTesting;
      expect(sel.end, wordEnd,
          reason: 'auto-scrolling the START handle must not move the end '
              'boundary');
      expect(sel.start, lessThan(wordStart),
          reason: 'the selection must have extended further back in the '
              'document than what was visible when the drag started');
    });
  });

  group('Auto-scroll — stops when the pointer leaves the edge zone', () {
    testWidgets(
        'auto-scroll stops as soon as the pointer moves back away from the '
        'edge zone, even though the drag is still active', (tester) async {
      final source = _buildLongSource();
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('line 1 ');
      final initialEnd = startOffset + 'line 1'.length;

      await pumpTallDocument(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      final viewportRect = tester.getRect(find.byKey(_viewportContainerKey));
      final bottomEdgeTouch =
          Offset(viewportRect.center.dx, viewportRect.bottom - 5);
      final middleTouch =
          Offset(viewportRect.center.dx, viewportRect.center.dy);

      final handleStart = tester.getCenter(find.byKey(_endHandleKey));
      final gesture =
          await tester.startGesture(handleStart, kind: PointerDeviceKind.touch);
      await moveGestureInSteps(tester, gesture, handleStart, bottomEdgeTouch);

      final scrollable = scrollableOf(tester);

      for (var i = 0; i < 10; i++) {
        await tester.pump(_autoScrollInterval);
      }
      final offsetWhileHeldAtEdge = scrollable.position.pixels;
      expect(offsetWhileHeldAtEdge, greaterThan(0),
          reason: 'test premise: auto-scroll must have started while held '
              'at the edge');

      // Move back toward the middle of the viewport — away from the edge
      // zone entirely.
      await moveGestureInSteps(tester, gesture, bottomEdgeTouch, middleTouch,
          steps: 3);
      final offsetImmediatelyAfterMovingAway = scrollable.position.pixels;

      for (var i = 0; i < 10; i++) {
        await tester.pump(_autoScrollInterval);
      }
      final offsetAfterFurtherWaiting = scrollable.position.pixels;

      expect(offsetAfterFurtherWaiting, offsetImmediatelyAfterMovingAway,
          reason: 'once the pointer is back away from the edge zone, '
              'further time passing must not scroll any further '
              '(afterMovingAway=$offsetImmediatelyAfterMovingAway, '
              'afterFurtherWaiting=$offsetAfterFurtherWaiting)');

      await gesture.up();
      await tester.pump();
    });
  });

  group('Auto-scroll — clamped to the actual document bounds', () {
    testWidgets(
        'auto-scroll never scrolls past the actual END of the document, '
        'even when held at the bottom edge far longer than needed to '
        'reach it', (tester) async {
      final source = _buildLongSource();
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('line 1 ');
      final initialEnd = startOffset + 'line 1'.length;

      await pumpTallDocument(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      final viewportRect = tester.getRect(find.byKey(_viewportContainerKey));
      final bottomEdgeTouch =
          Offset(viewportRect.center.dx, viewportRect.bottom - 5);

      final handleStart = tester.getCenter(find.byKey(_endHandleKey));
      final gesture =
          await tester.startGesture(handleStart, kind: PointerDeviceKind.touch);
      await moveGestureInSteps(tester, gesture, handleStart, bottomEdgeTouch);

      final scrollable = scrollableOf(tester);

      // Pump far more ticks than needed to reach the bottom of an 80-line
      // document at 16px/tick, so auto-scroll spends most of this loop
      // already clamped at the boundary.
      for (var i = 0; i < 150; i++) {
        await tester.pump(_autoScrollInterval);
      }

      final maxExtent = scrollable.position.maxScrollExtent;
      expect(scrollable.position.pixels, closeTo(maxExtent, 0.5),
          reason: 'auto-scroll must have reached (and stopped exactly at) '
              'the document\'s actual maxScrollExtent');

      // A few more ticks at the boundary must not push pixels past
      // maxScrollExtent or error.
      for (var i = 0; i < 5; i++) {
        await tester.pump(_autoScrollInterval);
        expect(scrollable.position.pixels, closeTo(maxExtent, 0.5),
            reason: 'must stay clamped at maxScrollExtent, never overshoot');
      }

      await gesture.up();
      await tester.pump();
    });

    testWidgets(
        'auto-scroll never scrolls past the actual START of the document, '
        'even when held at the top edge far longer than needed to reach '
        'it', (tester) async {
      final source = _buildLongSource();
      final controller = MarkdownEditorController();
      final lineStart = source.indexOf('line 60');
      final wordStart = source.indexOf('gamma', lineStart);
      final wordEnd = wordStart + 'gamma'.length;

      final ro = await pumpTallDocument(
        tester,
        source: source,
        controller: controller,
        selection: TextSelection(baseOffset: wordStart, extentOffset: wordEnd),
      );
      // See the identically-reasoned comment in the "extends selection"
      // group above: a non-collapsed selection does not auto-scroll into
      // view, so this test's "must start scrolled away from the top"
      // premise needs an explicit scroll.
      final scrollableForSetup = scrollableOf(tester);
      scrollSoOffsetIsVisible(ro, scrollableForSetup, wordStart);
      await tester.pump();
      // A scroll change's handle-overlay reposition is itself deferred one
      // extra frame (see quiki_editor.dart's _onScrollChangedForHandles doc
      // comment — Stage 2 Round 1) — a single pump() after this manual setup
      // scroll leaves find.byKey(_startHandleKey) still reporting its
      // PRE-scroll (here: unscrolled, off-viewport) position. Querying the
      // handle's center for the drag's start point before this settles would
      // start the gesture somewhere the handle isn't actually painted/hit-
      // testable, so nothing would grab it. One more zero-duration pump lets
      // that deferred reposition land before this test reads the handle's
      // position.
      await tester.pump();

      final viewportRect = tester.getRect(find.byKey(_viewportContainerKey));
      final topEdgeTouch = Offset(viewportRect.center.dx, viewportRect.top + 5);

      final handleStart = tester.getCenter(find.byKey(_startHandleKey));
      final gesture =
          await tester.startGesture(handleStart, kind: PointerDeviceKind.touch);
      await moveGestureInSteps(tester, gesture, handleStart, topEdgeTouch);

      final scrollable = scrollableOf(tester);
      expect(scrollable.position.pixels, greaterThan(0),
          reason: 'test premise: the viewport must start scrolled away '
              'from the top');

      for (var i = 0; i < 150; i++) {
        await tester.pump(_autoScrollInterval);
      }

      expect(scrollable.position.pixels, closeTo(0, 0.5),
          reason: 'auto-scroll must have reached (and stopped exactly at) '
              'the document\'s actual start (minScrollExtent)');

      for (var i = 0; i < 5; i++) {
        await tester.pump(_autoScrollInterval);
        expect(scrollable.position.pixels, closeTo(0, 0.5),
            reason: 'must stay clamped at 0, never go negative');
      }

      await gesture.up();
      await tester.pump();
    });
  });

  group('Auto-scroll — handle paint position stays live during the scroll', () {
    testWidgets(
        'the dragged handle\'s own rendered position stays visually '
        'accurate throughout continuous auto-scroll, checked mid-drag — '
        'not just once scrolling settles', (tester) async {
      final source = _buildLongSource();
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('line 1 ');
      final initialEnd = startOffset + 'line 1'.length;

      final ro = await pumpTallDocument(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      final viewportRect = tester.getRect(find.byKey(_viewportContainerKey));
      final bottomEdgeTouch =
          Offset(viewportRect.center.dx, viewportRect.bottom - 5);

      final handleStart = tester.getCenter(find.byKey(_endHandleKey));
      final gesture =
          await tester.startGesture(handleStart, kind: PointerDeviceKind.touch);
      await moveGestureInSteps(tester, gesture, handleStart, bottomEdgeTouch);

      for (var i = 0; i < 8; i++) {
        await tester.pump(_autoScrollInterval);
      }
      // One extra ZERO-DURATION pump (no time elapses, so the periodic
      // timer does not fire again): the selection boundary itself is
      // already exact the instant the previous pump() returns (proven by
      // the source-offset checks in the group above, which sample WITHOUT
      // this extra pump) — but the handle's own PAINTED position depends on
      // QuikiRenderEditor.localToGlobal, called from
      // _buildSelectionHandlesOverlay's build() method. A widget's build()
      // always runs BEFORE that same frame's layout phase, so it can only
      // ever reflect the PREVIOUS frame's completed layout — there is no
      // way for the very frame that first applies a given tick's scroll
      // offset to also paint a handle position derived from that same
      // offset; the earliest that is physically possible is the following
      // frame. This is the identical one-frame characteristic Stage 2 Round
      // 1 already documented and the project owner already accepted as
      // imperceptible during continuous scrolling (self-correcting every
      // frame, ~16ms) — this extra pump lets that one frame elapse before
      // sampling, so this check reflects what a real, continuously-
      // rendering 60fps display would actually show, not an instant that
      // is architecturally unreachable in Flutter's build/layout pipeline.
      await tester.pump();

      // Mid-sequence check, deliberately not after the hold loop below
      // settles: the handle's actual painted position must match an
      // independent getOffsetForCaret-based computation for whatever the
      // CURRENT selection end is — the same class of staleness Stage 2
      // Round 1 needed a real device to catch, now potentially recurring
      // every _autoScrollInterval instead of once per gesture.
      final currentEnd = controller.selectionForTesting.end;
      final actualCenter = tester.getCenter(find.byKey(_endHandleKey));
      final expectedCenter =
          independentHandleCenter(ro, sourceOffset: currentEnd, isStart: false);
      expect((actualCenter - expectedCenter).distance, lessThan(2.0),
          reason: 'handle position went stale mid-auto-scroll '
              '(actual=$actualCenter, expected=$expectedCenter, '
              'currentEnd=$currentEnd)');

      // Continue holding for more ticks and check again at a later point,
      // proving this holds throughout, not just at this one sampled tick.
      for (var i = 0; i < 8; i++) {
        await tester.pump(_autoScrollInterval);
      }
      await tester.pump();
      final laterEnd = controller.selectionForTesting.end;
      final laterActualCenter = tester.getCenter(find.byKey(_endHandleKey));
      final laterExpectedCenter =
          independentHandleCenter(ro, sourceOffset: laterEnd, isStart: false);
      expect((laterActualCenter - laterExpectedCenter).distance, lessThan(2.0),
          reason: 'handle position went stale at a later auto-scroll tick '
              '(actual=$laterActualCenter, expected=$laterExpectedCenter, '
              'laterEnd=$laterEnd)');
      expect(laterEnd, greaterThan(currentEnd),
          reason: 'the selection must have kept extending between the two '
              'sampled ticks, proving scrolling was still continuing, not '
              'settled, at the first check');

      await gesture.up();
      await tester.pump();
    });
  });
}
