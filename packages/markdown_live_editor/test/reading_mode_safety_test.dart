// Regression tests for three related reading-mode bugs, all driven by real
// simulated gestures (tester.tapAt / tester.longPressAt / two tapAt calls for
// double-tap) rather than programmatic controller mutation — this project has
// been burned before by tests that only assert the data change and miss the
// actual UX regression (see checkbox rendering history, root CLAUDE.md).
//
// #335 / #266 — tapping a rendered checkbox (☐/☑) must toggle it without
// switching the note out of reading mode: no focus request, no keyboard, no
// cursor jump, no scroll. Both issues trace to the SAME root cause:
// MarkdownEditorController.setValue() (via _MarkdownEditorState._setValue)
// hardcodes the post-update selection to TextSelection.collapsed(offset: 0)
// — unconditionally, regardless of why the content changed. For #266's
// multi-line repro this jumps the cursor to line 1 (scroll-to-top). For
// #335's repro (a checklist item as the note's ONLY line) offset 0 happens to
// fall inside that same checkbox element, so RenderModel.build's reveal rule
// (cursorOffset within the outermost covering element's [start, end] reveals
// it — see render_model.dart, NOT gated on focus at all) reveals it as raw
// markdown source. A second, independent contributor to #266's "keyboard
// opens" half: QuikiEditorState._onTapDown unconditionally requests focus /
// re-shows the IME connection BEFORE checking whether the tap landed on a
// checkbox glyph — so even a checkbox tap that correctly avoids moving the
// cursor still requests focus as a side effect of the tap-down that preceded
// the checkbox-hit-test branch.
//
// #336 — selecting text via long-press or double-tap while unfocused must
// not open the keyboard. Root cause: the exact same QuikiEditorState.
// _onTapDown focus-request side effect above also fires for the tap-down
// that precedes a long-press or double-tap gesture (GestureDetector fires
// onTapDown once the single-vs-double-tap ambiguity resolves, which for a
// held-down long-press happens partway into the hold, well before
// _onLongPressStart's own long-press-duration threshold) — so even though
// neither _onLongPressStart nor _onDoubleTapDown call requestFocus
// themselves, the preceding _onTapDown already did.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Helpers — self-contained, mirroring the equivalent helpers already
// established in selection_test.dart / block_indentation_test.dart (each
// test file in this suite keeps its own copies rather than sharing a helper
// module — see checkbox_toggle_test.dart's own doc comment for the same
// convention applied to the marker-toggle logic below).
// ---------------------------------------------------------------------------

// A fresh Key per pumpWidget call forces a real unmount + remount rather than
// an in-place widget update — see notes/dev/testing.md's pumpWidget-reuse
// gotcha.
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

ScrollableState scrollableOf(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first);

/// The global screen position of source offset [sourceOffset], nudged 2px
/// down from the caret's row-top so the tap lands within a glyph's vertical
/// extent — mirrors selection_test.dart's identically-named helper.
Offset globalPositionForSourceOffset(
  WidgetTester tester,
  QuikiRenderEditor ro,
  int sourceOffset,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: sourceOffset));
  final local = Offset(caret.dx, caret.dy + 2.0) + ro.localPadding.topLeft;
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + local;
}

