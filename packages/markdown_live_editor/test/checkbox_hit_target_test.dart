// Regression tests for #352 — the checkbox tap hit-test zone was sized to
// exactly match the painted glyph (`boxSize = lineHeight * 0.8`, zero
// margin), so tapping a checkbox to toggle it was extraordinarily hard to
// land precisely. `checkboxSourceOffsetForTap` hit-tests against
// `_checkboxLocalRect(slot)` — the same rect `paint()` draws the glyph
// within — with no separate, wider hit-test rect at all.
//
// This suite drives real simulated gestures (tester.tapAt), not
// programmatic controller mutation or a bare geometry call, for the same
// reason reading_mode_safety_test.dart does (see its own doc comment): a
// widened *data* range that a real tap never actually reaches would pass a
// synthetic test while leaving the reported bug exactly as bad as before.
//
// Geometry constants here (`_listMarkerGutterWidth` = 24.0,
// `_listMarkerContentGap` = 4.0) are copied from QuikiRenderEditor's own
// private constants of the same name, mirroring the existing convention in
// block_indentation_test.dart / reading_mode_safety_test.dart of each test
// file keeping its own self-contained geometry helpers rather than sharing
// a helper module.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const double _listMarkerGutterWidth = 24.0;
const double _listMarkerContentGap = 4.0;

// A fresh Key per pumpWidget call forces a real unmount + remount rather
// than an in-place widget update — see notes/dev/testing.md's
// pumpWidget-reuse gotcha.
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

/// Settles the delayed single-tap resolution this editor's GestureDetector
/// always has — see reading_mode_safety_test.dart's identically-named
/// helper for the full explanation (an onDoubleTapDown callback is
/// unconditionally wired alongside onTapDown, so onTapDown itself is
/// deferred until kDoubleTapTimeout has elapsed with no second tap).
Future<void> settleSingleTap(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

/// Mirrors the checkbox-toggle logic in
/// lib/features/editor/editor_screen.dart's EditorScreen._onCheckboxToggle —
/// copied from reading_mode_safety_test.dart's identically-named helper.
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
  controller.setValuePreservingSelection(newText);
}

/// The widened checkbox hit-test zone's bounds for [slot], in LOCAL
/// (render-object-relative, no padding) coordinates.
///
/// `caret.dx` is the run's own content-start x — the same anchor
/// `_checkboxLocalRect` uses as `gutterRight` (the checkbox marker renders
/// as zero characters, so `getOffsetForCaret` at the marker's source start
/// resolves to the first real content character's x). Top/bottom mirror
/// `_checkboxLocalRect`'s own vertical formula exactly, since the fix
/// leaves the vertical extent untouched — only the horizontal extent widens.
({double left, double right, double top, double bottom}) _zoneFor(
  QuikiRenderEditor ro,
  CheckboxSlot slot,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: slot.element.start));
  final lineHeight = ro.preferredLineHeight;
  final boxSize = lineHeight * 0.8;
  final boxTop = caret.dy + (lineHeight - boxSize) / 2 + lineHeight / 3;
  return (
    left: caret.dx - _listMarkerGutterWidth,
    right: caret.dx,
    top: boxTop,
    bottom: boxTop + boxSize,
  );
}

/// Converts a LOCAL render-object-relative offset to a GLOBAL screen offset
/// suitable for tester.tapAt — same conversion reading_mode_safety_test.dart's
/// checkboxTapPoint performs, needed once the document can scroll (an
/// unconverted local offset only coincidentally lands correctly when the
/// render object's global origin is near (0, 0)).
Offset _toGlobal(WidgetTester tester, QuikiRenderEditor ro, Offset local) {
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) +
      local +
      ro.localPadding.topLeft;
}

