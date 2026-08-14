// Regression tests for #352 — the checkbox tap hit-test zone was sized to
// exactly match the painted glyph (`boxSize = lineHeight * 0.8`, zero
// margin), so tapping a checkbox to toggle it was extraordinarily hard to
// land precisely. `checkboxSourceOffsetForTap` hit-tests against
// `_checkboxLocalRect(slot)` — the same rect `paint()` draws the glyph
// within — with no separate, wider hit-test rect at all.
//
// ROUND 2 (this file): round 1 widened the hit-test rect to
// `[r.x - _listMarkerGutterWidth, r.x]` — the reserved list-marker gutter's
// own band. Device-tested and confirmed STILL broken, two ways: (1) a
// non-nested checkbox was still hard to hit — round 1's own design reasoning
// ("widen to fill the gutter") assumed the gutter had real free space beyond
// the box, but the box's tuned size (#267) already consumes nearly all of
// it, leaving only ~2px of real slack; (2) nested/indented checkboxes were
// reportedly not tappable at all. Root cause of (2), confirmed by reading
// `QuikiRenderEditor.performLayout`: `_RunLayout.x` (aliased `r.x` /
// `gutterRight` throughout this file, matching the production code's own
// naming) is an ABSOLUTE offset from this render object's own text origin —
// `run.indentLevel * _indentUnit + listGutter` — not stacked incrementally
// from a parent run's own x. So `r.x - _listMarkerGutterWidth` only reaches
// this ROW's true left edge (local x = 0, the same physical margin every run
// shares) when `indentLevel` is 0. For a nested run it leaves a dead zone
// `indentLevel * _indentUnit` pixels wide between the true row start and
// round 1's zone — a real positioning bug, not just "the same insufficient
// margin, worse at depth."
//
// The fix (per #352's restated, simpler requirement): the widened zone spans
// this row's true left edge (local x = 0 — always, regardless of nesting,
// per the above) through to content-start x (`r.x`) — not a fixed
// gutter-width constant. For a non-nested (indentLevel 0) checkbox this is
// numerically IDENTICAL to round 1's zone (content-start x IS the gutter
// width there), so this round does not change the top-level geometry further
// — the top-level zone was already anchored at the row's true left edge; a
// ~24px-wide target being still a little fiddly on-device is a separate,
// inherent limit this round does not attempt to further relitigate. What
// changes is the nested case: the zone now correctly reaches all the way to
// local x = 0 at any nesting depth, instead of stopping `indentLevel * 16`
// px short of it.
//
// This suite drives real simulated gestures (tester.tapAt), not
// programmatic controller mutation or a bare geometry call, for the same
// reason reading_mode_safety_test.dart does (see its own doc comment): a
// widened *data* range that a real tap never actually reaches would pass a
// synthetic test while leaving the reported bug exactly as bad as before.
// The one exception is the dedicated geometry-assertion group below, added
// specifically because round 1's own test asserted only "doesn't overlap a
// neighboring checkbox" and never the actual size/position of the widened
// zone — a real invariant, just not the one that mattered for the reported
// bug. This round asserts concrete zone bounds directly, in addition to
// (not instead of) the real-gesture tests.
//
// A SEPARATE bug was found while writing this round's nested-checkbox tests,
// confirmed by tracing the code (not guessed): `MdElement.start` for a
// checkbox kind is always the LINE's absolute start (`lineStart` in
// md_parser.dart) — for a non-nested checkbox that happens to be the same
// position as the marker's own '-' character (no leading whitespace), but
// for a NESTED checkbox it is `wsLen` characters BEFORE '-' (the leading
// indentation whitespace). `EditorScreen._onCheckboxToggle`
// (lib/features/editor/editor_screen.dart) read a fixed 6-character marker
// starting exactly at that offset and only recognized literal '- [ ] ' /
// '- [x] ' / '- [X] ' — for a nested item this read e.g. '  - [ ' (leading
// spaces included) instead, matched neither pattern, and silently returned
// without editing anything. This meant a NESTED checkbox did not visibly
// toggle in the shipped app EVEN WITH a perfectly targeted tap — independent
// of, and in addition to, the hit-test geometry bug this file's other fix
// addresses. Filed as #354 and FIXED in round 3, same branch: `handleCheckboxToggle`
// below now mirrors EditorScreen._onCheckboxToggle's whitespace-skip fix, so
// the nested "toggles it" tests below assert the real, full end-to-end
// toggle again (not just offset resolution, which is what round 2 was
// reduced to asserting while #354 was still open).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
///
/// Skips any leading whitespace before reading the 6-char marker (#354) —
/// see this file's header comment for the full finding. Kept in sync with
/// EditorScreen's real fix.
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