/// The global screen position of a checkbox glyph's actual painted box.
///
/// The geometry formula is copied from block_indentation_test.dart's
/// checkboxTapPoint (see that file's doc comment for why this is not simply
/// getOffsetForCaret at the element's start: the box position comes from the
/// run's content-start x plus a fixed vertical formula, not an inline
/// character reservation) — but that original helper returns a LOCAL offset
/// within the render object's own coordinate space, because its only caller
/// feeds it straight into QuikiRenderEditor.checkboxSourceOffsetForTap (a
/// pure geometry call, no real gesture involved). This copy additionally
/// converts to GLOBAL screen coordinates via tester.getTopLeft, because every
/// use in this file drives an actual tester.tapAt — treating the local
/// offset as if it were already global would only coincidentally land on the
/// checkbox when the render object's global origin happens to be near
/// (0, 0) (an unscrolled document), and reliably miss it once the document
/// has been scrolled (confirmed empirically while writing this suite: the
/// off-screen-checkbox test below silently tapped nothing at all, toggling
/// nothing, until this conversion was added).
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
/// always has (an onDoubleTapDown callback is unconditionally wired
/// alongside onTapDown — see quiki_editor.dart's build() — so per Flutter's
/// own documented GestureDetector behaviour, onTapDown itself is deferred
/// until kDoubleTapTimeout has elapsed with no second tap, not fired
/// eagerly on pointer-down). Confirmed empirically while writing this suite
/// (a throwaway diagnostic test): a single tapAt's effects — including a
/// checkbox toggle, since the checkbox hit-test lives inside _onTapDown's
/// own (delayed) callback — are not observable until a pump of at least
/// this duration follows. Any test in this file asserting on the result of
/// ONE tapAt (not part of doubleTapAt, which already settles its own two
/// taps) must pump this after the tap before asserting.
Future<void> settleSingleTap(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

/// Simulates a real double-tap — two separate tap gestures at the same
/// location, close enough to fall inside kDoubleTapTimeout. Copied from
/// selection_test.dart's doubleTapAt; see that file's doc comment for why
/// the trailing pump must exceed kDoubleTapTimeout (drains
/// DoubleTapGestureRecognizer's internal timer so flutter_test's teardown
/// doesn't fail on a still-pending Timer).
Future<void> doubleTapAt(WidgetTester tester, Offset location) async {
  await tester.tapAt(location);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(location);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Mirrors the checkbox-toggle logic in
/// lib/features/editor/editor_screen.dart's EditorScreen._onCheckboxToggle:
/// toggles the 6-char marker and writes the result back through the
/// controller. Kept in sync with EditorScreen's real write call so this test
/// exercises the real production flow rather than a synthetic shortcut — see
/// checkbox_toggle_test.dart's toggleCheckbox for the equivalent precedent
/// for the pure marker-swap logic on its own.
void handleCheckboxToggle(
    MarkdownEditorController controller, int sourceOffset) {
  final current = controller.currentValue;
  if (sourceOffset < 0 || sourceOffset + 6 > current.length) return;
  final marker = current.substring(sourceOffset, sourceOffset + 6);
  final String replacement;
  if (marker == '- [ ] ') {
    replacement = '- [x] ';
  } else if (marker == '- [x] ' || marker == '- [X] ') {
    replacement = '- [ ] ';
  } else {
    return;
  }
  final newText =
      current.replaceRange(sourceOffset, sourceOffset + 6, replacement);
  controller.setValue(newText);
}

void main() {
  group('Checkbox tap is reading-mode-safe (#335, #266)', () {
    testWidgets(
        'tapping a checkbox while unfocused (reading mode) does not request '
        'focus or open the keyboard', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      int? toggledOffset;
      await tester.pumpWidget(buildEditor(
        initialValue: '- [ ] Task',
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) {
          toggledOffset = offset;
          handleCheckboxToggle(controller, offset);
        },
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isFalse, reason: 'starts in reading mode');

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      await tester.tapAt(checkboxTapPoint(tester, ro, slot));
      await settleSingleTap(tester);

      expect(toggledOffset, isNotNull,
          reason: 'tap must resolve to the checkbox');
      expect(controller.currentValue, '- [x] Task');
      expect(focusNode.hasFocus, isFalse,
          reason:
              'checkbox tap must not switch the note out of reading mode (#266)');
    });

    testWidgets(
        'tapping a checkbox while unfocused does not reveal the line as raw '
        'source — the checkbox glyph stays tappable immediately after (#335)',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '- [ ] Task',
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      await tester.tapAt(checkboxTapPoint(tester, ro, slot));
      await settleSingleTap(tester);

      // Re-fetch: the widget rebuilt with a new RenderModel after the toggle.
      final ro2 = renderEditorOf(tester);
      expect(ro2.renderModel.checkboxSlots, hasLength(1),
          reason: 'the line must still be a collapsed checkbox slot, not '
              'revealed raw markdown source');
      expect(ro2.renderModel.checkboxSlots.single.checked, isTrue);

      // Tappable again immediately, with no need to leave edit mode first.
      await tester.tapAt(
          checkboxTapPoint(tester, ro2, ro2.renderModel.checkboxSlots.single));
      await settleSingleTap(tester);
      expect(controller.currentValue, '- [ ] Task');
    });

    testWidgets(
        'tapping a checkbox lower in a long note does not scroll the note or '
        'move the cursor (#266)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      final lines = List.generate(60, (i) => 'line $i filler text');
      lines.add('- [ ] Task near the bottom');
      final source = lines.join('\n');
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;

      // Scroll the checkbox into view first — it starts off-screen this far
      // down a 60+-line document.
      final scrollable = scrollableOf(tester);
      final targetY =
          ro.getOffsetForCaret(TextPosition(offset: slot.element.start)).dy +
              ro.localPadding.top;
      final desired =
          (targetY - 150).clamp(0.0, scrollable.position.maxScrollExtent);
      scrollable.position.jumpTo(desired);
      await tester.pump();

      final scrollBefore = scrollable.position.pixels;
      final selectionBefore = controller.selectionForTesting;

      final roAfterScroll = renderEditorOf(tester);
      final slotAfterScroll = roAfterScroll.renderModel.checkboxSlots.single;
      await tester
          .tapAt(checkboxTapPoint(tester, roAfterScroll, slotAfterScroll));
      await settleSingleTap(tester);

      expect(controller.currentValue, contains('- [x] Task'),
          reason: 'sanity check: the tap must actually land on the checkbox '
              'and toggle it, or the assertions below are vacuous');
      expect(scrollable.position.pixels, scrollBefore,
          reason: 'checkbox tap must not scroll the note (#266)');
      expect(controller.selectionForTesting, selectionBefore,
          reason: 'checkbox tap must not move the cursor (#266)');
    });
  });

  group('Checkbox tap in edit mode does not disrupt the cursor', () {
    testWidgets(
        'tapping a checkbox while already focused, with the cursor on a '
        'different line, leaves the cursor and focus untouched',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = 'first line\n- [ ] Task\nthird line';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();

      // Put the cursor on the third line, away from the checkbox.
      final thirdLineOffset = source.indexOf('third line') + 3;
      controller.setSelectionForTesting(
          TextSelection.collapsed(offset: thirdLineOffset));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      await tester.tapAt(checkboxTapPoint(tester, ro, slot));
      await settleSingleTap(tester);

      expect(focusNode.hasFocus, isTrue,
          reason: 'must not disrupt an already-active edit session');
      expect(controller.selectionForTesting.baseOffset, thirdLineOffset,
          reason: 'cursor must stay exactly where it was');
      expect(controller.currentValue, contains('- [x] Task'));
    });
  });

  group('Long-press / double-tap selection is reading-mode-safe (#336)', () {
    testWidgets(
        'long-pressing a word while unfocused selects it without opening the '
        'keyboard, and the selection stays visible', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = 'hello world this is a test line for tapping';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);

      final ro = renderEditorOf(tester);
      final pos =
          globalPositionForSourceOffset(tester, ro, source.indexOf('world'));
      await tester.longPressAt(pos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final sel = controller.selectionForTesting;
      expect(sel.isCollapsed, isFalse,
          reason: 'a real word selection must have been created');
      expect(sel.textInside(source), 'world');
      expect(focusNode.hasFocus, isFalse,
          reason: 'selecting text while unfocused must not open the keyboard');
    });

    testWidgets(
        'double-tapping a word while unfocused selects it without opening '
        'the keyboard', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = 'hello world this is a test line for tapping';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);

      final ro = renderEditorOf(tester);
      final pos =
          globalPositionForSourceOffset(tester, ro, source.indexOf('world'));
      await doubleTapAt(tester, pos);

      final sel = controller.selectionForTesting;
      expect(sel.isCollapsed, isFalse,
          reason: 'a real word selection must have been created');
      expect(sel.textInside(source), 'world');
      expect(focusNode.hasFocus, isFalse,
          reason: 'selecting text while unfocused must not open the keyboard');
    });

    testWidgets(
        'long-pressing whitespace (no entity to select) while unfocused '
        'still falls through to normal tap-to-edit behaviour', (tester) async {
      // Explicit non-regression check: the reading-mode-safety fix must only
      // suppress focus for a GENUINE selection, not for the pre-existing
      // fallback where a long-press lands on nothing selectable and behaves
      // like a plain cursor-placing tap.
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      // Three spaces, not one: _selectEntityAt's _findEnclosingMatch treats
      // a tap immediately adjacent to a word's boundary as "on" that word
      // (confirmed while writing this test — targeting the single space in
      // 'hello world' actually selected 'hello', since offset 5 sits exactly
      // at that match's end). The middle space of a 3-space gap is not
      // adjacent to either word, so it genuinely has no entity to select.
      const source = 'hello   world';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final middleSpaceOffset = source.indexOf('   ') + 1;
      final pos = globalPositionForSourceOffset(tester, ro, middleSpaceOffset);
      await tester.longPressAt(pos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.selectionForTesting.isCollapsed, isTrue);
      expect(focusNode.hasFocus, isTrue,
          reason:
              'a long-press with no entity to select behaves like a plain tap');
    });

    testWidgets(
        'long-pressing a word while already focused keeps editing focus '
        '(no unintended unfocus)', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = 'hello world this is a test line for tapping';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
      ));
      await tester.pump();
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      final ro = renderEditorOf(tester);
      final pos =
          globalPositionForSourceOffset(tester, ro, source.indexOf('world'));
      await tester.longPressAt(pos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.selectionForTesting.textInside(source), 'world');
      expect(focusNode.hasFocus, isTrue,
          reason: 'must not disrupt an already-active edit session');
    });
  });
}
