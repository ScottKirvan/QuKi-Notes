// Widget-level interaction tests for ADR-37 / #345: marker-scoped reveal.
//
// notes/dev/decisions.md -> ADR-37 has the full spec. The pure RenderModel-
// level invariants (the marker's own [start, start + openDelimLen] boundary,
// headings/lists/checkboxes/blockquotes all falling out of the same
// _blockRevealEnd helper, image/hr left untouched) are covered directly in
// render_model_test.dart and nested_inline_test.dart (see the
// "marker-scoped reveal" groups added there). This file drives the SAME
// logic through the real widget tree -- MarkdownEditor -> QuikiEditor ->
// RenderModel.build() called with the controller's actual
// TextEditingValue.selection -- rather than a hand-picked cursorOffset
// passed straight to RenderModel.build() in isolation, using real simulated
// gestures (tester.tapAt) wherever the interaction can realistically happen
// via a screen tap.
//
// A collapsed marker (bullet, ol number, checkbox box, blockquote stripe) is
// painted in the gutter, entirely outside the inline text flow -- it has no
// distinct on-screen rendered position of its own while collapsed (every one
// of its hidden source characters maps to the same rendered offset as the
// first visible content character). So a real tap can never resolve INSIDE
// a currently-collapsed marker's own source range -- there is nothing
// distinct there to tap on, by design (the same reason list/checkbox
// markers moved off the inline TextPainter in ADR-34 to begin with). In
// real device use the cursor lands there via keyboard navigation (Home,
// Left-arrow from content-start, backspace merging a line) rather than a
// tap -- arrow-key device-testing is a separately deferred concern (ADR-31
// Stage 3), not something this suite can rely on simulating end-to-end. For
// those cases this file uses MarkdownEditorController.setSelectionForTesting
// -- the same sanctioned, already-established technique this suite uses
// elsewhere (reading_mode_safety_test.dart, block_indentation_test.dart) for
// precise cursor placement -- which still drives the full widget rebuild
// (a real RenderModel rebuild reacting to the controller's actual
// TextEditingValue), not a bare RenderModel.build() call in isolation.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Helpers -- self-contained per this suite's convention (see
// reading_mode_safety_test.dart's doc comment for the same rationale).
// ---------------------------------------------------------------------------

Widget buildEditor({
  required String initialValue,
  required FocusNode focusNode,
  MarkdownEditorController? controller,
  void Function(int sourceOffset)? onCheckboxToggle,
}) {
  return MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: MarkdownEditor(
        initialValue: initialValue,
        controller: controller,
        focusNode: focusNode,
        onCheckboxToggle: onCheckboxToggle,
      ),
    ),
  );
}

QuikiRenderEditor renderEditorOf(WidgetTester tester) =>
    tester.renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));

/// The global screen position of source offset [sourceOffset], nudged 2px
/// down from the caret's row-top so the tap lands within a glyph's vertical
/// extent -- mirrors reading_mode_safety_test.dart / selection_test.dart's
/// identically-named helper.
Offset globalPositionForSourceOffset(
  WidgetTester tester,
  QuikiRenderEditor ro,
  int sourceOffset,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: sourceOffset));
  final local = Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + local;
}

/// The global screen position of a checkbox glyph's actual painted box --
/// copied from reading_mode_safety_test.dart's identically-named helper; see
/// that file's doc comment for the full geometry rationale (the box position
/// comes from the run's content-start x plus a fixed vertical formula, not
/// an inline character reservation).
Offset checkboxTapPoint(
  WidgetTester tester,
  QuikiRenderEditor ro,
  CheckboxSlot slot,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: slot.element.start));
  final lineHeight = ro.preferredLineHeight;
  final boxSize = lineHeight * 0.8;
  final tapX = caret.dx - 4.0 - boxSize / 2;
  final boxTop = caret.dy + (lineHeight - boxSize) / 2 + lineHeight / 3;
  final tapY = boxTop + boxSize / 2;
  final local = Offset(tapX, tapY) + ro.localPadding.topLeft;
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + local;
}

