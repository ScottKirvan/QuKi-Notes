// Tests for Stage 2 draggable selection handles (feat/selection-stage2,
// notes/dev/selection.md §2, ADR-36).
//
// Every drag here is a REAL simulated gesture on the actual handle widget
// (tester.startGesture / moveTo / up), matching the discipline established
// by selection_test.dart's Stage 1 suite — the bug that discipline exists to
// catch (partial-word selection shipping despite tests that only ever set
// selection programmatically) is exactly the class of bug a handle-drag
// feature could reintroduce if these tests instead called a private method
// directly.
//
// The STARTING selection in each test is established via
// controller.setSelectionForTesting rather than a real long-press/double-tap
// gesture. That's deliberate, not a shortcut around the "real gesture"
// requirement: what Stage 2 adds is the DRAG, not the initial selection —
// Stage 1's suite already covers long-press/double-tap gesture correctness
// in depth. Going through a real long-press here would also open the
// floating toolbar (_showSelectionToolbar), which is unrelated to what this
// file tests and floats near the same screen region as a handle; keeping
// selection setup programmatic avoids that overlap being a source of test
// flakiness that has nothing to do with handle-drag correctness.
//
// _isMobile (handle visibility is gated on it, same as the toolbar) is
// forced true via QuikiEditorState.debugForceMobile — the real gate
// production code checks, not a bypass that skips the gating logic itself.

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

Widget buildEditor({
  required String initialValue,
  MarkdownEditorController? controller,
}) {
  return MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: MarkdownEditor(
        initialValue: initialValue,
        controller: controller,
      ),
    ),
  );
}

QuikiRenderEditor renderEditorOf(WidgetTester tester) =>
    tester.renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));

/// The global screen position of source offset [sourceOffset], nudged 2px
/// down from the caret's row-top so a resolved tap/drag lands within a
/// glyph's vertical extent rather than exactly on the row's top edge —
/// mirrors selection_test.dart's identically-named helper.
Offset globalPositionForSourceOffset(
  WidgetTester tester,
  QuikiRenderEditor ro,
  int sourceOffset,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: sourceOffset));
  final local = Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + local;
}

/// Independently computes where a handle's visible glyph — and therefore its
/// touch target — SHOULD be centered on screen for [sourceOffset], for the
/// start handle ([isStart] true) or end handle (false). This reimplements
/// the anchor geometry from scratch in the TEST rather than calling
/// QuikiEditorState's private _buildSelectionHandlesOverlay, so it can serve
/// as an INDEPENDENT check on the actual rendered handle
/// (tester.getCenter/tester.getRect) rather than trusting the handle
/// widget's own self-reported position — see the file doc comment on
/// dragHandleTo's circularity.
///
/// Written to catch a real, confirmed bug: a handle overlay rebuild driven
/// directly off ScrollPosition notifications reads QuikiRenderEditor's paint
/// transform BEFORE the frame's layout phase applies a just-changed scroll
/// offset (ScrollPosition.notifyListeners fires synchronously the moment
/// `.pixels` changes, which is before that frame's layout runs) — so the
/// computed handle position was permanently one scroll-tick stale after any
/// scroll, with nothing to later self-correct it. This helper calls
/// getOffsetForCaret / localToGlobal directly from the test, after whatever
/// pumping the test has already done, so it always reflects the CURRENT,
/// already-laid-out render tree — it cannot share that staleness even when
/// production code does.
Offset independentHandleCenter(
  QuikiRenderEditor ro, {
  required int sourceOffset,
  required bool isStart,
}) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: sourceOffset)) +
      ro.localPadding.topLeft;
  final anchorLocal = Offset(caret.dx, caret.dy + ro.preferredLineHeight);
  final anchorGlobal = ro.localToGlobal(anchorLocal);
  // Mirrors QuikiEditorState's handle geometry constants exactly
  // (_handleDiameter=20, _handleHitBoxSize=44, _handleInset=12): the
  // "point" corner where the anchor lands sits at (inset+diameter, inset)
  // within the hit box's own local space for the start handle, or
  // (inset, inset) for the end handle; the hit box's own center is always
  // 22px from its own top-left on both axes.
  const inset = 12.0;
  const diameter = 20.0;
  const hitBoxCenter = Offset(22.0, 22.0);
  final pointLocal = isStart
      ? const Offset(inset + diameter, inset)
      : const Offset(inset, inset);
  final topLeft = anchorGlobal - pointLocal;
  return topLeft + hitBoxCenter;
}

