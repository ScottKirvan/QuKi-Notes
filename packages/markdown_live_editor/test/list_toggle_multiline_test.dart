import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

// Multi-line generalization of toggleUnorderedList / toggleOrderedList /
// toggleCheckboxList (deliberately out of scope for the earlier
// fix/list-toggle-unify PR — list_toggle_test.dart covers the collapsed-
// selection/single-line case those buttons already handled).
//
// When the current selection spans multiple lines, each button now applies
// its existing per-line remove/convert/add rule (see list_toggle_test.dart's
// header comment for the rule itself) independently to EVERY line the
// selection touches, not just the line containing selection.baseOffset.
//
// Every expected resulting selection offset below was hand-derived from the
// exact per-line marker-length delta of each touched line — not guessed —
// so these assertions double as a check on the offset remapping, not just
// the resulting text.
//
// Heading lines are a deliberate, explicit exception: these are list-marker
// buttons, not general-purpose line-prefix buttons, and a heading line
// inside a multi-line selection is left completely untouched rather than
// treated as a bare/no-marker line to add a marker to. This is a real
// divergence from the pre-existing COLLAPSED-selection/single-line
// behavior of these same buttons, which has no such exclusion (verified
// directly against current `main` before writing these tests: placing the
// cursor on a lone "# Heading" line and calling toggleUnorderedList()
// produces "- # Heading", i.e. treats it as a bare line) — that single-line
// behavior is explicitly out of scope to change and is left exactly as-is;
// only the new multi-line path gets the heading exclusion.

Widget _buildEditor(String initialValue, MarkdownEditorController controller) {
  return MaterialApp(
    home: Scaffold(
      body: MarkdownEditor(
        initialValue: initialValue,
        controller: controller,
      ),
    ),
  );
}

Future<MarkdownEditorController> _pump(
  WidgetTester tester,
  String initialValue,
  TextSelection selection,
) async {
  final controller = MarkdownEditorController();
  await tester.pumpWidget(_buildEditor(initialValue, controller));
  controller.setSelectionForTesting(selection);
  await tester.pump();
  return controller;
}

void main() {
  group('toggleUnorderedList — multi-line selection', () {
    testWidgets('all touched lines already unordered — every marker removed',
        (tester) async {
      final controller = await _pump(
        tester,
        '- one\n- two\n- three',
        const TextSelection(baseOffset: 2, extentOffset: 15),
      );
      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'one\ntwo\nthree');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );
    });

    testWidgets(
        'all touched lines ordered (different type) — every marker converted',
        (tester) async {
      final controller = await _pump(
        tester,
        '1. one\n1. two\n1. three',
        const TextSelection(baseOffset: 3, extentOffset: 19),
      );
      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, '- one\n- two\n- three');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 2, extentOffset: 16),
      );
    });

    testWidgets(
        'mixed selection — same-type line removed, different-type line '
        'converted, no-marker line gets a marker added, each independently',
        (tester) async {
      final controller = await _pump(
        tester,
        '- alpha\n1. beta\ngamma',
        const TextSelection(baseOffset: 2, extentOffset: 18),
      );
      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'alpha\n- beta\n- gamma');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 0, extentOffset: 17),
      );
    });

    testWidgets(
        'a heading line inside the selection is left completely untouched'
        ' — not treated as a bare/no-marker line', (tester) async {
      final controller = await _pump(
        tester,
        '- item\n# Heading\n- other',
        const TextSelection(baseOffset: 2, extentOffset: 21),
      );
      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'item\n# Heading\nother');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 0, extentOffset: 17),
      );
    });
  });

  group('toggleOrderedList — multi-line selection', () {
    testWidgets('all touched lines already ordered — every marker removed',
        (tester) async {
      final controller = await _pump(
        tester,
        '1. one\n1. two\n1. three',
        const TextSelection(baseOffset: 3, extentOffset: 19),
      );
      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, 'one\ntwo\nthree');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 0, extentOffset: 10),
      );
    });

    testWidgets(
        'all touched lines checkbox (different type) — every marker converted',
        (tester) async {
      final controller = await _pump(
        tester,
        '- [ ] one\n- [ ] two\n- [ ] three',
        const TextSelection(baseOffset: 6, extentOffset: 28),
      );
      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, '1. one\n1. two\n1. three');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 3, extentOffset: 19),
      );
    });

    testWidgets(
        'indentation at different depths is preserved exactly for every '
        'line in the selection', (tester) async {
      final controller = await _pump(
        tester,
        '- top\n  - nested\n    - deeper',
        const TextSelection(baseOffset: 2, extentOffset: 25),
      );
      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, '1. top\n  1. nested\n    1. deeper');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 3, extentOffset: 28),
      );
    });

    testWidgets(
        'a heading line inside the selection is left completely untouched'
        ' — not treated as a bare/no-marker line', (tester) async {
      final controller = await _pump(
        tester,
        '- item\n# Heading\n- other',
        const TextSelection(baseOffset: 2, extentOffset: 21),
      );
      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, '1. item\n# Heading\n1. other');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 3, extentOffset: 23),
      );
    });
  });

  group('toggleCheckboxList — multi-line selection', () {
    testWidgets('all touched lines already checkbox — every marker removed',
        (tester) async {
      final controller = await _pump(
        tester,
        '- [ ] one\n- [ ] two\n- [ ] three',
        const TextSelection(baseOffset: 6, extentOffset: 28),
      );
      controller.toggleCheckboxList();
      await tester.pump();

      expect(controller.currentValue, 'one\ntwo\nthree');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 0, extentOffset: 10),
      );
    });

    testWidgets(
        'all touched lines unordered (different type) — every marker converted',
        (tester) async {
      final controller = await _pump(
        tester,
        '- one\n- two\n- three',
        const TextSelection(baseOffset: 2, extentOffset: 15),
      );
      controller.toggleCheckboxList();
      await tester.pump();

      expect(controller.currentValue, '- [ ] one\n- [ ] two\n- [ ] three');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 6, extentOffset: 27),
      );
    });

    testWidgets(
        'mixed selection — same-type line removed, different-type line '
        'converted, no-marker line gets a marker added, each independently',
        (tester) async {
      final controller = await _pump(
        tester,
        '- [ ] task\n1. plan\nnote',
        const TextSelection(baseOffset: 6, extentOffset: 21),
      );
      controller.toggleCheckboxList();
      await tester.pump();

      expect(controller.currentValue, 'task\n- [ ] plan\n- [ ] note');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 0, extentOffset: 24),
      );
    });

    testWidgets(
        'a heading line inside the selection is left completely untouched'
        ' — not treated as a bare/no-marker line', (tester) async {
      final controller = await _pump(
        tester,
        '- item\n# Heading\n- other',
        const TextSelection(baseOffset: 2, extentOffset: 21),
      );
      controller.toggleCheckboxList();
      await tester.pump();

      expect(controller.currentValue, '- [ ] item\n# Heading\n- [ ] other');
      expect(
        controller.selectionForTesting,
        const TextSelection(baseOffset: 6, extentOffset: 29),
      );
    });
  });
}