/// Settles the delayed single-tap resolution this editor's GestureDetector
/// always has -- see reading_mode_safety_test.dart's identically-named
/// helper doc comment: onDoubleTapDown is unconditionally wired alongside
/// onTapDown, so onTapDown itself is deferred until kDoubleTapTimeout has
/// elapsed with no second tap.
Future<void> settleSingleTap(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

Future<void> focusAndSettle(WidgetTester tester, FocusNode focusNode) async {
  await tester.pump();
  focusNode.requestFocus();
  await tester.pump();
}

void main() {
  group('Marker-scoped reveal — list item (ADR-37 / #345)', () {
    testWidgets(
        'tapping inside the item\'s text content does not reveal the "- " '
        'marker (real gesture — invariant 1)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '- click here';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      final ro = renderEditorOf(tester);
      final pos =
          globalPositionForSourceOffset(tester, ro, source.indexOf('here') + 1);
      await tester.tapAt(pos);
      await settleSingleTap(tester);

      final ro2 = renderEditorOf(tester);
      expect(ro2.renderModel.listMarkerSlots, hasLength(1),
          reason: 'the bullet marker must stay collapsed while the cursor '
              'is only in the item text — regression test for #345');
    });

    testWidgets(
        'cursor placed within the marker\'s own characters reveals it as '
        'raw source (invariant 2)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '- click here';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      // Marker is '- ' (openDelimLen 2); offset 1 is inside it. A real user
      // reaches this via keyboard navigation (Home, or Left-arrow from
      // content-start) — see file doc comment for why this isn't a tapAt.
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 1));
      await tester.pump();

      final ro = renderEditorOf(tester);
      expect(ro.renderModel.listMarkerSlots, isEmpty,
          reason: 'a revealed marker is raw source text, not a slot');
      expect(ro.renderModel.textSpan.toPlainText(), startsWith('- '));
    });

    testWidgets(
        'bold text inside the item still reveals correctly on its own — '
        'unaffected by the marker fix (invariant 3)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '- plain **bold** text';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      final ro = renderEditorOf(tester);
      // Cursor inside 'bold' -> its own delimiter chain reveals; the '- '
      // marker (elsewhere on the same line) must stay collapsed throughout.
      final pos =
          globalPositionForSourceOffset(tester, ro, source.indexOf('bold') + 1);
      await tester.tapAt(pos);
      await settleSingleTap(tester);

      final ro2 = renderEditorOf(tester);
      expect(ro2.renderModel.textSpan.toPlainText(), contains('**bold**'),
          reason: 'the bold delimiters reveal exactly as they always have');
      expect(ro2.renderModel.listMarkerSlots, hasLength(1),
          reason: 'the marker stays collapsed while an unrelated inline '
              'element elsewhere on the line is revealed');
    });
  });

  group('Marker-scoped reveal — heading (ADR-37 / #345)', () {
    testWidgets(
        'tapping inside the heading text does not reveal the "# " marker '
        '(invariant 1)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '# Hello World';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      final ro = renderEditorOf(tester);
      final pos = globalPositionForSourceOffset(
          tester, ro, source.indexOf('World') + 1);
      await tester.tapAt(pos);
      await settleSingleTap(tester);

      final ro2 = renderEditorOf(tester);
      expect(ro2.renderModel.textSpan.toPlainText(), 'Hello World',
          reason: 'the "# " marker must stay hidden — only styled heading '
              'text is visible, not raw source (regression test for #345)');
    });

    testWidgets(
        'cursor placed within the marker\'s own characters reveals the raw '
        '"# " prefix (invariant 2)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '# Hello World';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 1));
      await tester.pump();

      final ro = renderEditorOf(tester);
      expect(ro.renderModel.textSpan.toPlainText(), source);
    });
  });

  group('Marker-scoped reveal — blockquote (ADR-37 / #345)', () {
    testWidgets(
        'tapping inside the quoted text does not reveal the "> " marker '
        '(invariant 1)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '> quoted text here';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      final ro = renderEditorOf(tester);
      final pos =
          globalPositionForSourceOffset(tester, ro, source.indexOf('here') + 1);
      await tester.tapAt(pos);
      await settleSingleTap(tester);

      final ro2 = renderEditorOf(tester);
      expect(ro2.renderModel.blockquoteSlots, hasLength(1),
          reason: 'the border-stripe marker must stay collapsed — '
              'regression test for #345');
    });

    testWidgets(
        'cursor placed within the marker\'s own characters reveals the raw '
        '"> " prefix (invariant 2)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '> quoted text here';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 1));
      await tester.pump();

      final ro = renderEditorOf(tester);
      expect(ro.renderModel.blockquoteSlots, isEmpty);
      expect(ro.renderModel.textSpan.toPlainText(), startsWith('> '));
    });
  });

  group('Marker-scoped reveal — nested/indented list item (ADR-34 + ADR-37)',
      () {
    testWidgets(
        'tapping inside a nested item\'s text content does not reveal its '
        'own indented marker (invariant 4)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '- top level\n  - nested click target';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      final ro = renderEditorOf(tester);
      final pos = globalPositionForSourceOffset(
          tester, ro, source.indexOf('target') + 1);
      await tester.tapAt(pos);
      await settleSingleTap(tester);

      final ro2 = renderEditorOf(tester);
      expect(ro2.renderModel.listMarkerSlots, hasLength(2),
          reason: 'both the top-level and nested bullet markers must stay '
              'collapsed — regression test for #345 at a nested depth');
    });

    testWidgets(
        'cursor placed within the nested marker\'s own (indented) '
        'characters reveals only that marker, leaving the top-level one '
        'collapsed (invariant 4)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '- top level\n  - nested click target';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await focusAndSettle(tester, focusNode);

      // Second line starts right after '- top level\n' (12 chars). Its
      // marker is '  - ' (2 indent columns + '- ', openDelimLen 4) — offset
      // lineStart + 1 (the second leading space) lands inside it.
      final lineStart = source.indexOf('\n') + 1;
      controller.setSelectionForTesting(
          TextSelection.collapsed(offset: lineStart + 1));
      await tester.pump();

      final ro = renderEditorOf(tester);
      // Only the top-level marker still collapses to a slot; the nested
      // line's own marker is now revealed raw.
      expect(ro.renderModel.listMarkerSlots, hasLength(1));
      expect(ro.renderModel.listMarkerSlots.single.element.start, 0,
          reason: 'the remaining collapsed slot must be the TOP-LEVEL '
              'marker, not the (now-revealed) nested one');
    });
  });

  group('Checkbox tap-to-toggle non-regression (PR #350, invariant 5)', () {
    testWidgets(
        'toggling a checkbox via a real tap does not move the cursor into '
        'its own marker range or trigger a reveal', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '- [ ] Task',
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) {
          final current = controller.currentValue;
          final marker = current.substring(offset, offset + 6);
          final replacement = marker == '- [ ] ' ? '- [x] ' : '- [ ] ';
          controller.setValuePreservingSelection(
              current.replaceRange(offset, offset + 6, replacement));
        },
      ));
      await focusAndSettle(tester, focusNode);

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      await tester.tapAt(checkboxTapPoint(tester, ro, slot));
      await settleSingleTap(tester);

      final ro2 = renderEditorOf(tester);
      expect(controller.currentValue, '- [x] Task',
          reason: 'sanity check: the tap must actually land on the '
              'checkbox and toggle it, or the assertion below is vacuous');
      expect(ro2.renderModel.checkboxSlots, hasLength(1),
          reason: 'checkbox toggle must not move the cursor into the '
              'marker\'s own range and trigger a reveal — non-regression '
              'against PR #350\'s reading-mode-safety fix');
    });
  });
}
