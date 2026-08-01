// Tests for entity-aware long-press / double-tap selection
// (feat/selection-stage1).
//
// Every test here drives a REAL simulated gesture (tester.longPressAt /
// two tester.tapAt calls close together for double-tap / tester.startGesture
// for drag) and asserts the resulting TextSelection — not a programmatic
// controller.setSelectionForTesting() call. That distinction matters: the
// bug this file guards against (partial-word selection) shipped despite
// existing selection tests precisely because every one of them set the
// selection programmatically rather than exercising the actual tap
// coordinate → rendered offset → source offset path. See
// notes/dev/testing.md's bug-fix protocol and QuikiEditorState's
// _selectEntityAt doc comment (quiki_editor.dart) for the root-cause
// analysis this suite is written against.
//
// Root cause, in brief: the old _selectWordAt/_isWordChar scanned the raw
// SOURCE text (which still contains hidden markdown delimiters, e.g. the
// '**' in '**bold**' or a mid-word nested run like 're**a**lly'). '*' is
// correctly not a word character, so the scan stopped at the first hidden
// delimiter and returned only a fragment of the word — even though the
// delimiter is invisible on screen. The fix scans the RENDERED text (what's
// actually on screen) and maps the result back to source offsets via
// RenderModel's existing bidirectional offset maps.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// A fresh Key per call forces a real unmount + remount rather than an
// in-place widget update — see notes/dev/testing.md's pumpWidget-reuse
// gotcha (surfaced during ADR-34 follow-up work). Each test here only pumps
// once, but the UniqueKey is kept for consistency with the rest of the
// suite and to avoid ever accidentally reusing stale render state if a test
// is later extended to compare two documents.
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
/// down from the caret's row-top so the tap lands within a glyph's vertical
/// extent rather than exactly on the row's top edge (mirrors the pattern
/// already established in block_indentation_test.dart's hit-testing group).
Offset globalPositionForSourceOffset(
  WidgetTester tester,
  QuikiRenderEditor ro,
  int sourceOffset,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: sourceOffset));
  final local = Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + local;
}

