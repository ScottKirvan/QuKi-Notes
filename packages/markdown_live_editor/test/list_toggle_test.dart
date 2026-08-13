import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

// Regression coverage for the list-toggle-button unification.
//
// Before this fix, toggleUnorderedList/toggleOrderedList/the checkbox
// toolbar button (which reused the generic toggleLinePrefix('- [ ] ')) each
// had their own inconsistent detection:
//   - toggleUnorderedList recognized both ul and checkbox markers, but only
//     ever stripped them (no convert to a different type).
//   - toggleOrderedList recognized only ordered markers — clicking it on a
//     "- item" line produced "1. - item" (stacked, not converted).
//   - the checkbox button (toggleLinePrefix('- [ ] ')) recognized only the
//     exact literal "- [ ] " prefix — clicking it on a "- item" line
//     produced "- [ ] - item" (also stacked).
//   - None of the three regexes allowed for leading whitespace, so nested
//     list items (ADR-34) were not recognized as having a marker at all.
//
// Every test below places the cursor immediately after the marker (or,
// for the "no marker" cases, immediately after any leading indentation) —
// i.e. at the boundary between marker and content — so the expected
// resulting offset is always simply (leading-whitespace length) + (new
// marker length).

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
  int selectionOffset,
) async {
  final controller = MarkdownEditorController();
  await tester.pumpWidget(_buildEditor(initialValue, controller));
  controller
      .setSelectionForTesting(TextSelection.collapsed(offset: selectionOffset));
  await tester.pump();
  return controller;
}