/// The widened checkbox hit-test zone's bounds for [slot], in LOCAL
/// (render-object-relative, no padding) coordinates — mirrors
/// `QuikiRenderEditor._checkboxHitTestRect` using only the render object's
/// public API, per this suite's existing black-box-geometry convention (see
/// block_indentation_test.dart's `checkboxTapPoint` for the same convention
/// applied to the painted box itself).
///
/// `left` is always `0.0`: the row's true left edge, local to this render
/// object's own text origin — the SAME physical margin at any nesting depth,
/// since `QuikiRenderEditor.performLayout` computes each run's `x` as an
/// absolute offset from that origin (`indentLevel * _indentUnit +
/// listGutter`), never stacked relative to a parent run's own x. This is the
/// crux of round 2's fix: round 1 anchored the left edge at
/// `caret.dx - 24.0` (the marker-gutter's own width), which only coincides
/// with the row's true left edge when `indentLevel` is 0.
///
/// `right` (`caret.dx`) is the run's own content-start x — the same anchor
/// `_checkboxLocalRect` uses as `gutterRight` (the checkbox marker renders as
/// zero characters, so `getOffsetForCaret` at the marker's source start
/// resolves to the first real content character's x). Top/bottom mirror
/// `_checkboxLocalRect`'s own vertical formula exactly, since the fix leaves
/// the vertical extent untouched — only the horizontal extent widens.
({double left, double right, double top, double bottom}) _zoneFor(
  QuikiRenderEditor ro,
  CheckboxSlot slot,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: slot.element.start));
  final lineHeight = ro.preferredLineHeight;
  final boxSize = lineHeight * 0.8;
  final boxTop = caret.dy + (lineHeight - boxSize) / 2 + lineHeight / 3;
  return (
    left: 0.0,
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

/// Converts a WIDGET-RELATIVE offset (the literal coordinate space
/// `QuikiEditorState._onTapDown`'s own `details.localPosition` is in, and
/// therefore the same space `tester.tapAt`'s target implies once converted
/// through `tester.getTopLeft`) directly to a GLOBAL screen offset — with NO
/// padding re-added, unlike [_toGlobal] above.
///
/// This is the coordinate space round 2's own tests never exercised (#352,
/// round 4's finding): [_toGlobal] takes a "local" offset that is already
/// TEXT-ORIGIN-relative (post `_padding.topLeft` subtraction, the space
/// `_checkboxHitTestRect` itself operates in) and re-adds padding to land on
/// screen — so its `local.dx = 0` case exercises `textOffset.dx = 0`, i.e.
/// round 2's own "row's true left edge", never `textOffset.dx =
/// -_padding.left`, the literal widget edge a real finger can actually
/// reach. This helper's `widgetLocal.dx = 0` case is the one that does.
Offset _toGlobalWidgetEdge(WidgetTester tester, Offset widgetLocal) {
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + widgetLocal;
}

/// [_zoneFor]'s bounds re-expressed in the same WIDGET-RELATIVE coordinate
/// space [_toGlobalWidgetEdge] targets — i.e. with [QuikiRenderEditor]'s own
/// [EdgeInsets] padding folded back in (`+ ro.localPadding.topLeft` on the Y
/// axis; the X axis is handled separately below since round 4 changes it).
///
/// `left` is `0.0` here too, but it means something different from
/// [_zoneFor]'s `left: 0.0`: this is the literal widget edge (round 4's
/// fix — `_checkboxHitTestRect`'s real left bound, `-_padding.left` in
/// text-origin-relative terms, becomes exactly `0.0` once padding is added
/// back to convert to widget-relative coordinates), not
/// text-origin-relative local x = 0 one layer further in (round 2's claim,
/// which — after round 4 — is no longer the zone's actual left edge, just a
/// point `_padding.left` pixels inside it).
({double left, double right, double top, double bottom}) _widgetZoneFor(
  QuikiRenderEditor ro,
  CheckboxSlot slot,
) {
  final z = _zoneFor(ro, slot);
  final pad = ro.localPadding;
  return (
    left: 0.0,
    right: z.right + pad.left,
    top: z.top + pad.top,
    bottom: z.bottom + pad.top,
  );
}

void main() {
  group('Checkbox tap zone geometry (#352, round 2) — explicit bounds', () {
    testWidgets(
        'a non-nested checkbox\'s widened zone left edge sits at this row\'s '
        'true left edge (local x = 0)', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(buildEditor(
        initialValue: '- [ ] Task',
        focusNode: focusNode,
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final zone = _zoneFor(ro, slot);

      expect(zone.left, 0.0,
          reason: 'the widened zone must reach this row\'s true left edge, '
              'not stop short of it');
    });

    testWidgets(
        'a nested checkbox\'s widened zone left edge ALSO sits at this '
        'row\'s true left edge (local x = 0) — the exact case round 1 got '
        'wrong', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(buildEditor(
        initialValue: '  - [ ] Nested',
        focusNode: focusNode,
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final zone = _zoneFor(ro, slot);

      expect(zone.left, 0.0,
          reason: 'a nested checkbox\'s widened zone must reach the SAME '
              'true left edge as a non-nested one — round 1 left a dead zone '
              '`indentLevel * 16px` wide here instead');
    });

    testWidgets(
        'a nested checkbox\'s widened zone is measurably WIDER than a '
        'non-nested one, by approximately the indent unit — proving the '
        'zone actually grows with nesting depth rather than staying '
        'gutter-sized', (tester) async {
      final focusNode1 = FocusNode();
      await tester.pumpWidget(buildEditor(
        initialValue: '- [ ] Task',
        focusNode: focusNode1,
      ));
      await tester.pump();
      final flatRo = renderEditorOf(tester);
      final flatZone =
          _zoneFor(flatRo, flatRo.renderModel.checkboxSlots.single);
      final flatWidth = flatZone.right - flatZone.left;

      final focusNode2 = FocusNode();
      await tester.pumpWidget(buildEditor(
        initialValue: '  - [ ] Nested',
        focusNode: focusNode2,
      ));
      await tester.pump();
      final nestedRo = renderEditorOf(tester);
      final nestedZone =
          _zoneFor(nestedRo, nestedRo.renderModel.checkboxSlots.single);
      final nestedWidth = nestedZone.right - nestedZone.left;

      // One indent level (_indentUnit = 16.0) wider, within a small
      // tolerance for the same sub-pixel font-metrics noise the rest of this
      // suite's geometry tests already tolerate.
      expect(nestedWidth, closeTo(flatWidth + 16.0, 1.0),
          reason: 'the nested zone must be wider than the flat zone by '
              'approximately one indent unit — a flat 24px-regardless-of-'
              'depth zone (round 1\'s actual behavior) would fail this');
    });
  });

  group('Checkbox tap zone is wider than the painted glyph (#352)', () {
    testWidgets(
        'tapping at the true start of the line — well left of the painted '
        'box, in space the old exact-glyph hit-test never covered — still '
        'toggles the checkbox', (tester) async {
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
      // 2px inside the zone's left edge — i.e. near local x = 0, the row's
      // own true start, far from the painted glyph's own left edge (glyph
      // left edge sits well to the right, at
      // `zone.right - _listMarkerContentGap - boxSize`).
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
      final firstSlot = slots
          .firstWhere((s) => s.element.start == source.indexOf('- [ ] First'));
      final secondSlot = slots
          .firstWhere((s) => s.element.start == source.indexOf('- [ ] Second'));

      // Tap 1px inside the second item's zone top edge — as close as
      // possible to the boundary with the first item's zone without
      // actually crossing into it.
      final secondZone = _zoneFor(ro, secondSlot);
      final tapLocal = Offset(
          (secondZone.left + secondZone.right) / 2, secondZone.top + 1.0);

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

  group(
      'Nested checkbox tap zone reaches the row\'s true left edge (#352, '
      'round 2)', () {
    testWidgets(
        'a nested checkbox: tapping at the true start of ITS row — indented '
        'rightward from the page\'s own left edge is irrelevant; this taps '
        'local x = 0, well left of the checkbox glyph itself — resolves to '
        'THIS checkbox\'s own source offset. This is the case round 1 '
        'completely missed', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      int? toggledOffset;
      await tester.pumpWidget(buildEditor(
        initialValue: '  - [ ] Nested',
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) {
          toggledOffset = offset;
          handleCheckboxToggle(controller, offset);
        },
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final zone = _zoneFor(ro, slot);
      // Sanity: this nested zone must actually start left of where round 1's
      // gutter-only zone would have (r.x - 24.0), proving the widened region
      // covers space round 1 left dead. Recomputed here from the same public
      // API `_zoneFor` uses, not the private constant, to stay black-box.
      final contentStartX = zone.right;
      expect(contentStartX - 24.0, greaterThan(zone.left + 1.0),
          reason: 'this nested checkbox\'s content-start x must sit '
              'meaningfully right of (round1-gutter-left-edge), i.e. round '
              '1\'s zone would have started well right of local x = 0 here — '
              'otherwise this test isn\'t exercising the nested case at all');

      final tapLocal = Offset(zone.left + 2.0, (zone.top + zone.bottom) / 2);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      // Proves both fixes together: the tap resolves to this checkbox's own
      // element.start (round 2's hit-test-geometry fix — the widened zone,
      // not just its computed bounds above, actually catches a real tap
      // gesture at the row's true left edge), AND that offset now produces
      // a real, visible toggle (round 3's #354 fix — handleCheckboxToggle
      // above now skips the leading indentation whitespace the same way
      // EditorScreen._onCheckboxToggle does).
      expect(toggledOffset, slot.element.start,
          reason: 'a tap at the true start of a NESTED checkbox\'s row must '
              'resolve to THIS checkbox\'s own source offset, even though it '
              'lands well left of round 1\'s gutter-only zone');
      expect(controller.currentValue, '  - [x] Nested',
          reason: 'the resolved offset must also produce a real toggle '
              '(#354) — not just resolve to the right position');
    });

    testWidgets(
        'a nested checkbox: tapping past its content-start x, on the '
        'visible text itself, does not toggle it', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '  - [ ] Nested',
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final zone = _zoneFor(ro, slot);
      final tapLocal = Offset(zone.right + 12.0, (zone.top + zone.bottom) / 2);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '  - [ ] Nested',
          reason: 'a tap clearly inside a nested checkbox\'s own text must '
              'not toggle it');
    });

    testWidgets(
        'two nested checkboxes on adjacent lines resolve independently — '
        'their widened zones (now reaching local x = 0) do not overlap '
        'vertically', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '  - [ ] First\n  - [ ] Second';
      int? toggledOffset;
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => toggledOffset = offset,
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slots = ro.renderModel.checkboxSlots;
      expect(slots, hasLength(2));
      // Sort by source position rather than matching via source.indexOf: a
      // checkbox slot's element.start is the LINE's absolute start (see this
      // file's header comment on the separate EditorScreen bug), which for
      // 'Second' is NOT the same offset source.indexOf('- [ ] Second') would
      // find (that finds the marker's own '-', two columns later than the
      // line's true start).
      final sorted = [...slots]
        ..sort((a, b) => a.element.start.compareTo(b.element.start));
      final firstSlot = sorted[0];
      final secondSlot = sorted[1];

      final firstZone = _zoneFor(ro, firstSlot);
      final secondZone = _zoneFor(ro, secondSlot);
      expect(firstZone.bottom, lessThanOrEqualTo(secondZone.top),
          reason: 'even after widening to local x = 0, the two nested '
              'checkboxes\' zones must not overlap vertically');

      final tapLocal = Offset(
          (secondZone.left + secondZone.right) / 2, secondZone.top + 1.0);
      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      expect(toggledOffset, secondSlot.element.start,
          reason: 'only the second nested item\'s own offset may resolve — '
              'proves the two widened zones stay independent even though '
              'both now reach local x = 0');
    });
  });

  group(
      'Nested checkbox zone does not collide with ancestor-level content '
      '(#352, round 2)', () {
    testWidgets(
        'a nested checkbox\'s widened zone, at its own row, has no '
        'ancestor-level content painted underneath it — a tap on the '
        'ancestor\'s own (different) row does not toggle the nested item',
        (tester) async {
      // 'parent' is a plain (non-checkbox) list item directly above a nested
      // checkbox — the realistic shape of the reported bug (a checklist
      // nested under a plain bullet). Each source line is its own layout
      // row/run in this editor (ADR-34) — 'parent' and the nested checkbox
      // occupy different, non-overlapping vertical bands, so nothing from
      // 'parent' is ever painted within the checkbox row's own Y range,
      // regardless of how far left this round's widened X range now reaches.
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = '- parent\n  - [ ] child';
      int? toggledOffset;
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => toggledOffset = offset,
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final zone = _zoneFor(ro, slot);

      // Tap at local x = 2 (deep in the widened zone) but at the PARENT
      // line's own Y (one line above the checkbox's zone top) — confirms a
      // tap in the same X column, on a different row, does not cross into
      // the checkbox's zone or toggle it.
      final parentRowY = zone.top - ro.preferredLineHeight;
      final tapLocal = Offset(zone.left + 2.0, parentRowY);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      expect(toggledOffset, isNull,
          reason: 'a tap on the ancestor\'s own row, even at the same local '
              'x the nested checkbox\'s widened zone now reaches, must not '
              'resolve to the child checkbox — the zones are Y-disjoint, not '
              'just X-bounded');
      expect(controller.currentValue, source,
          reason: 'no content change either way — the ancestor line has no '
              'checkbox of its own, so nothing should have toggled');

      // And confirm the nested checkbox's OWN zone still resolves, so the
      // test above is a real "different row" check, not a coincidence of the
      // checkbox being unreachable altogether.
      final tapChild = Offset(zone.left + 2.0, (zone.top + zone.bottom) / 2);
      await tester.tapAt(_toGlobal(tester, ro, tapChild));
      await settleSingleTap(tester);
      expect(toggledOffset, slot.element.start,
          reason: 'sanity check: the nested checkbox\'s own row must still '
              'resolve at the same local x — proves the prior negative '
              'result was a real Y-boundary check, not a broken tap helper');
    });
  });

  group(
      'Widened checkbox tap zone is still reading-mode-safe (#352, '
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

    testWidgets(
        'tapping at the true start of a NESTED checkbox\'s row while '
        'unfocused (reading mode) toggles it without requesting focus or '
        'opening the keyboard', (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '  - [ ] Nested',
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();
      expect(focusNode.hasFocus, isFalse, reason: 'starts in reading mode');

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final zone = _zoneFor(ro, slot);
      final tapLocal = Offset(zone.left + 2.0, (zone.top + zone.bottom) / 2);

      await tester.tapAt(_toGlobal(tester, ro, tapLocal));
      await settleSingleTap(tester);

      // Full end-to-end toggle now that #354 is fixed (handleCheckboxToggle
      // above mirrors EditorScreen._onCheckboxToggle's whitespace-skip fix).
      // The reading-mode safety property is independent of that fix either
      // way — the checkbox hit-test branch in QuikiEditorState._onTapDown
      // runs BEFORE any focus-related code and returns immediately once
      // checkboxSourceOffsetForTap resolves non-null, never reaching the
      // focus-request branch regardless of what the toggle callback then
      // does with that offset.
      expect(controller.currentValue, '  - [x] Nested',
          reason: 'sanity check: the tap must actually land on the nested '
              'checkbox\'s widened zone and toggle it, or the assertion '
              'below is vacuous');
      expect(focusNode.hasFocus, isFalse,
          reason: 'a nested checkbox tap anywhere in its widened zone must '
              'also stay on the reading-mode-safe path — this newly-reached '
              'zone is not exempt from #335/#266\'s fix');
    });
  });

  group(
      'Checkbox tap zone reaches the literal widget edge, not just '
      'text-origin-relative local x = 0 (#352, round 4)', () {
    testWidgets(
        'checkboxSourceOffsetForTap resolves a non-null offset at exactly '
        'widget-relative x = 0 — called directly against the production '
        'API (not through a gesture), so this asserts the real hit-test '
        'boundary rather than a value the test itself assumes', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(buildEditor(
        initialValue: '- [ ] Task',
        focusNode: focusNode,
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final widgetZone = _widgetZoneFor(ro, slot);
      final midY = (widgetZone.top + widgetZone.bottom) / 2;

      // The exact edge (widgetLocal.dx == 0): must resolve. This is the
      // literal coordinate checkboxSourceOffsetForTap receives as
      // `localPosition` when a real tap lands on the widget's own leftmost
      // pixel — round 2 left this returning null (textOffset.dx worked out
      // to -_padding.left there, outside its `[0, gutterRight)` rect).
      expect(
          ro.checkboxSourceOffsetForTap(Offset(0.0, midY)), slot.element.start,
          reason: 'a tap at the literal widget edge must resolve to this '
              'checkbox\'s own source offset');

      // Just past the edge (widgetLocal.dx == -0.5): not a reachable real
      // tap position (nothing renders left of the widget's own bounds), but
      // calling the API directly here proves the fixed left bound is
      // exactly `-_padding.left` in text-offset terms (== widget x = 0), not
      // some looser padding-plus-slop value that would happen to also cover
      // this out-of-bounds case.
      expect(ro.checkboxSourceOffsetForTap(Offset(-0.5, midY)), isNull,
          reason: 'the widened zone\'s left bound is exactly the widget '
              'edge, not wider than it');
    });

    testWidgets(
        'tapping at the literal left edge of the editor widget '
        '(localPosition.dx == 0, in the SAME coordinate space '
        'tester.tapAt targets, relative to the widget\'s own top-left — '
        'NOT _zoneFor\'s text-origin-relative local x = 0) toggles a '
        'non-nested checkbox', (tester) async {
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
      final widgetZone = _widgetZoneFor(ro, slot);
      // widgetLocal.dx = 0 is the literal widget edge -- round 2's own tests
      // tapped `zone.left + 2.0` through `_toGlobal`, which is text-origin
      // x = 2, i.e. widget-relative x = 2 + _padding.left (~14px in from the
      // real edge) -- never the true edge itself.
      final tapWidgetLocal =
          Offset(0.0, (widgetZone.top + widgetZone.bottom) / 2);

      await tester.tapAt(_toGlobalWidgetEdge(tester, tapWidgetLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '- [x] Task',
          reason: 'a tap at the literal widget edge (widgetLocal.dx == 0) '
              'must toggle the checkbox -- this is the exact tap position '
              '#352\'s latest device-test report describes ("the farthest '
              'left point actually reachable on screen")');
    });

    testWidgets(
        'tapping at the literal left edge of the editor widget '
        '(localPosition.dx == 0) toggles a NESTED checkbox too',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '  - [ ] Nested',
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      final slot = ro.renderModel.checkboxSlots.single;
      final widgetZone = _widgetZoneFor(ro, slot);
      final tapWidgetLocal =
          Offset(0.0, (widgetZone.top + widgetZone.bottom) / 2);

      await tester.tapAt(_toGlobalWidgetEdge(tester, tapWidgetLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '  - [x] Nested',
          reason: 'a tap at the literal widget edge must toggle a nested '
              'checkbox too -- padding sits outside every run regardless of '
              'nesting depth, so this widening is not nesting-dependent');
    });

    testWidgets(
        'tapping at the literal left edge of the editor widget, on a row '
        'with NO checkbox, does not toggle anything -- proves the widening '
        'is checkbox-specific, not a general padding hit-test change',
        (tester) async {
      final focusNode = FocusNode();
      final controller = MarkdownEditorController();
      const source = 'Just a paragraph, no checkbox here.';
      await tester.pumpWidget(buildEditor(
        initialValue: source,
        focusNode: focusNode,
        controller: controller,
        onCheckboxToggle: (offset) => handleCheckboxToggle(controller, offset),
      ));
      await tester.pump();

      final ro = renderEditorOf(tester);
      expect(ro.renderModel.checkboxSlots, isEmpty,
          reason: 'sanity check: this line must have no checkbox slot at '
              'all, or the negative result below would not prove anything');
      final lineHeight = ro.preferredLineHeight;
      final tapWidgetLocal = Offset(0.0, ro.localPadding.top + lineHeight / 2);

      await tester.tapAt(_toGlobalWidgetEdge(tester, tapWidgetLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, source,
          reason: 'a widget-edge tap on a checkbox-free row must not alter '
              'the document -- the widening only ever applies within '
              'checkboxSourceOffsetForTap\'s own loop over checkboxSlots, '
              'never as a blanket padding-is-tappable rule');
    });

    testWidgets(
        'tapping at the literal left edge of the editor widget while '
        'unfocused (reading mode) toggles the checkbox without requesting '
        'focus or opening the keyboard', (tester) async {
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
      final widgetZone = _widgetZoneFor(ro, slot);
      final tapWidgetLocal =
          Offset(0.0, (widgetZone.top + widgetZone.bottom) / 2);

      await tester.tapAt(_toGlobalWidgetEdge(tester, tapWidgetLocal));
      await settleSingleTap(tester);

      expect(controller.currentValue, '- [x] Task',
          reason: 'sanity check: the widget-edge tap must actually land on '
              'the widened zone and toggle it, or the assertion below is '
              'vacuous');
      expect(focusNode.hasFocus, isFalse,
          reason: 'a widget-edge checkbox tap must still stay on the '
              'reading-mode-safe path established by #335/#266 -- this '
              'newly-reached padding strip is not exempt either');
    });
  });
}
