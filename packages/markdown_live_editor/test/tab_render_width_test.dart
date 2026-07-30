import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Tab render width (fix/tab-render-width).
//
// A literal '\t' character has no real tab-stop concept under Flutter's
// TextPainter — it renders at whatever narrow width the font's tab glyph
// happens to report, in practice roughly one space-width, which reads as too
// narrow to see as an indent. Surfaced by ADR-34 Stage 4's Indent/Dedent
// (indent_dedent.dart), which can insert a literal '\t' into visible text for
// list items and paragraph lines.
//
// Required behaviour under test:
//  - A visible tab renders at ~4x a single space glyph's width, in both
//    live-preview (styled) and plain-text mode — the same RenderModel.build
//    per-character loop both modes flow through (QuikiEditorState forces an
//    empty element list in plain-text mode but always calls
//    RenderModel.build with it).
//  - List-item indentation (a tab used purely as leading-whitespace nesting
//    depth, already fully hidden as a delimiter char folded into the
//    marker) is completely unaffected — regression guard.
//  - Tap-to-source coordinate lookups still resolve correctly around a
//    widened tab region.
// ---------------------------------------------------------------------------

void main() {
  // A fresh Key per call is required: WidgetTester.pumpWidget() on a tree
  // that Widget.canUpdate() considers compatible with the previous one
  // (same runtimeType, same key — both null count as equal) performs an
  // in-place UPDATE, not a fresh mount — _MarkdownEditorState has no
  // didUpdateWidget override to resync its TextEditingController from a
  // changed widget.initialValue, so a second same-test pumpWidget call with
  // a different initialValue but no distinguishing key silently keeps
  // rendering the FIRST call's content. Confirmed by direct repro during
  // this fix's development (a stale second pump measured a source offset
  // inside the first document's list-item content, exactly matching the
  // first document's actual glyph metrics). A UniqueKey per call forces a
  // real unmount + remount every time, which is what every geometry
  // comparison below actually needs.
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

  group('tab render width — live-preview mode', () {
    testWidgets('a tab renders at ~4x the width of a single space glyph',
        (tester) async {
      // Measure the width contributed purely by the character between 'a'
      // and 'b' for a tab vs. a single space, in the same style/font.
      await tester.pumpWidget(buildEditor(initialValue: 'a\tb'));
      await tester.pump();
      final roTab = renderEditorOf(tester);
      final tabWidth =
          roTab.getOffsetForCaret(const TextPosition(offset: 2)).dx -
              roTab.getOffsetForCaret(const TextPosition(offset: 1)).dx;

      await tester.pumpWidget(buildEditor(initialValue: 'a b'));
      await tester.pump();
      final roSpace = renderEditorOf(tester);
      final spaceWidth =
          roSpace.getOffsetForCaret(const TextPosition(offset: 2)).dx -
              roSpace.getOffsetForCaret(const TextPosition(offset: 1)).dx;

      expect(tabWidth, closeTo(spaceWidth * 4, 0.5),
          reason: 'a rendered tab must occupy a visual width equivalent to '
              '4 regular space characters at the current font size');
    });

    testWidgets(
        'tab widening applies to a paragraph leading tab (Indent-inserted) '
        'and to text following a heading marker', (tester) async {
      // Paragraph leading tab — the exact shape ADR-34 Stage 4's Indent
      // action produces for a plain paragraph line.
      await tester.pumpWidget(buildEditor(initialValue: '\tindented'));
      await tester.pump();
      final roPara = renderEditorOf(tester);
      final paraTabWidth =
          roPara.getOffsetForCaret(const TextPosition(offset: 1)).dx -
              roPara.getOffsetForCaret(const TextPosition(offset: 0)).dx;

      // Heading content tab — the Indent fallback inserts a tab at the
      // cursor for heading/blockquote/hr/block-image lines, landing inside
      // the heading's rendered content rather than at line start.
      const headingSource = '# Title\ttext';
      await tester.pumpWidget(buildEditor(initialValue: headingSource));
      await tester.pump();
      final roHeading = renderEditorOf(tester);
      final tabSrcOffset = headingSource.indexOf('\t');
      final headingTabWidth = roHeading
              .getOffsetForCaret(TextPosition(offset: tabSrcOffset + 1))
              .dx -
          roHeading.getOffsetForCaret(TextPosition(offset: tabSrcOffset)).dx;

      // Reference: width of 4 literal spaces in plain body-text style
      // (matches the paragraph line's own style, so directly comparable).
      await tester.pumpWidget(buildEditor(initialValue: '    indented'));
      await tester.pump();
      final roSpaces = renderEditorOf(tester);
      final fourSpaceWidth =
          roSpaces.getOffsetForCaret(const TextPosition(offset: 4)).dx -
              roSpaces.getOffsetForCaret(const TextPosition(offset: 0)).dx;

      expect(paraTabWidth, closeTo(fourSpaceWidth, 0.5),
          reason: 'a paragraph leading tab (Indent-inserted) must widen to '
              '4 space-widths');
      // Heading content renders at a larger font size (h1), so it is only
      // compared against its own body-text-relative expectation: it must be
      // clearly wider than a single (unwidened) tab-like glyph would be —
      // i.e. noticeably more than the plain-paragraph 1-space-ish baseline —
      // confirming the substitution also fires inside heading content, not
      // just plain paragraphs.
      expect(headingTabWidth, greaterThan(paraTabWidth),
          reason: 'a widened tab inside larger (h1) heading content must be '
              'wider than the body-text tab, since both scale with font size '
              'and the h1 tab is still 4 space-widths, just at a bigger font');
    });
  });

  group('tab render width — plain-text mode', () {
    testWidgets(
        'renderedLength reflects 4-space tab expansion identically in '
        'styled and plain-text mode', (tester) async {
      final controller = MarkdownEditorController();
      // '**b**' + tab + 'x'.
      await tester.pumpWidget(
        buildEditor(initialValue: '**b**\tx', controller: controller),
      );
      await tester.pump();

      final ro = renderEditorOf(tester);

      // Styled mode: '**b**' collapses to 'b' (1 rendered char); tab widens
      // to 4 rendered chars; 'x' is 1 rendered char. Total = 6.
      expect(controller.plainTextMode, isFalse);
      expect(ro.renderModel.renderedLength, 6,
          reason: 'styled mode: bold collapses, tab still widens to 4 chars');

      controller.togglePlainTextMode();
      await tester.pump();

      // Plain-text mode: no markdown parsing at all (QuikiEditorState.build
      // forces an empty element list) — all 5 literal '**b**' chars are
      // visible, tab still widens to 4 rendered chars, 'x' is 1 char.
      // Total = 5 + 4 + 1 = 10.
      expect(controller.plainTextMode, isTrue);
      expect(ro.renderModel.renderedLength, 10,
          reason: 'plain-text mode: no collapsing, but the tab-widening '
              'substitution is not gated on any MdElement, so it still '
              'fires even though the element list is empty');
    });

    testWidgets('a tab renders at ~4x a single space glyph in plain-text mode',
        (tester) async {
      final controller = MarkdownEditorController();
      await tester.pumpWidget(
        buildEditor(initialValue: 'a\tb', controller: controller),
      );
      await tester.pump();
      controller.togglePlainTextMode();
      await tester.pump();

      final roTab = renderEditorOf(tester);
      final tabWidth =
          roTab.getOffsetForCaret(const TextPosition(offset: 2)).dx -
              roTab.getOffsetForCaret(const TextPosition(offset: 1)).dx;

      final spaceController = MarkdownEditorController();
      await tester.pumpWidget(
        buildEditor(initialValue: 'a b', controller: spaceController),
      );
      await tester.pump();
      spaceController.togglePlainTextMode();
      await tester.pump();

      final roSpace = renderEditorOf(tester);
      final spaceWidth =
          roSpace.getOffsetForCaret(const TextPosition(offset: 2)).dx -
              roSpace.getOffsetForCaret(const TextPosition(offset: 1)).dx;

      expect(tabWidth, closeTo(spaceWidth * 4, 0.5));
    });
  });

  group('tab render width — list-item indentation regression guard', () {
    testWidgets(
        'a tab used purely for list-item nesting depth is unaffected — '
        'content-start x matches an equivalent space-indented item exactly',
        (tester) async {
      const tabIndented = '\t- item'; // depth 1 via one tab (2 columns)
      const spaceIndented = '  - item'; // depth 1 via two spaces (2 columns)
      const depthZero = '- item'; // depth 0, for contrast

      await tester.pumpWidget(buildEditor(initialValue: tabIndented));
      await tester.pump();
      final roTab = renderEditorOf(tester);
      final tabContentX = roTab
          .getOffsetForCaret(TextPosition(offset: tabIndented.indexOf('item')))
          .dx;

      await tester.pumpWidget(buildEditor(initialValue: spaceIndented));
      await tester.pump();
      final roSpace = renderEditorOf(tester);
      final spaceContentX = roSpace
          .getOffsetForCaret(
              TextPosition(offset: spaceIndented.indexOf('item')))
          .dx;

      expect(tabContentX, spaceContentX,
          reason: 'the leading tab of a nested list item is a hidden '
              'delimiter character folded into the marker (never reaches '
              'the visible-character path this fix touches) — indentation '
              'still comes entirely from RenderRun.indentLevel, exactly as '
              'before this fix, so a tab-indented and a space-indented item '
              'at the same depth must land at the identical content x');

      await tester.pumpWidget(buildEditor(initialValue: depthZero));
      await tester.pump();
      final roZero = renderEditorOf(tester);
      final zeroContentX = roZero
          .getOffsetForCaret(TextPosition(offset: depthZero.indexOf('item')))
          .dx;

      expect(tabContentX, isNot(closeTo(zeroContentX, 0.01)),
          reason: 'sanity check that indentation is actually happening at '
              'all, so the equality above is not vacuously true');
    });
  });

  group('tab render width — coordinate round-trips', () {
    testWidgets(
        'tap-to-source resolves correctly for content on either side of a '
        'widened tab', (tester) async {
      const source = '\tHello world';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      for (final label in ['Hello', 'world']) {
        final targetOffset = source.indexOf(label);
        final caret = ro.getOffsetForCaret(TextPosition(offset: targetOffset));
        // Nudge 2px down from the row-top caret position, matching the
        // existing tap-to-source test convention in block_indentation_test.
        final caretLocal =
            Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
        final resolved = ro.positionForOffset(caretLocal);

        expect(resolved.offset, targetOffset,
            reason: 'a tap at the start of "$label" must resolve back to '
                'that exact source offset even though it sits after a '
                'widened (1 source char -> 4 rendered char) tab region');
      }
    });

    testWidgets(
        'getOffsetForCaret / getPositionForOffset round-trip through a '
        'widened tab region (the mechanism arrow-key up/down movement uses)',
        (tester) async {
      const source = '\tHello';
      await tester.pumpWidget(buildEditor(initialValue: source));
      await tester.pump();
      final ro = renderEditorOf(tester);

      // Source offset 1 = right after the tab, before 'H'.
      final caretAfterTab = ro.getOffsetForCaret(const TextPosition(offset: 1));
      final roundTripped = ro.getPositionForOffset(caretAfterTab);

      expect(roundTripped.offset, 1,
          reason: 'a coordinate query at exactly the caret position for '
              'source offset 1 must resolve back to source offset 1, '
              'confirming sourceToRendered/renderedToSource stay mutually '
              'consistent across the widened tab region');
    });
  });
}