void main() {
  group('toggleUnorderedList — unified detection', () {
    testWidgets('removes "- " marker when already unordered (non-indented)',
        (tester) async {
      final controller = await _pump(tester, '- item', 2);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, 'item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 0));
    });

    testWidgets('removes "- " marker when already unordered (indented)',
        (tester) async {
      final controller = await _pump(tester, '  - item', 4);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, '  item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 2));
    });

    testWidgets('converts ordered to unordered (non-indented)', (tester) async {
      final controller = await _pump(tester, '3. item', 3);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, '- item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 2));
    });

    testWidgets('converts ordered to unordered (indented)', (tester) async {
      final controller = await _pump(tester, '  3. item', 5);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, '  - item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 4));
    });

    testWidgets('converts checkbox to unordered (non-indented)',
        (tester) async {
      final controller = await _pump(tester, '- [ ] item', 6);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, '- item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 2));
    });

    testWidgets('converts checkbox to unordered (indented)', (tester) async {
      final controller = await _pump(tester, '  - [ ] item', 8);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, '  - item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 4));
    });

    testWidgets('adds "- " marker after no marker (non-indented)',
        (tester) async {
      final controller = await _pump(tester, 'item', 0);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, '- item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 2));
    });

    testWidgets('adds "- " marker after leading indentation, no marker',
        (tester) async {
      final controller = await _pump(tester, '  item', 2);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, '  - item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 4));
    });
  });

  group('toggleOrderedList — unified detection', () {
    testWidgets('removes ordered marker when already ordered (non-indented)',
        (tester) async {
      final controller = await _pump(tester, '3. item', 3);
      controller.toggleOrderedList();
      await tester.pump();
      expect(controller.currentValue, 'item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 0));
    });

    testWidgets('removes ordered marker when already ordered (indented)',
        (tester) async {
      final controller = await _pump(tester, '  3. item', 5);
      controller.toggleOrderedList();
      await tester.pump();
      expect(controller.currentValue, '  item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 2));
    });

    testWidgets('converts unordered to ordered (non-indented)', (tester) async {
      final controller = await _pump(tester, '- item', 2);
      controller.toggleOrderedList();
      await tester.pump();
      expect(controller.currentValue, '1. item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 3));
    });

    testWidgets('converts unordered to ordered (indented)', (tester) async {
      final controller = await _pump(tester, '  - item', 4);
      controller.toggleOrderedList();
      await tester.pump();
      expect(controller.currentValue, '  1. item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 5));
    });

    testWidgets('converts checkbox to ordered (non-indented)', (tester) async {
      final controller = await _pump(tester, '- [ ] item', 6);
      controller.toggleOrderedList();
      await tester.pump();
      expect(controller.currentValue, '1. item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 3));
    });

    testWidgets('converts checkbox to ordered (indented)', (tester) async {
      final controller = await _pump(tester, '  - [ ] item', 8);
      controller.toggleOrderedList();
      await tester.pump();
      expect(controller.currentValue, '  1. item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 5));
    });

    testWidgets('adds "1. " marker after no marker (non-indented)',
        (tester) async {
      final controller = await _pump(tester, 'item', 0);
      controller.toggleOrderedList();
      await tester.pump();
      expect(controller.currentValue, '1. item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 3));
    });

    testWidgets('adds "1. " marker after leading indentation, no marker',
        (tester) async {
      final controller = await _pump(tester, '  item', 2);
      controller.toggleOrderedList();
      await tester.pump();
      expect(controller.currentValue, '  1. item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 5));
    });
  });

  group('toggleCheckboxList — unified detection', () {
    testWidgets('removes checkbox marker when already checkbox (non-indented)',
        (tester) async {
      final controller = await _pump(tester, '- [ ] item', 6);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, 'item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 0));
    });

    testWidgets('removes checkbox marker when already checkbox (indented)',
        (tester) async {
      final controller = await _pump(tester, '  - [ ] item', 8);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, '  item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 2));
    });

    testWidgets('converts unordered to checkbox (non-indented)',
        (tester) async {
      final controller = await _pump(tester, '- item', 2);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, '- [ ] item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 6));
    });

    testWidgets('converts unordered to checkbox (indented)', (tester) async {
      final controller = await _pump(tester, '  - item', 4);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, '  - [ ] item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 8));
    });

    testWidgets('converts ordered to checkbox (non-indented)', (tester) async {
      final controller = await _pump(tester, '3. item', 3);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, '- [ ] item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 6));
    });

    testWidgets('converts ordered to checkbox (indented)', (tester) async {
      final controller = await _pump(tester, '  3. item', 5);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, '  - [ ] item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 8));
    });

    testWidgets('adds "- [ ] " marker after no marker (non-indented)',
        (tester) async {
      final controller = await _pump(tester, 'item', 0);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, '- [ ] item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 6));
    });

    testWidgets('adds "- [ ] " marker after leading indentation, no marker',
        (tester) async {
      final controller = await _pump(tester, '  item', 2);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, '  - [ ] item');
      expect(controller.selectionForTesting,
          const TextSelection.collapsed(offset: 8));
    });
  });

  group('checked-checkbox marker variants', () {
    testWidgets('recognizes lowercase "- [x] " as checkbox for removal',
        (tester) async {
      final controller = await _pump(tester, '- [x] item', 6);
      controller.toggleCheckboxList();
      await tester.pump();
      expect(controller.currentValue, 'item');
    });

    testWidgets('recognizes uppercase "- [X] " as checkbox for conversion',
        (tester) async {
      final controller = await _pump(tester, '- [X] item', 6);
      controller.toggleUnorderedList();
      await tester.pump();
      expect(controller.currentValue, '- item');
    });
  });

  group('heading toggle unaffected by list-toggle unification', () {
    testWidgets(
        'toggleLinePrefix("# ") still adds/removes heading exactly as before',
        (tester) async {
      final controller = await _pump(tester, 'my heading', 5);
      controller.toggleLinePrefix('# ');
      await tester.pump();
      expect(controller.currentValue, '# my heading');

      controller.toggleLinePrefix('# ');
      await tester.pump();
      expect(controller.currentValue, 'my heading');
    });

    testWidgets(
        'toggleLinePrefix("# ") on a bullet line still stacks (unchanged, out of scope)',
        (tester) async {
      final controller = await _pump(tester, '- item', 0);
      controller.toggleLinePrefix('# ');
      await tester.pump();
      expect(controller.currentValue, '# - item');
    });
  });
}