void main() {
  group('Checkbox tap zone is wider than the painted glyph (#352)', () {
    testWidgets(
        'tapping near the left edge of the marker gutter — well left of the '
        'painted box, in space the old exact-glyph hit-test never covered — '
        'still toggles the checkbox', (tester) async {
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
      final zone = _zoneFor(ro, slot);
      // 2px inside the zone's left edge — deep in the gutter, far from the
      // painted glyph's own left edge (glyph left edge sits at
      // `zone.right - _listMarkerContentGap - boxSize`, well to the right
      // of `zone.left`).
      final tapLocal = Offset(zone.left + 2.0, (zone.top + zone.bottom) / 2);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '- [x] Task',
          reason: 'a tap 2px inside the widened zone\'s left edge must '
              'register as a checkbox toggle');
    });

    testWidgets(
        'tapping in the content gap between the box and the start of the '
        'text — previously dead hit-test space — still toggles the checkbox',
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
      final zone = _zoneFor(ro, slot);
      // 1px left of the zone's right edge (content-start x) — inside the
      // _listMarkerContentGap band the old rect excluded entirely.
      final tapLocal = Offset(zone.right - 1.0, (zone.top + zone.bottom) / 2);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '- [x] Task',
          reason: 'a tap 1px inside the widened zone\'s right edge (the '
              'content gap) must register as a checkbox toggle');
    });
  });

  group('Checkbox tap zone does not leak into adjacent content (#352)', () {
    testWidgets(
        'tapping mid-text, well past the content-start x, does not toggle '
        'the checkbox', (tester) async {
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
      final zone = _zoneFor(ro, slot);
      // 12px to the right of content-start x — squarely inside "Task"'s own
      // glyphs, not the widened zone.
      final tapLocal = Offset(zone.right + 12.0, (zone.top + zone.bottom) / 2);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '- [ ] Task',
          reason: 'a tap clearly inside the text must not toggle the '
              'checkbox');
    });

    testWidgets(
        'with two checklist items on adjacent lines, tapping inside one '
        'item\'s widened zone toggles only that item, not its neighbor',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '- [ ] First\n- [ ] Second';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slots = ro.renderModel.checkboxSlots;
      expect(slots, hasLength(2));
      final firstSlot =
          slots.firstWhere((s) => s.element.start == source.indexOf('- [ ] First'));
      final secondSlot =
          slots.firstWhere((s) => s.element.start == source.indexOf('- [ ] Second'));

      // Tap 1px inside the second item's zone top edge — as close as
      // possible to the boundary with the first item's zone without
      // actually crossing into it.
      final secondZone = _zoneFor(ro, secondSlot);
      final tapLocal =
          Offset((secondZone.left + secondZone.right) / 2, secondZone.top + 1.0);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '- [ ] First\n- [x] Second',
          reason: 'only the second item — the one actually tapped near — '
              'may toggle');

      // Sanity: the two zones don't overlap at all at this line spacing —
      // otherwise the assertion above would be trivially satisfiable by
      // either checkbox and wouldn't actually prove anything.
      final firstZone = _zoneFor(ro, firstSlot);
      expect(firstZone.bottom, lessThanOrEqualTo(secondZone.top),
          reason: 'the two checkboxes\' widened zones must not overlap at '
              'this line spacing, or this test would not be meaningful');
    });
  });

  group('Widened checkbox tap zone is still reading-mode-safe (#352, '
      'no regression on #335/#266)', () {
    testWidgets(
        'tapping near the widened zone\'s edge while unfocused (reading '
        'mode) toggles the checkbox without requesting focus or opening the '
        'keyboard', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '- [ ] Task',
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isFalse, reason: 'starts in reading mode');

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final zone = _zoneFor(ro, slot);
      // Same left-edge position as the first group's test above — deep in
      // the newly-widened gutter, not on the painted glyph itself.
      final tapLocal = Offset(zone.left + 2.0, (zone.top + zone.bottom) / 2);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '- [x] Task',
          reason: 'sanity check: the tap must actually land on the widened '
              'zone and toggle it, or the assertion below is vacuous');
      expect(focusNode.hasFocus, isFalse,
          reason: 'a checkbox tap anywhere in the widened zone must stay on '
              'the reading-mode-safe path established by #335/#266 — no '
              'focus request, regardless of where in the zone it lands');
    });
  });
}
