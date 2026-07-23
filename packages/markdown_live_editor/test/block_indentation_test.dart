import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Block indentation — ADR-34 Stage 1: multi-run rendering foundation +
// nested blockquotes. See notes/dev/block_indentation.md and
// notes/dev/decisions.md → ADR-34 for the full spec.
//
// Layers tested:
//  - RenderModel.runs — pure, no TextPainter needed (indent level per line,
//    merged into maximal same-level runs).
//  - sliceTextSpan — pure TextSpan slicing.
//  - groupBlockquoteRunsByLevel — pure, per-level stripe continuity.
//  - QuikiRenderEditor's public coordinate API (the hard constraint this
//    stage must preserve) — geometry and hit-testing through a real laid-out
//    render object, including the wrapped-line case that is this stage's
//    actual reason to exist.
// ---------------------------------------------------------------------------

const _base = TextStyle(fontSize: 16.0, color: Color(0xFFFFFFFF));

RenderModel _model(String source, {int cursorOffset = -1}) {
  final els = MdParser.parse(source);
  return RenderModel.build(
    source: source,
    elements: els,
    cursorOffset: cursorOffset,
    baseStyle: _base,
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // RenderModel.runs
  // ---------------------------------------------------------------------------
  group('RenderModel.runs', () {
    test('plain text, no indentation → one run at level 0', () {
      final m = _model('hello world');
      expect(m.runs, hasLength(1));
      expect(m.runs.single.indentLevel, 0);
      expect(m.runs.single.start, 0);
      expect(m.runs.single.end, m.renderedLength);
    });

    test('empty source → one degenerate level-0 run', () {
      final m = _model('');
      expect(m.runs, hasLength(1));
      expect(m.runs.single.indentLevel, 0);
      expect(m.runs.single.start, 0);
      expect(m.runs.single.end, 0);
    });

    test('multi-line plain text (no blocks at all) stays one run', () {
      final m = _model('line one\nline two\nline three');
      expect(m.runs, hasLength(1));
      expect(m.runs.single.indentLevel, 0);
      expect(m.runs.single.end, m.renderedLength);
    });

    test('a heading followed by a paragraph stays one level-0 run', () {
      // Headings don't set indentLevel — this guards against accidentally
      // treating "has a block element" as "is indented".
      final m = _model('# Title\nbody text');
      expect(m.runs, hasLength(1));
      expect(m.runs.single.indentLevel, 0);
    });

    test('plain line then a single-level blockquote line → two runs', () {
      // source = 'plain\n> quote' (13 chars)
      // rendered = 'plain' + '\n' + 'quote' (collapsedMarker is now '' — ADR-34)
      const source = 'plain\n> quote';
      final m = _model(source);
      expect(m.textSpan.toPlainText(), 'plain\nquote');
      expect(m.runs, hasLength(2));

      expect(m.runs[0].indentLevel, 0);
      expect(m.runs[0].start, 0);
      expect(m.runs[0].end, 6); // 'plain\n' — the run absorbs the newline

      expect(m.runs[1].indentLevel, 1);
      expect(m.runs[1].start, 6);
      expect(m.runs[1].end, m.renderedLength);
    });

    test('a blockquote line then a plain line → two runs, in the other order',
        () {
      const source = '> quote\nplain';
      final m = _model(source);
      expect(m.runs, hasLength(2));
      expect(m.runs[0].indentLevel, 1);
      expect(m.runs[1].indentLevel, 0);
      expect(m.runs[0].end, m.runs[1].start,
          reason: 'runs must be contiguous — no gap, no overlap');
    });

    test('two consecutive same-level blockquote lines merge into one run', () {
      const source = '> a\n> b';
      final m = _model(source);
      expect(m.runs, hasLength(1));
      expect(m.runs.single.indentLevel, 1);
      expect(m.runs.single.end, m.renderedLength);
    });

    test('depth changes mid-document → runs split exactly at the depth change',
        () {
      // '> a' (depth1) / '>> b' (depth2) / '> c' (depth1) — three runs, since
      // layout runs group by EXACT indent-level match (unlike stripe-run
      // continuity, which is >= K — see groupBlockquoteRunsByLevel below).
      const source = '> a\n>> b\n> c';
      final m = _model(source);
      expect(m.runs, hasLength(3));
      expect(m.runs[0].indentLevel, 1);
      expect(m.runs[1].indentLevel, 2);
      expect(m.runs[2].indentLevel, 1);
      // Contiguous and non-overlapping, and the last run reaches the end.
      expect(m.runs[0].start, 0);
      expect(m.runs[0].end, m.runs[1].start);
      expect(m.runs[1].end, m.runs[2].start);
      expect(m.runs[2].end, m.renderedLength);
    });

    test('a revealed blockquote line (cursor inside) contributes a level-0 run',
        () {
      // Cursor at offset 1 (inside '> quote') reveals the whole line as raw
      // source — it is not indented while revealed, matching how it also
      // produces no blockquoteSlot while revealed.
      const source = 'plain\n> quote';
      final m = _model(source, cursorOffset: source.indexOf('quote'));
      // Only the blockquote line's run should be level 0 now; both lines end
      // up level 0, so RenderModel.runs collapses back to a single run.
      expect(m.runs, hasLength(1));
      expect(m.runs.single.indentLevel, 0);
    });

    test('runs are contiguous and cover [0, renderedLength] with no gaps', () {
      const source = 'a\n> b\n>> c\nd\n> e';
      final m = _model(source);
      expect(m.runs.first.start, 0);
      expect(m.runs.last.end, m.renderedLength);
      for (var i = 1; i < m.runs.length; i++) {
        expect(m.runs[i - 1].end, m.runs[i].start,
            reason: 'run $i must start exactly where run ${i - 1} ends');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // sliceTextSpan
  // ---------------------------------------------------------------------------
  group('sliceTextSpan', () {
    test('start >= end → empty span', () {
      final span = sliceTextSpan(const TextSpan(text: 'hello'), 3, 3);
      expect(span.toPlainText(), '');
    });

    test('single flat span (no children): slices the plain text', () {
      const span = TextSpan(text: 'hello world');
      expect(sliceTextSpan(span, 0, 5).toPlainText(), 'hello');
      expect(sliceTextSpan(span, 6, 11).toPlainText(), 'world');
      expect(sliceTextSpan(span, 0, 11).toPlainText(), 'hello world');
    });

    test('multi-leaf span: slice entirely within one leaf', () {
      const span = TextSpan(children: [
        TextSpan(text: 'abc', style: TextStyle(color: Color(0xFF000000))),
        TextSpan(text: 'defgh', style: TextStyle(color: Color(0xFF111111))),
      ]);
      final sliced = sliceTextSpan(span, 4, 7); // 'e','f','g' inside leaf 2
      expect(sliced.toPlainText(), 'efg');
    });

    test(
        'multi-leaf span: slice spanning a leaf boundary preserves both '
        'styles', () {
      const styleA = TextStyle(color: Color(0xFF000000));
      const styleB = TextStyle(color: Color(0xFF111111));
      const span = TextSpan(children: [
        TextSpan(text: 'abc', style: styleA),
        TextSpan(text: 'def', style: styleB),
      ]);
      final sliced = sliceTextSpan(span, 1, 5); // 'bc' + 'de'
      expect(sliced.toPlainText(), 'bcde');
      final children = sliced.children!;
      expect(children, hasLength(2));
      expect((children[0] as TextSpan).text, 'bc');
      expect((children[0] as TextSpan).style, styleA);
      expect((children[1] as TextSpan).text, 'de');
      expect((children[1] as TextSpan).style, styleB);
    });

    test('multi-leaf span: full-range slice reproduces identical content', () {
      const span = TextSpan(children: [
        TextSpan(text: 'abc'),
        TextSpan(text: 'def'),
      ]);
      final sliced = sliceTextSpan(span, 0, 6);
      expect(sliced.toPlainText(), 'abcdef');
    });

    test('leaves entirely outside [start, end) are omitted', () {
      const span = TextSpan(children: [
        TextSpan(text: 'abc'),
        TextSpan(text: 'def'),
        TextSpan(text: 'ghi'),
      ]);
      final sliced = sliceTextSpan(span, 3, 6); // exactly the middle leaf
      expect(sliced.toPlainText(), 'def');
      expect(sliced.children, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // groupBlockquoteRunsByLevel — per-level stripe continuity (ADR-34)
  // ---------------------------------------------------------------------------
  group('groupBlockquoteRunsByLevel', () {
    test('empty input → empty map', () {
      expect(groupBlockquoteRunsByLevel(const []), isEmpty);
    });

    test(
        'single-level blockquote (all depth 1) → only level 1 present, one '
        'run', () {
      final m = _model('> a\n> b\n> c');
      final grouped = groupBlockquoteRunsByLevel(m.blockquoteSlots);
      expect(grouped.keys, [1]);
      expect(grouped[1], hasLength(1));
      expect(grouped[1]!.single, hasLength(3));
    });

    test(
        'the spec worked example: level1/level2/level1 → stripe-1 spans all '
        'three, stripe-2 spans only the middle', () {
      // '> level 1 line\n>> level 2 line\n> level 1 again'
      const source = '> level 1 line\n>> level 2 line\n> level 1 again';
      final m = _model(source);
      expect(m.blockquoteSlots, hasLength(3));
      expect(m.blockquoteSlots[0].element.indentLevel, 1);
      expect(m.blockquoteSlots[1].element.indentLevel, 2);
      expect(m.blockquoteSlots[2].element.indentLevel, 1);

      final grouped = groupBlockquoteRunsByLevel(m.blockquoteSlots);
      expect(grouped.keys.toList()..sort(), [1, 2]);

      // Level 1: one continuous run covering all three slots.
      expect(grouped[1], hasLength(1));
      expect(grouped[1]!.single, hasLength(3));

      // Level 2: one run covering only the middle slot.
      expect(grouped[2], hasLength(1));
      expect(grouped[2]!.single, hasLength(1));
      expect(grouped[2]!.single.single, same(m.blockquoteSlots[1]));
    });

    test(
        '3-level case: a/b/c/d/e at depths 1/2/3/2/1 → per-level run '
        'lengths 5/3/1', () {
      const source = '> a\n>> b\n>>> c\n>> d\n> e';
      final m = _model(source);
      expect(m.blockquoteSlots, hasLength(5));
      expect(m.blockquoteSlots.map((s) => s.element.indentLevel).toList(),
          [1, 2, 3, 2, 1]);

      final grouped = groupBlockquoteRunsByLevel(m.blockquoteSlots);
      expect(grouped.keys.toList()..sort(), [1, 2, 3]);

      // Level 1: all five lines are depth >= 1 and all source-adjacent → one
      // run of 5.
      expect(grouped[1], hasLength(1));
      expect(grouped[1]!.single, hasLength(5));

      // Level 2: lines b, c, d (depth >= 2) are adjacent → one run of 3.
      expect(grouped[2], hasLength(1));
      expect(grouped[2]!.single, hasLength(3));

      // Level 3: only line c (depth >= 3) → one run of 1.
      expect(grouped[3], hasLength(1));
      expect(grouped[3]!.single, hasLength(1));
    });

    test(
        'a non-blockquote line breaks continuity at every level it '
        'interrupts', () {
      // '> a' (1) / plain / '>> c' (2) — the plain line has no slot at all,
      // so both the depth-1 and depth-2 lines start fresh runs.
      const source = '> a\nplain\n>> c';
      final m = _model(source);
      final grouped = groupBlockquoteRunsByLevel(m.blockquoteSlots);
      // Level 1: both 'a' (depth1) and 'c' (depth2, so also >=1) qualify, but
      // they are NOT source-adjacent (the plain line sits between them) → two
      // separate runs of length 1 each.
      expect(grouped[1], hasLength(2));
      expect(grouped[1]![0], hasLength(1));
      expect(grouped[1]![1], hasLength(1));
      // Level 2: only 'c' qualifies → one run of 1.
      expect(grouped[2], hasLength(1));
      expect(grouped[2]!.single, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Widget-level: geometry and hit-testing through the real render object.
  // ---------------------------------------------------------------------------

  Widget buildEditor({
    required String initialValue,
    MarkdownEditorController? controller,
    bool autofocus = false,
    void Function(String url)? onLinkTap,
    void Function(int sourceOffset)? onCheckboxToggle,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MarkdownEditor(
          initialValue: initialValue,
          controller: controller,
          autofocus: autofocus,
          onLinkTap: onLinkTap,
          onCheckboxToggle: onCheckboxToggle,
        ),
      ),
    );
  }

  QuikiRenderEditor renderEditorOf(WidgetTester tester) =>
      tester.renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));

  group('QuikiRenderEditor — indentation geometry (public API only)', () {
    testWidgets(
        'blockquote content is indented relative to a plain line above it',
        (tester) async {
      const source = 'plain\n> quote';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final plainDx = ro.getOffsetForCaret(const TextPosition(offset: 0)).dx;
      final quoteContentOffset = source.indexOf('quote');
      final quoteDx =
          ro.getOffsetForCaret(TextPosition(offset: quoteContentOffset)).dx;

      // Tolerance is loose (not 0.0 exactly) because the test font reports a
      // small sub-pixel leading offset on every laid-out run's own first
      // row — unrelated to indentation, present even at indent level 0.
      expect(plainDx, closeTo(0.0, 1.0),
          reason: 'plain paragraph content is not indented');
      expect(quoteDx, greaterThan(plainDx + 8.0),
          reason: 'blockquote content must be pushed meaningfully to the '
              "right, via its own narrower/offset layout run — not just "
              'differ by sub-pixel noise');
    });

    testWidgets(
        'a nested (depth-2) blockquote line is indented further than '
        'a depth-1 line', (tester) async {
      const source = '> one\n>> two';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final oneDx =
          ro.getOffsetForCaret(TextPosition(offset: source.indexOf('one'))).dx;
      final twoDx =
          ro.getOffsetForCaret(TextPosition(offset: source.indexOf('two'))).dx;

      expect(twoDx, greaterThan(oneDx),
          reason: 'a deeper nesting level must be indented further right');
    });

    testWidgets(
        'a wrapped blockquote line has every wrapped visual row indented — '
        'the regression this stage exists to fix', (tester) async {
      // Long enough, at the default 800px test-surface width, to wrap into
      // multiple visual rows even after the 16px reduction for depth 1.
      final longQuote =
          '> ${'this is a deliberately long quoted line that must wrap ' * 4}';
      await tester.pumpWidget(buildEditor(initialValue: longQuote));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final ro = renderEditorOf(tester);
      final contentStart = longQuote.indexOf(' ', 1) + 1; // just past '> '

      // Walk every source offset across the quoted content, recording the dx
      // at the start of every visual row (a row boundary is detected by a dy
      // change). Before this stage's fix, word-wrap would reset every
      // wrapped row's dx back to 0 (or the run's un-indented default) instead
      // of the blockquote's own indent — that is the exact bug being fixed.
      // Stops strictly before longQuote.length: the end-sentinel position
      // (one past the last character) reports a dy a few px below the last
      // row's own row-start dy — not a full row height below — which is a
      // harmless caret-metrics quirk for "end of text" specifically, not a
      // new visual row. Including it would produce a false extra "row" whose
      // dx is a genuine mid-row value, not a row-start value, breaking this
      // test's premise for reasons unrelated to indentation.
      // Two separate things are tracked: how many distinct rows were found
      // (a List, so repeats count — used only to confirm the test actually
      // exercises wrapping) and the set of distinct dx values seen at a row
      // start (a Set — collapses to length 1 exactly when every row is
      // indented consistently, which is the property under test).
      final rowStartDxSeen = <double>[];
      final rowStartDxUnique = <double>{};
      double? lastDy;
      for (var srcOff = contentStart; srcOff < longQuote.length; srcOff++) {
        final o = ro.getOffsetForCaret(TextPosition(offset: srcOff));
        if (lastDy == null || (o.dy - lastDy).abs() > 1.0) {
          rowStartDxSeen.add(o.dx);
          rowStartDxUnique.add(o.dx);
          lastDy = o.dy;
        }
      }

      expect(rowStartDxSeen.length, greaterThan(1),
          reason: 'the content must actually wrap into multiple visual rows '
              'for this test to be meaningful — increase the source length '
              'if this fails');
      expect(rowStartDxUnique, hasLength(1),
          reason: 'every wrapped visual row must start at the SAME x (the '
              "run's indent) — a mix of values means at least one wrapped "
              'row snapped back to the un-indented margin');
      expect(rowStartDxUnique.single, greaterThan(0.0),
          reason: 'the shared row-start x must be a real indent, not '
              'trivially 0');
    });

    testWidgets(
        'nested blockquote (3 lines, depths 1/2/1) paints without error and '
        'produces 3 distinct layout runs', (tester) async {
      const source = '> level 1 line\n>> level 2 line\n> level 1 again';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final ro = renderEditorOf(tester);
      expect(ro.renderModel.blockquoteSlots, hasLength(3));
      // Layout runs split on exact depth match (1, 2, 1) even though the
      // level-1 STRIPE spans all three lines continuously (tested above at
      // the RenderModel level via groupBlockquoteRunsByLevel).
      expect(ro.renderModel.runs, hasLength(3));
      expect(ro.renderModel.runs.map((r) => r.indentLevel).toList(), [1, 2, 1]);
    });

    testWidgets('deeply-nested (3-level) blockquote paints without error',
        (tester) async {
      const source = '> a\n>> b\n>>> c\n>> d\n> e';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final ro = renderEditorOf(tester);
      expect(ro.renderModel.blockquoteSlots, hasLength(5));
    });
  });

  group('QuikiRenderEditor — cursor movement across a run boundary', () {
    // Exercises the same public coordinate API quiki_editor.dart's
    // _moveUp/_moveDown are built on (getOffsetForCaret + getPositionForOffset)
    // — the contract this stage must preserve — rather than a full keyboard-
    // event simulation (no existing precedent for that in this suite).
    //
    // Target Y is taken directly from the known destination line's own caret
    // position (with a small downward nudge to land inside its row rather
    // than exactly on a row-top boundary — see the tap-to-source test above
    // for why exact boundaries are ambiguous when independently-laid-out
    // runs are stacked), rather than by adding/subtracting a fixed step to
    // the current position. quiki_editor.dart's real _moveUp/_moveDown do use
    // a fixed step (one preferredLineHeight) — but this suite's test font
    // reports preferredLineHeight (~14px, unmultiplied font size) noticeably
    // smaller than the real per-row visual spacing (~20px, from this editor's
    // 1.4 line-height multiplier), a pre-existing mismatch that predates
    // ADR-34 (preferredLineHeight is read from a TextSpan whose root carries
    // no style, disconnected from the actual rendered TextStyle) and is out
    // of scope for this stage. A fixed-step version of this test would be
    // testing that pre-existing imprecision, not the run-crossing mechanism
    // this stage adds — so it targets a known line's Y directly instead.
    double nudgedY(QuikiRenderEditor ro, int offset) =>
        ro.getOffsetForCaret(TextPosition(offset: offset)).dy + 2.0;

    testWidgets(
        'moving down from the last line of a blockquote lands in the plain '
        'line below it (not lost, not out of bounds)', (tester) async {
      const source = '> quoted line\nplain text after';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final startOffset = source.indexOf('quoted');
      final currentX =
          ro.getOffsetForCaret(TextPosition(offset: startOffset)).dx;
      final plainLineStart = source.indexOf('plain');
      final targetY = nudgedY(ro, plainLineStart);

      final newPos = ro.getPositionForOffset(Offset(currentX, targetY));
      expect(newPos.offset, greaterThanOrEqualTo(plainLineStart),
          reason: 'a Y coordinate on the plain line below a blockquote must '
              'resolve to that line, not remain stuck in the blockquote run');
      expect(newPos.offset, lessThanOrEqualTo(source.length));
    });

    testWidgets(
        'moving up from the plain line below a blockquote lands back inside '
        'the blockquote (not lost, not out of bounds)', (tester) async {
      const source = '> quoted line\nplain text after';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final plainLineStart = source.indexOf('plain');
      final currentX =
          ro.getOffsetForCaret(TextPosition(offset: plainLineStart)).dx;
      final quotedLineStart = source.indexOf('quoted');
      final targetY = nudgedY(ro, quotedLineStart);

      final newPos = ro.getPositionForOffset(Offset(currentX, targetY));
      expect(newPos.offset, lessThan(plainLineStart),
          reason: 'a Y coordinate on the blockquote line above must resolve '
              'back inside it, not remain stuck on the plain line below');
      expect(newPos.offset, greaterThanOrEqualTo(0));
    });

    testWidgets(
        'moving down/up across a 3-level nested boundary does not '
        'crash or go out of bounds', (tester) async {
      const source = '> a\n>> b\n>>> c\nplain after';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      // Step through every consecutive line pair, moving "down" via each
      // next line's own known Y — verifying every run-to-run transition in a
      // 3-level nested document lands within bounds without crashing.
      final lineStarts = [
        source.indexOf('a'),
        source.indexOf('b'),
        source.indexOf('c'),
        source.indexOf('plain'),
      ];
      for (var i = 0; i < lineStarts.length - 1; i++) {
        final currentX =
            ro.getOffsetForCaret(TextPosition(offset: lineStarts[i])).dx;
        final targetY = nudgedY(ro, lineStarts[i + 1]);
        final newPos = ro.getPositionForOffset(Offset(currentX, targetY));
        expect(newPos.offset, inInclusiveRange(0, source.length));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('QuikiRenderEditor — hit-testing inside an indented run', () {
    testWidgets(
        'tap-to-source round-trips correctly for a character inside blockquote '
        'content', (tester) async {
      const source = 'plain\n> quoted text';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final targetOffset = source.indexOf('text');
      final caret = ro.getOffsetForCaret(TextPosition(offset: targetOffset));
      // Nudge 2px down from the caret's row-top position before tapping —
      // matches how a real tap lands somewhere within a glyph's vertical
      // extent, not exactly on the row's top edge, and avoids the run-to-run
      // Y-band boundary's sub-pixel ambiguity (each independently-laid-out
      // run's own first row carries a tiny font-metrics leading offset that
      // doesn't perfectly cancel when their heights are summed).
      final caretLocal =
          Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
      final resolved = ro.positionForOffset(caretLocal);

      expect(resolved.offset, targetOffset,
          reason: 'a tap at (approximately) where a character is painted '
              'must resolve back to that same source offset, even inside an '
              'indented run');
    });

    testWidgets(
        'linkUrlForOffset resolves a link nested inside blockquote '
        'content (indented run)', (tester) async {
      const source = '> see [docs](https://example.com) for more';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      expect(ro.renderModel.linkSlots, hasLength(1));
      final slot = ro.renderModel.linkSlots.single;
      expect(slot.element.url, 'https://example.com');

      // Resolve a source offset that lands inside the rendered link label
      // ('docs'), then confirm a tap there is recognized as the link.
      final midRendered = (slot.renderedStart + slot.renderedEnd) ~/ 2;
      final midSource = ro.renderModel.sourceForRendered(midRendered);
      final tapLocal = ro.getOffsetForCaret(TextPosition(offset: midSource)) +
          ro.localPadding.topLeft;

      expect(ro.linkUrlForOffset(tapLocal), 'https://example.com');
    });

    testWidgets(
        'checkboxSourceOffsetForTap still resolves correctly when the '
        'document also contains an indented (blockquote) run', (tester) async {
      // The checkbox itself is not nested inside the blockquote (list-inside-
      // blockquote parsing is out of scope for this stage), but the document
      // has two runs — the blockquote (level 1) and the checkbox line
      // (level 0) below it — exercising multi-run hit-test routing.
      const source = '> quoted\n- [ ] task';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      expect(ro.renderModel.runs, hasLength(2));
      final slot = ro.renderModel.checkboxSlots.single;

      // +2px nudge into the row: the checkbox line is the very first
      // character of its run, so its unnudged caret Y sits exactly on the
      // run-to-run boundary — see the tap-to-source test above for why that
      // exact boundary is ambiguous when independently-laid-out runs are
      // stacked.
      final caret =
          ro.getOffsetForCaret(TextPosition(offset: slot.element.start));
      final tapLocal =
          Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
      final resolved = ro.checkboxSourceOffsetForTap(tapLocal);

      expect(resolved, slot.element.start);
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-34 Stage 2+3 — nested list indentation wired into the Stage 1
  // rendering foundation. Layers tested mirror Stage 1's blockquote coverage
  // above: RenderModel.runs (pure), then widget-level geometry and hit-
  // testing through a real laid-out render object.
  // ---------------------------------------------------------------------------

  group('RenderModel.runs — list kinds (ADR-34 Stage 2+3)', () {
    test(
        'an indented ul line contributes a run at its indentLevel, exactly '
        'like a blockquote line does', () {
      const source = 'plain\n  - item';
      final m = _model(source);
      expect(m.runs, hasLength(2));
      expect(m.runs[0].indentLevel, 0);
      expect(m.runs[1].indentLevel, 1);
      expect(m.runs[0].end, m.runs[1].start);
      expect(m.runs[1].end, m.renderedLength);
    });

    test('two-level-deep nested ul lines produce two runs at depths 1 and 2',
        () {
      const source = '  - one\n    - two';
      final m = _model(source);
      expect(m.runs, hasLength(2));
      expect(m.runs[0].indentLevel, 1);
      expect(m.runs[1].indentLevel, 2);
    });

    test('ol indentation contributes runs the same way as ul', () {
      const source = '1. top\n  1. sub';
      final m = _model(source);
      expect(m.runs, hasLength(2));
      expect(m.runs[0].indentLevel, 0);
      expect(m.runs[1].indentLevel, 1);
    });

    test('checkbox indentation contributes runs the same way as ul', () {
      const source = '- [ ] top\n  - [ ] sub';
      final m = _model(source);
      expect(m.runs, hasLength(2));
      expect(m.runs[0].indentLevel, 0);
      expect(m.runs[1].indentLevel, 1);
    });

    test(
        'a revealed indented list line (cursor inside) contributes a '
        'level-0 run, mirroring the revealed-blockquote-line behavior', () {
      const source = 'plain\n  - item';
      final m = _model(source, cursorOffset: source.indexOf('item'));
      // Both lines collapse to level 0 while the list line is revealed, so
      // RenderModel.runs merges back to a single run — same mechanism as the
      // analogous blockquote test above.
      expect(m.runs, hasLength(1));
      expect(m.runs.single.indentLevel, 0);
    });

    test(
        'a document mixing a nested list and a nested blockquote does not '
        'corrupt either kind\'s layout runs or slot lists — both now feed '
        'the same _computeRuns mechanism', () {
      const source = '- top item\n> quoted text\n  - nested item';
      final m = _model(source);

      // Line 0 (ul, depth 0) is its own run; lines 1-2 (blockquote depth 1,
      // then ul depth 1) share the same indent level and merge into one run
      // — runs are keyed purely by indent level, not by which block kind
      // produced it, which is the intended generalization.
      expect(m.runs, hasLength(2));
      expect(m.runs[0].indentLevel, 0);
      expect(m.runs[1].indentLevel, 1);
      expect(m.runs[0].end, m.runs[1].start);
      expect(m.runs[1].end, m.renderedLength);

      // Neither kind's own bookkeeping was disturbed by the other's presence.
      expect(m.blockquoteSlots, hasLength(1));
      final uls =
          MdParser.parse(source).where((e) => e.kind == MdElKind.ul).toList();
      expect(uls, hasLength(2));
      expect(uls[0].indentLevel, 0);
      expect(uls[1].indentLevel, 1);
    });
  });

  group(
      'QuikiRenderEditor — nested list indentation geometry (ADR-34 Stage '
      '2+3)', () {
    testWidgets(
        'nested list-item content is indented relative to a plain line '
        'above it', (tester) async {
      const source = 'plain\n  - item';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final plainDx = ro.getOffsetForCaret(const TextPosition(offset: 0)).dx;
      final itemContentOffset = source.indexOf('item');
      final itemDx =
          ro.getOffsetForCaret(TextPosition(offset: itemContentOffset)).dx;

      expect(plainDx, closeTo(0.0, 1.0),
          reason: 'plain paragraph content is not indented');
      expect(itemDx, greaterThan(plainDx + 8.0),
          reason: 'nested list content must be pushed meaningfully to the '
              'right via its own narrower/offset layout run');
    });

    testWidgets(
        'a depth-2 nested list line is indented further than a depth-1 '
        'line', (tester) async {
      const source = '  - one\n    - two';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final oneDx =
          ro.getOffsetForCaret(TextPosition(offset: source.indexOf('one'))).dx;
      final twoDx =
          ro.getOffsetForCaret(TextPosition(offset: source.indexOf('two'))).dx;

      expect(twoDx, greaterThan(oneDx),
          reason: 'a deeper nesting level must be indented further right');
    });

    testWidgets(
        'a wrapped nested-list line has every wrapped visual row indented — '
        'the same regression class Stage 1 fixed for blockquotes, now '
        'verified for lists', (tester) async {
      const prefix = '  - '; // 2-space indent + unordered marker
      final longItem =
          '$prefix${'this is a deliberately long list item that must wrap ' * 4}';
      await tester.pumpWidget(buildEditor(initialValue: longItem));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final ro = renderEditorOf(tester);
      const contentStart = prefix.length;

      final rowStartDx = <double>[];
      double? lastDy;
      for (var srcOff = contentStart; srcOff < longItem.length; srcOff++) {
        final o = ro.getOffsetForCaret(TextPosition(offset: srcOff));
        if (lastDy == null || (o.dy - lastDy).abs() > 1.0) {
          rowStartDx.add(o.dx);
          lastDy = o.dy;
        }
      }

      expect(rowStartDx.length, greaterThan(2),
          reason: 'need at least one wrapped continuation row beyond the '
              'first for this test to be meaningful — increase the source '
              'length if this fails');

      // The FIRST visual row legitimately sits further right than every
      // continuation row: the collapsed bullet glyph ("• ") is rendered
      // text that only occupies width on that first row — a pre-existing
      // characteristic of how the list marker has always rendered (present
      // identically at indentLevel 0, confirmed by inspection before this
      // test was finalized), unaffected by this stage in either direction.
      // What THIS stage owns, and what this test actually verifies, is that
      // every WRAPPED CONTINUATION row stays at the run's own non-zero
      // depth-1 indent instead of snapping back to the left margin — that
      // snap-back is the historical bug class (block_indentation.md).
      final continuationDx = rowStartDx.sublist(1).toSet();
      expect(continuationDx, hasLength(1),
          reason: 'every wrapped CONTINUATION row must start at the SAME x '
              "(the run's indent) — a mix of values means at least one "
              'wrapped row snapped back to the un-indented margin');
      expect(continuationDx.single, greaterThan(0.0),
          reason: 'the shared continuation-row x must be a real depth-1 '
              'indent, not trivially 0 (i.e. not lost back to the margin)');
      expect(rowStartDx.first, greaterThan(continuationDx.single),
          reason: 'the first row is expected to sit further right than the '
              'continuation rows, for the bullet-glyph reason documented '
              'above — not itself a regression');
    });

    testWidgets(
        'a mixed document (nested list + nested blockquote) paints without '
        'error', (tester) async {
      const source = '- top\n> quoted\n  - nested\n>> deeper';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group(
      'QuikiRenderEditor — hit-testing inside a nested list run (ADR-34 '
      'Stage 2+3)', () {
    testWidgets(
        'tap-to-source round-trips correctly for a character inside nested '
        'list-item content', (tester) async {
      const source = 'plain\n  - item text';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final targetOffset = source.indexOf('text');
      final caret = ro.getOffsetForCaret(TextPosition(offset: targetOffset));
      final caretLocal =
          Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
      final resolved = ro.positionForOffset(caretLocal);

      expect(resolved.offset, targetOffset,
          reason: 'a tap at (approximately) where a character is painted '
              'must resolve back to that same source offset, even inside a '
              'nested list run');
    });

    testWidgets(
        'checkboxSourceOffsetForTap still resolves correctly for a nested '
        '(indented) checkbox item', (tester) async {
      const source = '  - [ ] task';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      final slot = ro.renderModel.checkboxSlots.single;
      final caret =
          ro.getOffsetForCaret(TextPosition(offset: slot.element.start));
      final tapLocal =
          Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
      final resolved = ro.checkboxSourceOffsetForTap(tapLocal);

      expect(resolved, slot.element.start);
    });

    testWidgets(
        'linkUrlForOffset resolves a link nested inside a nested list '
        'item\'s content (indented run)', (tester) async {
      const source = '  - see [docs](https://example.com) for more';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      expect(ro.renderModel.linkSlots, hasLength(1));
      final slot = ro.renderModel.linkSlots.single;
      expect(slot.element.url, 'https://example.com');

      final midRendered = (slot.renderedStart + slot.renderedEnd) ~/ 2;
      final midSource = ro.renderModel.sourceForRendered(midRendered);
      final tapLocal = ro.getOffsetForCaret(TextPosition(offset: midSource)) +
          ro.localPadding.topLeft;

      expect(ro.linkUrlForOffset(tapLocal), 'https://example.com');
    });
  });
}
