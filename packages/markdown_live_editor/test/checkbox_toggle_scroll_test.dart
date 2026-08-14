// Regression tests: toggling a checkbox must not scroll the viewport.
//
// Root cause, traced end to end: checkbox toggle ->
// EditorScreen._onCheckboxToggle -> MarkdownEditorController
// .setValuePreservingSelection() -> _MarkdownEditorState
// ._setValuePreservingSelection() sets the shared TextEditingController's
// .value directly. As a plain ChangeNotifier value assignment, that
// synchronously fires EVERY registered listener on the controller,
// including QuikiEditorState._onControllerChanged, which unconditionally
// scheduled a scroll-to-caret pass (_scheduleScrollToCaret) keyed off
// wherever the SELECTION happened to be left over from whatever editing
// happened before -- not the checkbox that was actually tapped. A checkbox
// tap never moves the selection (checkboxSourceOffsetForTap / the checkbox
// tap handler return without touching it), so the resulting jump had no
// connection at all to the tapped checkbox.
//
// Fixed via a `scrollToCaret` parameter on
// MarkdownEditorController.setValuePreservingSelection (default true,
// unchanged for every other existing caller) plus
// QuikiEditorState.suppressNextScrollToCaret() -- a one-shot flag armed
// immediately before the controller value mutation that would otherwise
// trigger the unwanted scroll, and consumed by the very
// _onControllerChanged call that mutation synchronously triggers. Every
// other value-change path (typing, IME edits, indent/dedent, paste, a
// programmatic QuKi switch) goes through QuikiEditorState._updateValue
// instead, which this flag does not touch -- the second test below is a
// non-regression check confirming that path still scrolls exactly as
// before.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Helpers -- self-contained per this suite's convention (see
// reading_mode_safety_test.dart's doc comment for the same rationale).
// ---------------------------------------------------------------------------

QuikiRenderEditor renderEditorOf(WidgetTester tester) =>
    tester.renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));

ScrollableState scrollableOf(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first);

/// Mirrors EditorScreen._onCheckboxToggle exactly, including the
/// `scrollToCaret: false` argument production now passes -- copied from
/// checkbox_hit_target_test.dart / reading_mode_safety_test.dart's
/// identically-named helper (kept in sync with the real fix).
void handleCheckboxToggle(
    MarkdownEditorController controller, int sourceOffset) {
  final current = controller.currentValue;
  if (sourceOffset < 0 || sourceOffset > current.length) return;
  var markerStart = sourceOffset;
  while (markerStart < current.length &&
      (current[markerStart] == ' ' || current[markerStart] == '\t')) {
    markerStart++;
  }
  if (markerStart + 6 > current.length) return;
  final marker = current.substring(markerStart, markerStart + 6);
  final String replacement;
  if (marker == '- [ ] ') {
    replacement = '- [x] ';
  } else if (marker == '- [x] ' || marker == '- [X] ') {
    replacement = '- [ ] ';
  } else {
    return;
  }
  final newText =
      current.replaceRange(markerStart, markerStart + 6, replacement);
  controller.setValuePreservingSelection(newText, scrollToCaret: false);
}

/// The global screen position of a checkbox glyph's actual painted box --
/// copied from reading_mode_safety_test.dart / marker_scoped_reveal_test
/// .dart's identically-named helper.
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
/// always has -- an onDoubleTapDown callback is unconditionally wired
/// alongside onTapDown, so onTapDown itself is deferred until
/// kDoubleTapTimeout has elapsed with no second tap.
Future<void> settleSingleTap(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

/// An 80-line document, tall enough to overflow a 300px viewport many times
/// over, with a single checkbox item near the very top (line 2) -- visible
/// without any scrolling -- and ordinary content filling the rest.
String _buildLongSource({int lines = 80}) => List.generate(
      lines,
      (i) => i == 2 ? '- [ ] task' : 'line $i alpha beta gamma delta',
    ).join('\n');

Future<QuikiRenderEditor> pumpTallDocument(
  WidgetTester tester, {
  required String source,
  required MarkdownEditorController controller,
  void Function(int sourceOffset)? onCheckboxToggle,
  double viewportHeight = 300,
}) async {
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    home: Scaffold(
      body: SizedBox(
        height: viewportHeight,
        child: MarkdownEditor(
          initialValue: source,
          controller: controller,
          onCheckboxToggle: onCheckboxToggle,
        ),
      ),
    ),
  ));
  await tester.pump();
  return renderEditorOf(tester);
}

void main() {
  group('Checkbox toggle does not scroll the viewport', () {
    testWidgets(
        'toggling a checkbox while the selection sits far below the '
        'visible viewport leaves the scroll offset unchanged', (tester) async {
      final source = _buildLongSource();
      final controller = MarkdownEditorController();
      final checkboxLineStart = source.indexOf('- [ ] task');

      final ro = await pumpTallDocument(
        tester,
        source: source,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      );

      // The selection sits far below the fold -- "wherever the selection
      // happens to be left over from whatever editing happened before,"
      // exactly the position the pre-fix scroll-to-caret pass would have
      // jumped toward on the very next controller value change.
      final farOffset = source.length - 5;
      controller
          .setSelectionForTesting(TextSelection.collapsed(offset: farOffset));
      await tester.pump();

      final scrollable = scrollableOf(tester);
      scrollable.position.jumpTo(0);
      await tester.pump();
      expect(scrollable.position.pixels, 0.0,
          reason: 'sanity check: viewport starts at the top, where the '
              'checkbox is visible');

      final slot = ro.renderModel.checkboxSlots
          .singleWhere((s) => s.element.start == checkboxLineStart);
      await tester.tapAt(checkboxTapPoint(tester, ro, slot));
      await settleSingleTap(tester);
      // Give any postFrameCallback-scheduled scroll jump a chance to run.
      await tester.pump();
      await tester.pump();

      expect(controller.currentValue, contains('- [x] task'),
          reason: 'sanity check: the tap actually landed on the checkbox '
              'and toggled it -- otherwise the assertion below is vacuous');
      expect(scrollableOf(tester).position.pixels, 0.0,
          reason: 'toggling the checkbox must not move the viewport, even '
              'though the (unmoved) selection sits far below the fold');
    });

    testWidgets(
        'a normal typing/IME edit in the same scrolled-away state still '
        'scrolls to keep the new caret position visible -- confirms the '
        'checkbox fix did not suppress scroll-to-caret globally',
        (tester) async {
      final source = _buildLongSource();
      final controller = MarkdownEditorController();

      await pumpTallDocument(
        tester,
        source: source,
        controller: controller,
      );

      final scrollable = scrollableOf(tester);
      scrollable.position.jumpTo(0);
      await tester.pump();
      expect(scrollable.position.pixels, 0.0);

      controller.requestFocus();
      await tester.pump();

      // Simulate the IME reporting a keystroke typed at the very end of the
      // document -- far below the fold from the current (top) scroll
      // position, exactly the kind of edit _updateValue's unconditional
      // _scheduleScrollToCaret() call exists to handle.
      final editedText = '${source}Z';
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: editedText,
          selection: TextSelection.collapsed(offset: editedText.length),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(controller.currentValue, editedText,
          reason: 'sanity check: the simulated IME edit actually landed');
      expect(scrollableOf(tester).position.pixels, greaterThan(0.0),
          reason: 'a real typing/IME edit must still scroll to keep the '
              'new caret position in view -- the checkbox-toggle fix must '
              'not have suppressed scroll-to-caret for this path too');
    });
  });
}