/// Drags the handle found by [handleFinder] from its current center to
/// [targetGlobal] via several intermediate move events (see
/// selection_test.dart's performDrag for why: a single large jump does not
/// reliably drive a PanGestureRecognizer's start/update chain in this test
/// harness).
Future<void> dragHandleTo(
  WidgetTester tester,
  Finder handleFinder,
  Offset targetGlobal, {
  int steps = 5,
}) async {
  final start = tester.getCenter(handleFinder);
  final gesture =
      await tester.startGesture(start, kind: PointerDeviceKind.touch);
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(Offset.lerp(start, targetGlobal, i / steps)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// Pumps a widget with handles forced visible ([QuikiEditorState.debugForceMobile])
/// and an initial selection set programmatically (see file doc comment for
/// why setup is programmatic while the drag itself is a real gesture).
Future<QuikiRenderEditor> pumpWithSelection(
  WidgetTester tester, {
  required String source,
  required MarkdownEditorController controller,
  required TextSelection selection,
}) async {
  QuikiEditorState.debugForceMobile = true;
  await tester
      .pumpWidget(buildEditor(initialValue: source, controller: controller));
  await tester.pump();
  controller.setSelectionForTesting(selection);
  await tester.pump();
  return renderEditorOf(tester);
}

void main() {
  tearDown(() {
    QuikiEditorState.debugForceMobile = false;
  });

  group('Selection handles — presence', () {
    testWidgets(
        'both handles appear the moment a non-collapsed selection exists, '
        'and neither appears for a collapsed selection', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection: TextSelection(
          baseOffset: source.indexOf('beta'),
          extentOffset: source.indexOf('beta') + 'beta'.length,
        ),
      );

      expect(find.byKey(_startHandleKey), findsOneWidget);
      expect(find.byKey(_endHandleKey), findsOneWidget);

      // Collapse the selection programmatically and confirm both disappear.
      controller.setSelectionForTesting(
        TextSelection.collapsed(offset: source.indexOf('beta')),
      );
      await tester.pump();

      expect(find.byKey(_startHandleKey), findsNothing);
      expect(find.byKey(_endHandleKey), findsNothing);
    });
  });

  group('Selection handles — independent drag, non-crossing', () {
    testWidgets(
        'dragging the END handle further into the document extends the '
        'selection end; the start boundary is untouched', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('beta');
      final initialEnd = startOffset + 'beta'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      final targetOffset = source.indexOf('gamma') + 'gamma'.length;
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOffset);
      await dragHandleTo(tester, find.byKey(_endHandleKey), targetGlobal);

      final sel = controller.selectionForTesting;
      expect(sel.start, startOffset,
          reason: 'dragging the end handle must not move the start boundary');
      expect(sel.end, targetOffset);
      expect(sel.textInside(source), 'beta gamma');
    });

    testWidgets(
        'dragging the START handle further back in the document extends the '
        'selection start; the end boundary is untouched', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      final initialStart = source.indexOf('gamma');
      final endOffset = initialStart + 'gamma'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: initialStart, extentOffset: endOffset),
      );

      final targetOffset = source.indexOf('alpha');
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOffset);
      await dragHandleTo(tester, find.byKey(_startHandleKey), targetGlobal);

      final sel = controller.selectionForTesting;
      expect(sel.end, endOffset,
          reason: 'dragging the start handle must not move the end boundary');
      expect(sel.start, targetOffset);
      expect(sel.textInside(source), 'alpha beta gamma');
    });

    testWidgets('handle drag precision is character-level, not word-snapped',
        (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('beta');
      final initialEnd = startOffset + 'beta'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      // Land mid-word inside "gamma" (not at a word boundary) — a
      // word-snapping implementation would round this to the whole word or
      // to gamma's own boundary; character-level precision must not.
      final targetOffset = source.indexOf('gamma') + 2;
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOffset);
      await dragHandleTo(tester, find.byKey(_endHandleKey), targetGlobal);

      expect(controller.selectionForTesting.end, targetOffset);
    });
  });

  group('Selection handles — crossing', () {
    testWidgets(
        'dragging the END handle backward past the current start flips '
        'logical start/end — selection still spans the two handle positions',
        (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      final initialStart = source.indexOf('gamma');
      final initialEnd = initialStart + 'gamma'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: initialStart, extentOffset: initialEnd),
      );

      // Drag the END handle backward past the original START, into "alpha".
      final targetOffset = source.indexOf('alpha');
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOffset);
      await dragHandleTo(tester, find.byKey(_endHandleKey), targetGlobal);

      final sel = controller.selectionForTesting;
      expect(sel.isCollapsed, isFalse);
      // The dragged position (now the smaller offset) becomes the logical
      // start; the untouched original start becomes the logical end. The
      // untouched boundary is the original START of "gamma" (the position
      // immediately before its 'g'), so "gamma" itself is excluded — that
      // boundary was never touched by this drag, only its own opposite side
      // (originally the end, at initialStart + 'gamma'.length) was.
      expect(sel.start, targetOffset,
          reason: 'crossing must flip which boundary is logically "start" — '
              'not clamp the drag at the original start');
      expect(sel.end, initialStart);
      expect(sel.textInside(source), 'alpha beta ');
    });

    testWidgets(
        'dragging the START handle forward past the current end flips '
        'logical start/end — the reverse crossing case', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      final initialStart = source.indexOf('beta');
      final initialEnd = initialStart + 'beta'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: initialStart, extentOffset: initialEnd),
      );

      // Drag the START handle forward past the original END, into "delta".
      final targetOffset = source.indexOf('delta') + 'delta'.length;
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOffset);
      await dragHandleTo(tester, find.byKey(_startHandleKey), targetGlobal);

      final sel = controller.selectionForTesting;
      expect(sel.isCollapsed, isFalse);
      expect(sel.start, initialEnd,
          reason: 'the untouched original end must become the new logical '
              'start after the reverse crossing');
      expect(sel.end, targetOffset,
          reason: 'crossing must flip which boundary is logically "end" — '
              'not clamp or refuse the drag');
      // The untouched boundary is the original END of "beta" (the position
      // immediately after its 'a'), so "beta" itself is excluded — the
      // space right after it is included instead.
      expect(sel.textInside(source), ' gamma delta');
    });
  });

  group('Selection handles — multi-line', () {
    testWidgets(
        'dragging a handle down across a line boundary extends the '
        'selection into the next line', (tester) async {
      const source = 'alpha beta gamma\ndelta epsilon zeta';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('beta');
      final initialEnd = startOffset + 'beta'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      final targetOffset = source.indexOf('epsilon') + 'epsilon'.length;
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOffset);
      await dragHandleTo(tester, find.byKey(_endHandleKey), targetGlobal);

      final sel = controller.selectionForTesting;
      expect(sel.start, startOffset);
      expect(sel.end, targetOffset);
      expect(sel.textInside(source), 'beta gamma\ndelta epsilon');
    });
  });

  group('Selection handles — delimiter-boundary precision', () {
    testWidgets(
        'a handle drag landing exactly at the source-offset boundary '
        'between visible content and a hidden closing delimiter resolves '
        'to a valid, in-range source offset rather than erroring or '
        'landing inside the delimiter run', (tester) async {
      const source = 'see **bold** word here';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('see');
      final initialEnd = startOffset + 'see'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      // The target SOURCE offset requested is one past "bold"'s last content
      // character — i.e. the boundary right at the start of the hidden
      // closing '**'. getOffsetForCaret maps that source offset to a screen
      // position; because the '**' delimiter is entirely collapsed (zero
      // rendered width), every source offset within it maps to the SAME
      // screen position as the boundary itself. Resolving that screen
      // position back to a source offset (positionForOffset — the same
      // shared coordinate-mapping path every other gesture in this class
      // already uses) is therefore inherently ambiguous at this exact pixel,
      // and lands one whole hidden-delimiter-width further than requested
      // (past BOTH closing '*' characters, at the space after them) rather
      // than at the requested boundary itself — see
      // _renderedRangeToSourceSelection's doc comment in quiki_editor.dart
      // for the same ambiguity Stage 1 had to explicitly work around for
      // _selectEntityAt's regex-driven whole-word/whole-link boundaries.
      // Stage 2 deliberately reuses positionForOffset as-is (no new
      // coordinate math per the brief), so this is pre-existing,
      // already-established tap-to-cursor behaviour, not a Stage 2
      // regression — what matters here is that the result is a valid,
      // in-range, non-crashing mapping, which it is.
      final requestedOffset = source.indexOf('bold') + 'bold'.length;
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, requestedOffset);
      await dragHandleTo(tester, find.byKey(_endHandleKey), targetGlobal);

      final sel = controller.selectionForTesting;
      expect(sel.start, startOffset);
      expect(sel.end, requestedOffset + '**'.length,
          reason: 'lands one hidden-delimiter-width past the requested '
              'boundary (at the space after the closing **), not inside the '
              'delimiter and not at some unrelated/out-of-range offset');
      expect(sel.textInside(source), 'see **bold**');
    });

    testWidgets(
        'a handle drag landing on a rendered link label maps back through '
        'the link source range without error', (tester) async {
      const source = 'see [click here](https://example.com) now';
      final controller = MarkdownEditorController();
      final startOffset = source.indexOf('see');
      final initialEnd = startOffset + 'see'.length;
      final ro = await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection:
            TextSelection(baseOffset: startOffset, extentOffset: initialEnd),
      );

      // Land on "here", the second word of the link label — a rendered
      // position with no source-text equivalent nearby except through the
      // link's own offset-map entries.
      final targetOffset = source.indexOf('here', source.indexOf('click'));
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOffset);
      await dragHandleTo(tester, find.byKey(_endHandleKey), targetGlobal);

      final sel = controller.selectionForTesting;
      expect(sel.start, startOffset);
      // No crash, and the resulting end lands within the link's source
      // span (between the label's start and the URL's closing paren) —
      // proof the drag resolved through the link's rendered<->source
      // mapping rather than producing a garbage offset.
      expect(sel.end, greaterThanOrEqualTo(source.indexOf('click here')));
      expect(sel.end, lessThanOrEqualTo(source.indexOf(')') + 1));
    });
  });

  group('Selection handles — dismissal', () {
    testWidgets(
        'a fresh tap elsewhere dismisses both handles along with the '
        'selection, the same way it already dismisses the toolbar today',
        (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      await pumpWithSelection(
        tester,
        source: source,
        controller: controller,
        selection: TextSelection(
          baseOffset: source.indexOf('beta'),
          extentOffset: source.indexOf('beta') + 'beta'.length,
        ),
      );

      expect(find.byKey(_startHandleKey), findsOneWidget);
      expect(find.byKey(_endHandleKey), findsOneWidget);

      final ro = renderEditorOf(tester);
      final tapPos = globalPositionForSourceOffset(
          tester, ro, source.indexOf('delta') + 2);
      await tester.tapAt(tapPos);
      // Drain DoubleTapGestureRecognizer's internal timer — any pointer
      // down through the main editor's GestureDetector schedules it, tap or
      // not (see selection_test.dart's doubleTapAt for the full mechanism).
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.selectionForTesting.isCollapsed, isTrue);
      expect(find.byKey(_startHandleKey), findsNothing);
      expect(find.byKey(_endHandleKey), findsNothing);
    });
  });

  group('Selection handles — position accuracy after scrolling (regression)',
      () {
    // Real, confirmed device bug: after scrolling, a handle looked roughly
    // right (visible in the general area) but dragging it did not grab it —
    // the touch fell through to the underlying scrollable content instead.
    // Root cause: the handle overlay was rebuilt directly off
    // ScrollPosition's notification, which fires synchronously the instant
    // `.pixels` changes — before that frame's layout phase applies the new
    // scroll offset to QuikiRenderEditor's paint transform. So the position
    // computed in that rebuild (via getOffsetForCaret + localToGlobal) was
    // always one scroll-tick stale, and — because nothing else triggers a
    // further handle-overlay rebuild once scrolling stops — the staleness
    // never self-corrected. Both tests below scroll and then pump only a
    // couple of plain frames (deliberately NOT pumpAndSettle, which would
    // let an unrelated later rebuild paper over the bug) to catch exactly
    // that just-scrolled state.
    //
    // Long document + constrained viewport height so the target text
    // requires an actual scroll to reach — the single-screen tests above
    // never move the ScrollPosition at all, so they could not have caught
    // this class of bug regardless of how the drag's start position was
    // computed.
    String buildLongSource() =>
        List.generate(60, (i) => 'line $i alpha beta gamma delta').join('\n');

    Future<QuikiRenderEditor> pumpScrolledSelection(
      WidgetTester tester, {
      required String source,
      required MarkdownEditorController controller,
      required TextSelection selection,
    }) async {
      QuikiEditorState.debugForceMobile = true;
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: MarkdownEditor(initialValue: source, controller: controller),
          ),
        ),
      ));
      await tester.pump();
      controller.setSelectionForTesting(selection);
      await tester.pump();

      // Scroll by an amount CALIBRATED from the selection's own measured
      // position (not a guessed constant) so the target line lands roughly
      // 100px below the viewport's top edge — comfortably on-screen — rather
      // than risking an over-large drag that clamps at maxScrollExtent and
      // scrolls straight past the target, off the top of the viewport
      // entirely (which would make the handle genuinely, correctly absent —
      // a test-construction mistake, not the staleness bug this group is
      // written to catch).
      final roBeforeScroll = renderEditorOf(tester);
      final targetLocalY = roBeforeScroll
              .getOffsetForCaret(TextPosition(offset: selection.start))
              .dy +
          roBeforeScroll.localPadding.top;
      final dragDistance = (targetLocalY - 100).clamp(0.0, double.infinity);

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, Offset(0, -dragDistance));
      await tester.pump();
      await tester.pump();

      return renderEditorOf(tester);
    }

    testWidgets(
        'a handle rendered right after the editor scrolls sits at the '
        'position independently computed via getOffsetForCaret, not stale '
        'from before the scroll', (tester) async {
      final source = buildLongSource();
      final controller = MarkdownEditorController();
      final lineStart = source.indexOf('line 40');
      final betaStart = source.indexOf('beta', lineStart);
      final betaEnd = betaStart + 'beta'.length;

      final ro = await pumpScrolledSelection(
        tester,
        source: source,
        controller: controller,
        selection: TextSelection(baseOffset: betaStart, extentOffset: betaEnd),
      );

      expect(find.byKey(_startHandleKey), findsOneWidget,
          reason: 'the selection must have scrolled into view for this test '
              'to exercise anything');

      final expectedCenter =
          independentHandleCenter(ro, sourceOffset: betaStart, isStart: true);
      final actualCenter = tester.getCenter(find.byKey(_startHandleKey));

      expect((actualCenter - expectedCenter).distance, lessThan(2.0),
          reason: 'the rendered handle must sit at the position '
              'getOffsetForCaret independently says it should — a mismatch '
              'here means the handle is stuck at a stale pre-scroll '
              'position (actual=$actualCenter, expected=$expectedCenter)');

      // Drain DoubleTapGestureRecognizer's internal timer — the scroll drag
      // above is a real pointer down/up sequence through the main editor's
      // (ancestor) GestureDetector, which arms it regardless of whether the
      // gesture turns out to be a tap (see selection_test.dart's
      // doubleTapAt for the full mechanism).
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
        'dragging from the independently-computed touch position — not the '
        'handle widget\'s own reported center — still grabs and moves the '
        'handle after scrolling', (tester) async {
      final source = buildLongSource();
      final controller = MarkdownEditorController();
      final lineStart = source.indexOf('line 40');
      final betaStart = source.indexOf('beta', lineStart);
      final betaEnd = betaStart + 'beta'.length;

      final ro = await pumpScrolledSelection(
        tester,
        source: source,
        controller: controller,
        selection: TextSelection(baseOffset: betaStart, extentOffset: betaEnd),
      );

      expect(find.byKey(_startHandleKey), findsOneWidget);

      // Deliberately NOT tester.getCenter(handleFinder) — that would be
      // exactly the circularity this test exists to avoid (see the file doc
      // comment and independentHandleCenter's doc comment). This is the
      // screen position a real finger aiming at the handle would land on,
      // computed independently of what the handle widget itself reports.
      final startTouchPos =
          independentHandleCenter(ro, sourceOffset: betaStart, isStart: true);

      final targetOffset = source.indexOf('alpha', lineStart);
      final targetGlobal =
          globalPositionForSourceOffset(tester, ro, targetOffset);

      final gesture = await tester.startGesture(startTouchPos,
          kind: PointerDeviceKind.touch);
      for (var i = 1; i <= 5; i++) {
        await gesture.moveTo(Offset.lerp(startTouchPos, targetGlobal, i / 5)!);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      final sel = controller.selectionForTesting;
      expect(sel.end, betaEnd,
          reason: 'dragging the start handle must not move the end boundary');
      expect(sel.start, targetOffset,
          reason: 'a drag starting from the real, independently-computed '
              'touch position must grab the handle and move the selection '
              'start — if this fails while the handle is visually present, '
              'the touch fell through to the underlying content instead of '
              'the handle (the exact bug this regression test guards '
              'against)');

      // Drain DoubleTapGestureRecognizer's internal timer (see the previous
      // test's identical comment).
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