/// Simulates a real double-tap: two separate tap gestures at the same
/// location, close enough in time to fall inside Flutter's double-tap
/// window (kDoubleTapTimeout, 300ms by default) but as two genuinely
/// separate pointer down/up sequences — matching how two real taps arrive.
///
/// The trailing pump is deliberately longer than kDoubleTapTimeout: as soon
/// as a GestureDetector has any onDoubleTap* callback wired up, EVERY
/// pointer down through it — even ones that turn out not to be a second tap
/// — makes DoubleTapGestureRecognizer schedule an internal
/// "forget the last tap" timer. That timer is real (backed by the test
/// binding's fake clock) and must be allowed to fire before the test ends,
/// or flutter_test's own teardown assertion ('A Timer is still pending
/// even after the widget tree was disposed') fails — a pure test-harness
/// bookkeeping requirement, unrelated to the app's own correctness. A plain
/// tester.longPressAt already drains this incidentally (it internally
/// pumps for kLongPressTimeout, which is already longer than
/// kDoubleTapTimeout); a quick tap/double-tap does not, so it must be done
/// explicitly here.
Future<void> doubleTapAt(WidgetTester tester, Offset location) async {
  await tester.tapAt(location);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(location);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Performs a drag gesture from [start] to [end] via several intermediate
/// move events with a pump after each, rather than one large jump.
///
/// A single large TestGesture.moveTo jump from down straight to the target
/// does not reliably drive PanGestureRecognizer's onPanStart/onPanUpdate
/// chain in this test harness (confirmed empirically while writing this
/// suite — it can leave the drag never recognized as a pan at all). Several
/// smaller moves does. This also better matches how a real drag actually
/// arrives — many intermediate pointer-move events, not one.
///
/// The trailing >=kDoubleTapTimeout pump is the same DoubleTapGestureRecognizer
/// timer-drain requirement documented on [doubleTapAt].
Future<void> performDrag(
  WidgetTester tester,
  Offset start,
  Offset end, {
  required PointerDeviceKind kind,
  int steps = 5,
}) async {
  final gesture = await tester.startGesture(start, kind: kind);
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / steps)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // -------------------------------------------------------------------------
  // Long-press: entity-aware word/link/email/numeric selection.
  // -------------------------------------------------------------------------

  group('Long-press selection — entity-aware', () {
    testWidgets('plain word in a plain paragraph', (tester) async {
      const source = 'hello world';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final wordStart = source.indexOf('world');
      final tapOffset = wordStart + 2; // land inside "world", not at an edge
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, tapOffset));
      await tester.pump();

      final sel = controller.selectionForTesting;
      expect(sel.start, wordStart);
      expect(sel.end, wordStart + 'world'.length);
      expect(sel.textInside(source), 'world');
    });

    testWidgets(
        'REGRESSION (root cause): a word split mid-word by hidden inline '
        'markup selects the whole visual word, including the markup — not '
        'just the fragment before or after the hidden delimiter',
        (tester) async {
      // "word" rendered, with the 'r' individually bolded — source is
      // 'wo**r**d', i.e. the hidden '**' delimiters sit BETWEEN visible
      // characters of what reads as one continuous word on screen. The old
      // source-text \w scan stopped dead at the first '*' it hit.
      const source = 'see wo**r**d here';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      // Tap on the bolded 'r' itself — the character directly adjacent to
      // hidden delimiters on both sides, the most aggressive case.
      final rOffset = source.indexOf('r', source.indexOf('wo'));
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, rOffset));
      await tester.pump();

      final sel = controller.selectionForTesting;
      final expectedStart = source.indexOf('wo**r**d');
      final expectedEnd = expectedStart + 'wo**r**d'.length;
      expect(sel.start, expectedStart,
          reason: 'selection must start at the "w", not after the hidden '
              'delimiter fragment');
      expect(sel.end, expectedEnd,
          reason: 'selection must extend through the whole word including '
              'its internal hidden delimiters, not stop at "wo" or "r"');
      expect(sel.textInside(source), 'wo**r**d');
    });

    testWidgets(
        'word wholly surrounded by (not split by) bold delimiters selects '
        'only the content, excluding the delimiters', (tester) async {
      const source = 'a **bold** word here';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final boldOffset = source.indexOf('bold') + 1; // inside "bold"
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, boldOffset));
      await tester.pump();

      final sel = controller.selectionForTesting;
      expect(sel.textInside(source), 'bold',
          reason: 'must select exactly the content word, never the '
              'surrounding ** delimiters');
    });

    testWidgets('word adjacent to italic delimiters selects only the content',
        (tester) async {
      const source = 'this is _italic_ text';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.indexOf('italic') + 2;
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), 'italic');
    });

    testWidgets(
        'word adjacent to strikethrough delimiters selects only the content',
        (tester) async {
      const source = 'oops ~~gone~~ now';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.indexOf('gone') + 1;
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), 'gone');
    });

    testWidgets(
        'word adjacent to inline code delimiters selects only the content',
        (tester) async {
      const source = 'run `build` now';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.indexOf('build') + 2;
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), 'build');
    });

    testWidgets('word inside a rendered link selects the whole link label',
        (tester) async {
      const source = 'see [click here](https://example.com) now';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      // Tap inside "here", the second word of the link label — must select
      // the FULL label "click here", not just "here".
      final offset = source.indexOf('here', source.indexOf('click'));
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), 'click here');
    });

    testWidgets('bare autolinked URL selects the whole URL', (tester) async {
      const source = 'go to https://example.com/path/here now';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      const url = 'https://example.com/path/here';
      final offset = source.indexOf('example');
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), url);
    });

    testWidgets('email address selects the whole address', (tester) async {
      const source = 'contact me at jane.doe@example.co.uk today';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      const email = 'jane.doe@example.co.uk';
      final offset = source.indexOf('example'); // land after the '@'
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), email);
    });

    testWidgets(
        'punctuated numeric string (phone-number-like) selects the whole '
        'digit-and-punctuation run', (tester) async {
      const source = 'call 555-1234 tomorrow';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      const number = '555-1234';
      final offset = source.indexOf('1234'); // land in the second group
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), number);
    });

    testWidgets(
        'BOUNDARY CASE: letter-suffixed identifier — the numeric-entity '
        'matcher is deliberately digits-plus-punctuation only, so a serial '
        'number ending in a letter selects only its numeric core, not the '
        'letter prefix/suffix (see _numericEntityPattern doc for the '
        'reasoning)', (tester) async {
      const source = 'part id SN-2024-0847-B end';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.indexOf('2024');
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      // Selects the digit-and-punctuation run only: '2024-0847'. The
      // leading 'SN-' and trailing '-B' are NOT included — this is the
      // deliberately chosen, narrower boundary (digits-plus-punctuation
      // only, no letters), not an oversight.
      expect(controller.selectionForTesting.textInside(source), '2024-0847');
    });

    testWidgets('word at the very start of the document', (tester) async {
      const source = 'first word here';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      await tester.longPressAt(globalPositionForSourceOffset(tester, ro, 1));
      await tester.pump();

      final sel = controller.selectionForTesting;
      expect(sel.start, 0);
      expect(sel.end, 'first'.length);
      expect(sel.textInside(source), 'first');
    });

    testWidgets('word at the very end of the document', (tester) async {
      const source = 'here is last';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.length - 2; // inside "last"
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      final sel = controller.selectionForTesting;
      expect(sel.start, source.indexOf('last'));
      expect(sel.end, source.length);
      expect(sel.textInside(source), 'last');
    });

    testWidgets(
        'word immediately after a checkbox marker selects only the word, '
        'never bleeding into the marker', (tester) async {
      const source = '- [ ] task today';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.indexOf('task') + 1;
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), 'task');
    });

    testWidgets(
        'word immediately after a bullet list marker selects only the word',
        (tester) async {
      const source = '- item here';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.indexOf('item') + 1;
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro, offset));
      await tester.pump();

      expect(controller.selectionForTesting.textInside(source), 'item');
    });
  });

  // -------------------------------------------------------------------------
  // Double-tap: must be a fully equivalent entry point to long-press.
  // -------------------------------------------------------------------------

  group('Double-tap selection — equivalent to long-press', () {
    testWidgets('plain word — double-tap selects the whole word',
        (tester) async {
      const source = 'hello world';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.indexOf('world') + 2;
      await doubleTapAt(
          tester, globalPositionForSourceOffset(tester, ro, offset));

      expect(controller.selectionForTesting.textInside(source), 'world');
    });

    testWidgets(
        'word split mid-word by hidden inline markup — double-tap selects '
        'the whole visual word, same as long-press', (tester) async {
      const source = 'see wo**r**d here';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final rOffset = source.indexOf('r', source.indexOf('wo'));
      await doubleTapAt(
          tester, globalPositionForSourceOffset(tester, ro, rOffset));

      expect(controller.selectionForTesting.textInside(source), 'wo**r**d');
    });

    testWidgets(
        'word inside a rendered link — double-tap selects the whole '
        'link label', (tester) async {
      const source = 'see [click here](https://example.com) now';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final offset = source.indexOf('here', source.indexOf('click'));
      await doubleTapAt(
          tester, globalPositionForSourceOffset(tester, ro, offset));

      expect(controller.selectionForTesting.textInside(source), 'click here');
    });

    testWidgets(
        'long-press and double-tap resolve to IDENTICAL selections for the '
        'same content and tap position — proves they share one underlying '
        'determination rather than two implementations that could drift '
        'apart', (tester) async {
      const source = 'reach out at jane.doe@example.co.uk soon';
      final offset = source.indexOf('example');

      final longPressController = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: longPressController,
      ));
      await tester.pump();
      final ro1 = renderEditorOf(tester);
      await tester
          .longPressAt(globalPositionForSourceOffset(tester, ro1, offset));
      await tester.pump();
      final longPressSel = longPressController.selectionForTesting;

      // Fresh remount for the double-tap half of the comparison — same
      // reasoning as testing.md's pumpWidget-reuse gotcha: a second
      // pumpWidget without a distinguishing key on a structurally-identical
      // tree would silently keep rendering the first document. buildEditor
      // always stamps a UniqueKey, so this remounts for real.
      final doubleTapController = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: doubleTapController,
      ));
      await tester.pump();
      final ro2 = renderEditorOf(tester);
      await doubleTapAt(
          tester, globalPositionForSourceOffset(tester, ro2, offset));
      final doubleTapSel = doubleTapController.selectionForTesting;

      expect(doubleTapSel.start, longPressSel.start);
      expect(doubleTapSel.end, longPressSel.end);
      expect(doubleTapSel.textInside(source), 'jane.doe@example.co.uk');
    });
  });

  // -------------------------------------------------------------------------
  // Recognizer hardening — explicit pan anchor + pointer-kind dispatch.
  // -------------------------------------------------------------------------

  group('Drag-to-select recognizer hardening', () {
    // Note on gesture-arena timing: TapGestureRecognizer only wins the arena
    // (and fires onTapDown) once every competing recognizer — LongPress,
    // Pan, DoubleTap, all registered on the same GestureDetector — has
    // conceded. For a real drag (down, then movement well past the pan
    // slop, then up), PanGestureRecognizer claims the arena as soon as that
    // movement is seen, so TapGestureRecognizer loses and onTapDown never
    // fires at all — confirmed empirically while writing this suite. That
    // means these tests deliberately do NOT assert anything about
    // _onTapDown's collapsed-cursor side effect during a drag (unlike the
    // long-press/double-tap groups above, which are quick, stationary
    // gestures onTapDown does win for) — they assert only on what
    // _onPanStart/_onPanUpdate/_onPanEnd themselves are responsible for.
    //
    // Every test also ends with a >=kDoubleTapTimeout pump for the same
    // "drain DoubleTapGestureRecognizer's internal timer" reason documented
    // on doubleTapAt above — any pointer down through this GestureDetector
    // schedules it, drag or not.

    testWidgets(
        'mouse drag: selection extends from the drag start to the drag end '
        'via the explicitly-captured pan anchor', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final startPos = globalPositionForSourceOffset(tester, ro, 0);
      final endPos = globalPositionForSourceOffset(tester, ro, source.length);
      await performDrag(tester, startPos, endPos,
          kind: PointerDeviceKind.mouse);

      final sel = controller.selectionForTesting;
      expect(sel.isCollapsed, isFalse,
          reason: 'a mouse drag across the whole document must produce a '
              'non-collapsed selection');
      // The anchor is captured once PanGestureRecognizer's slop threshold is
      // first exceeded, not at the exact original down position (see
      // _onPanStart's doc comment in quiki_editor.dart) — so a few pixels
      // (a fraction of one character) of drift versus source offset 0 is
      // expected and correct, not a bug. What matters is the anchor lands
      // near the drag's true start (well inside "alpha"), not somewhere
      // unrelated.
      expect(sel.start, inInclusiveRange(0, 'alpha'.length));
      // The extent tracks the live pointer position on every subsequent
      // update (no slop involved once the drag is already recognized), so
      // this lands exactly on the final drag position.
      expect(sel.end, source.length);
    });

    testWidgets(
        'pointer-kind dispatch: a TOUCH drag never changes the selection at '
        'all (scroll gesture, not select) — proves _onPanUpdate\'s '
        '_lastPointerKind gate is still correctly excluding touch',
        (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      // Establish a known starting selection that has nothing to do with
      // either end of the drag, so any accidental leak — extension to the
      // drag's start OR end, from either _onTapDown or _onPanUpdate — would
      // be caught, not just an extension specifically matching the drag.
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 8));
      await tester.pump();
      final before = controller.selectionForTesting;

      final startPos = globalPositionForSourceOffset(tester, ro, 0);
      final endPos = globalPositionForSourceOffset(tester, ro, source.length);
      await performDrag(tester, startPos, endPos,
          kind: PointerDeviceKind.touch);

      final sel = controller.selectionForTesting;
      expect(sel.isCollapsed, isTrue,
          reason: 'a touch drag must NOT extend the selection — touch '
              'dragging is reserved for scrolling (Bug 2)');
      expect(sel.baseOffset, before.baseOffset,
          reason: 'a touch drag must leave the pre-existing selection '
              'completely untouched — _onPanUpdate must gate out for touch '
              'regardless of what _onTapDown does or does not do during a '
              'drag gesture');
    });

    testWidgets(
        'pointer-kind dispatch: a STYLUS drag extends the selection, same '
        'as mouse', (tester) async {
      const source = 'alpha beta gamma delta';
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final startPos = globalPositionForSourceOffset(tester, ro, 0);
      final endPos = globalPositionForSourceOffset(tester, ro, source.length);
      await performDrag(tester, startPos, endPos,
          kind: PointerDeviceKind.stylus);

      final sel = controller.selectionForTesting;
      expect(sel.isCollapsed, isFalse);
      expect(sel.start, inInclusiveRange(0, 'alpha'.length));
      expect(sel.end, source.length);
    });
  });
}
