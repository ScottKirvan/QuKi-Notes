import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

// Helper: pump the editor with a FormattingToolbar below it.
Future<MarkdownEditorController> pumpEditor(
  WidgetTester tester, {
  String initialValue = '',
}) async {
  final controller = MarkdownEditorController();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: MarkdownEditor(
              initialValue: initialValue,
              controller: controller,
            ),
          ),
          FormattingToolbar(controller: controller),
        ],
      ),
    ),
  ));
  await tester.pump();
  return controller;
}

// Helper: pump the editor with a FormattingToolbar constrained to
// [toolbarWidth], narrower than the combined width of its 10 buttons, so
// tests can exercise the horizontal-scroll behavior.
Future<MarkdownEditorController> pumpNarrowToolbar(
  WidgetTester tester, {
  String initialValue = '',
  double toolbarWidth = 250,
}) async {
  final controller = MarkdownEditorController();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MarkdownEditor(
              initialValue: initialValue,
              controller: controller,
            ),
          ),
          SizedBox(
            width: toolbarWidth,
            child: FormattingToolbar(controller: controller),
          ),
        ],
      ),
    ),
  ));
  await tester.pump();
  return controller;
}

void main() {
  group('wrapSelection', () {
    testWidgets('wraps selected text with bold markers', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'hello world');

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 6, extentOffset: 11));
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, 'hello **world**');
    });

    testWidgets('inserts markers at cursor when no selection', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'hello');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.wrapSelection('_', '_');
      await tester.pump();

      expect(controller.currentValue, 'hello__');
    });

    testWidgets('wraps with italic markers', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'word');

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      controller.wrapSelection('_', '_');
      await tester.pump();

      expect(controller.currentValue, '_word_');
    });

    testWidgets('wraps with strikethrough markers', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'word');

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      controller.wrapSelection('~~', '~~');
      await tester.pump();

      expect(controller.currentValue, '~~word~~');
    });
  });

  group('toggleLinePrefix', () {
    testWidgets('adds heading prefix when absent', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'my heading');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, '# my heading');
    });

    testWidgets('removes heading prefix when present', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '# my heading');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, 'my heading');
    });

    testWidgets('adds task prefix when absent', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'do the thing');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      controller.toggleLinePrefix('- [ ] ');
      await tester.pump();

      expect(controller.currentValue, '- [ ] do the thing');
    });

    testWidgets('removes task prefix when present', (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '- [ ] do the thing');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 8));
      await tester.pump();

      controller.toggleLinePrefix('- [ ] ');
      await tester.pump();

      expect(controller.currentValue, 'do the thing');
    });

    testWidgets('operates on the correct line in multi-line text',
        (tester) async {
      final controller = await pumpEditor(tester,
          initialValue: 'line one\nline two\nline three');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 12));
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, 'line one\n# line two\nline three');
    });
  });

  group('list auto-continue', () {
    testWidgets('Enter after "- item" produces "- " on next line',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      controller.requestFocus();
      await tester.pump();

      // Simulate IME setting "- item".
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- item',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();

      // Simulate IME appending newline.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- item\n',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, '- item\n- ');
    });

    testWidgets('Enter after "- [ ] item" produces "- [ ] " on next line',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- [ ] item',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- [ ] item\n',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, '- [ ] item\n- [ ] ');
    });

    testWidgets(
        'Enter after "- [x] item" produces unchecked "- [ ] " on next line',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- [x] item',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- [x] item\n',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, '- [x] item\n- [ ] ');
    });

    testWidgets('Enter on empty "- " line exits the list', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- item',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- item\n',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.pump();
      expect(controller.currentValue, '- item\n- ');

      // Simulate adding another newline on the auto-continued empty "- ".
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- item\n- \n',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, '- item\n\n');
    });

    // -------------------------------------------------------------------
    // Indentation-preserving continuation (ADR-34 Stage 2+3): pressing
    // Enter after an indented list item must continue at the SAME
    // indentation, not reset to column 0.
    // -------------------------------------------------------------------

    testWidgets(
        'Enter after an indented "  - item" preserves the 2-space indent '
        'on the continuation line', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  - item',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  - item\n',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, '  - item\n  - ');
    });

    testWidgets(
        'Enter after an indented checkbox item preserves indentation and '
        'resets to unchecked', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  - [x] item',
          selection: TextSelection.collapsed(offset: 12),
        ),
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  - [x] item\n',
          selection: TextSelection.collapsed(offset: 13),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, '  - [x] item\n  - [ ] ');
    });

    testWidgets(
        'Enter after an indented ordered item preserves indentation and '
        'increments the number', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  1. item',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  1. item\n',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, '  1. item\n  2. ');
    });

    testWidgets(
        'Enter on an empty indented list item exits the list, dropping the '
        "line's indentation too", (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  - item',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  - item\n',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();
      expect(controller.currentValue, '  - item\n  - ');

      // Enter again on the now-empty, still-indented continuation line.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '  - item\n  - \n',
          selection: TextSelection.collapsed(offset: 14),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, '  - item\n\n');
    });
  });

  group('toggleUnorderedList', () {
    testWidgets('adds "- " prefix when line has no list marker',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'plain item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, '- plain item');
    });

    testWidgets('removes "- " prefix when already present', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '- plain item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'plain item');
    });

    testWidgets(
        'converts a task-list marker to a bullet, not a full strip'
        ' — regression: toggleUnorderedList previously treated checkbox as'
        ' "same family" and stripped it entirely instead of converting',
        (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '- [ ] task item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 8));
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, '- task item');
    });

    testWidgets('removes "* " prefix when present', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '* asterisk');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'asterisk');
    });
  });

  group('toggleOrderedList', () {
    testWidgets('adds "1. " prefix when line has no ordered marker',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'first item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, '1. first item');
    });

    testWidgets('removes ordered prefix regardless of number', (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '3. third item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, 'third item');
    });

    testWidgets('removes multi-digit ordered prefix', (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '10. tenth item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, 'tenth item');
    });
  });

  group('FormattingToolbar widget', () {
    testWidgets('renders all toolbar buttons', (tester) async {
      await pumpEditor(tester);

      expect(find.byIcon(LucideIcons.bold), findsOneWidget);
      expect(find.byIcon(LucideIcons.italic), findsOneWidget);
      expect(find.byIcon(LucideIcons.strikethrough), findsOneWidget);
      expect(find.byIcon(LucideIcons.code), findsOneWidget);
      expect(find.byIcon(LucideIcons.list), findsOneWidget);
      expect(find.byIcon(LucideIcons.listOrdered), findsOneWidget);
      expect(find.byIcon(LucideIcons.heading1), findsOneWidget);
      expect(find.byIcon(LucideIcons.listChecks), findsOneWidget);
      expect(find.byIcon(LucideIcons.indentIncrease), findsOneWidget);
      expect(find.byIcon(LucideIcons.indentDecrease), findsOneWidget);
    });

    testWidgets('tapping bold button wraps cursor text with **',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'bold me');

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 7));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.bold));
      await tester.pump();

      expect(controller.currentValue, '**bold me**');
    });

    testWidgets('tapping heading button toggles # prefix', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'a heading');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.heading1));
      await tester.pump();

      expect(controller.currentValue, '# a heading');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.heading1));
      await tester.pump();

      expect(controller.currentValue, 'a heading');
    });

    testWidgets('tapping checklist button toggles - [ ]  prefix',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'task item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.listChecks));
      await tester.pump();

      expect(controller.currentValue, '- [ ] task item');
    });

    testWidgets('tapping list button toggles unordered prefix', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'an item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.list));
      await tester.pump();

      expect(controller.currentValue, '- an item');
    });

    testWidgets('tapping listOrdered button toggles ordered prefix',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'an item');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.listOrdered));
      await tester.pump();

      expect(controller.currentValue, '1. an item');
    });

    testWidgets('tapping italic button wraps cursor text with _',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'word');

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.italic));
      await tester.pump();

      expect(controller.currentValue, '_word_');
    });

    testWidgets('tapping strikethrough button wraps cursor text with ~~',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'word');

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.strikethrough));
      await tester.pump();

      expect(controller.currentValue, '~~word~~');
    });

    testWidgets('tapping code button wraps cursor text with `', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'word');

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.code));
      await tester.pump();

      expect(controller.currentValue, '`word`');
    });

    testWidgets('tapping indentIncrease button indents the current line',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'hello world');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.indentIncrease));
      await tester.pump();

      expect(controller.currentValue, '\thello world');
    });

    testWidgets('tapping indentDecrease button dedents the current line',
        (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '\thello world');

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 6));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.indentDecrease));
      await tester.pump();

      expect(controller.currentValue, 'hello world');
    });
  });

  group('FormattingToolbar horizontal scroll', () {
    testWidgets(
        'on a viewport wide enough for all buttons, the toolbar does not '
        'scroll and buttons start flush at the left edge', (tester) async {
      await pumpEditor(tester); // default test viewport is 800x600.

      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(FormattingToolbar),
          matching: find.byType(Scrollable),
        ),
      );

      // Nothing to scroll: all 10 buttons already fit in 800 logical px.
      expect(scrollable.position.maxScrollExtent, 0);
      expect(scrollable.position.pixels, 0);

      // Flush left, same as the pre-fix bare Row — no leading padding
      // introduced by the new scroll container. Compared against the
      // *button's* own position, not the icon glyph's — IconButton has an
      // inherent ~12px inset between its tap-target box and the glyph
      // inside it, unrelated to this fix, so comparing the glyph directly
      // to the toolbar's edge would fail even with zero added padding.
      final firstButton = find.ancestor(
        of: find.byIcon(LucideIcons.bold),
        matching: find.byType(IconButton),
      );
      final firstButtonLeft = tester.getTopLeft(firstButton);
      final toolbarLeft = tester.getTopLeft(find.byType(FormattingToolbar));
      expect(firstButtonLeft.dx, toolbarLeft.dx);

      // The toolbar box itself is still exactly 44 logical px tall.
      final toolbarSize = tester.getSize(find.byType(FormattingToolbar));
      expect(toolbarSize.height, 44);
    });

    testWidgets(
        'on a narrow viewport, a button that overflows becomes reachable '
        'and tappable after a horizontal drag', (tester) async {
      const toolbarWidth = 250.0;
      final controller = await pumpNarrowToolbar(
        tester,
        initialValue: '\thello world',
        toolbarWidth: toolbarWidth,
      );

      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(FormattingToolbar),
          matching: find.byType(Scrollable),
        ),
      );

      // The 10th button (Dedent) does not fit in 250 logical px alongside
      // the other 9, so there is real overflow to scroll through.
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      final dedentFinder = find.byIcon(LucideIcons.indentDecrease);
      final beforeDrag = tester.getTopLeft(dedentFinder);
      expect(beforeDrag.dx, greaterThan(toolbarWidth));

      // Drag the toolbar content leftward to reveal the overflowed button.
      await tester.drag(find.byType(FormattingToolbar), const Offset(-400, 0));
      await tester.pumpAndSettle();

      final afterDrag = tester.getTopLeft(dedentFinder);
      expect(afterDrag.dx, lessThan(toolbarWidth));
      expect(afterDrag.dx, greaterThanOrEqualTo(0));

      // Now reachable: tapping it produces its existing, correct behavior.
      await tester.tap(dedentFinder);
      await tester.pump();

      expect(controller.currentValue, 'hello world');
    });
  });
}
