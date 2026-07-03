import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

// Helper: pump the editor with a FormattingToolbar below it.
// The single-buffer architecture always has exactly one TextField available.
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

void main() {
  group('wrapSelection', () {
    testWidgets('wraps selected text with bold markers', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'hello world');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          const TextSelection(baseOffset: 6, extentOffset: 11);
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, 'hello **world**');
    });

    testWidgets('inserts markers at cursor when no selection', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'hello');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.wrapSelection('_', '_');
      await tester.pump();

      expect(controller.currentValue, 'hello__');
    });

    testWidgets('wraps with italic markers', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'word');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();

      controller.wrapSelection('_', '_');
      await tester.pump();

      expect(controller.currentValue, '_word_');
    });

    testWidgets('wraps with strikethrough markers', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'word');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();

      controller.wrapSelection('~~', '~~');
      await tester.pump();

      expect(controller.currentValue, '~~word~~');
    });
  });

  group('toggleLinePrefix', () {
    testWidgets('adds heading prefix when absent', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'my heading');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, '# my heading');
    });

    testWidgets('removes heading prefix when present', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '# my heading');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, 'my heading');
    });

    testWidgets('adds task prefix when absent', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'do the thing');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      controller.toggleLinePrefix('- [ ] ');
      await tester.pump();

      expect(controller.currentValue, '- [ ] do the thing');
    });

    testWidgets('removes task prefix when present', (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '- [ ] do the thing');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();

      controller.toggleLinePrefix('- [ ] ');
      await tester.pump();

      expect(controller.currentValue, 'do the thing');
    });

    testWidgets('operates on the correct line in multi-line text',
        (tester) async {
      final controller = await pumpEditor(tester,
          initialValue: 'line one\nline two\nline three');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 12);
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

      await tester.enterText(find.byType(TextField), '- item');
      await tester.pump();

      await tester.enterText(find.byType(TextField), '- item\n');
      await tester.pump();

      expect(controller.currentValue, '- item\n- ');
    });

    testWidgets('Enter after "- [ ] item" produces "- [ ] " on next line',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      await tester.enterText(find.byType(TextField), '- [ ] item');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '- [ ] item\n');
      await tester.pump();

      expect(controller.currentValue, '- [ ] item\n- [ ] ');
    });

    testWidgets(
        'Enter after "- [x] item" produces unchecked "- [ ] " on next line',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      await tester.enterText(find.byType(TextField), '- [x] item');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '- [x] item\n');
      await tester.pump();

      expect(controller.currentValue, '- [x] item\n- [ ] ');
    });

    testWidgets('Enter on empty "- " line exits the list', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '');

      await tester.enterText(find.byType(TextField), '- item');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '- item\n');
      await tester.pump();
      expect(controller.currentValue, '- item\n- ');

      await tester.enterText(find.byType(TextField), '- item\n- \n');
      await tester.pump();

      expect(controller.currentValue, '- item\n\n');
    });
  });

  group('toggleUnorderedList', () {
    testWidgets('adds "- " prefix when line has no list marker',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'plain item');
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, '- plain item');
    });

    testWidgets('removes "- " prefix when already present', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '- plain item');
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'plain item');
    });

    testWidgets('strips full task list prefix when toggling off',
        (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '- [ ] task item');
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'task item');
    });

    testWidgets('removes "* " prefix when present', (tester) async {
      final controller = await pumpEditor(tester, initialValue: '* asterisk');
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 3);
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
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, '1. first item');
    });

    testWidgets('removes ordered prefix regardless of number', (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '3. third item');
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, 'third item');
    });

    testWidgets('removes multi-digit ordered prefix', (tester) async {
      final controller =
          await pumpEditor(tester, initialValue: '10. tenth item');
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
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
      expect(find.byIcon(LucideIcons.list), findsOneWidget);
      expect(find.byIcon(LucideIcons.listOrdered), findsOneWidget);
      expect(find.byIcon(LucideIcons.heading1), findsOneWidget);
      expect(find.byIcon(LucideIcons.listChecks), findsOneWidget);
    });

    testWidgets('tapping bold button wraps cursor text with **',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'bold me');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 7);
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.bold));
      await tester.pump();

      expect(controller.currentValue, '**bold me**');
    });

    testWidgets('tapping heading button toggles # prefix', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'a heading');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.heading1));
      await tester.pump();

      expect(controller.currentValue, '# a heading');

      await tester.tap(find.byIcon(LucideIcons.heading1));
      await tester.pump();

      expect(controller.currentValue, 'a heading');
    });

    testWidgets('tapping checklist button toggles - [ ]  prefix',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'task item');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.listChecks));
      await tester.pump();

      expect(controller.currentValue, '- [ ] task item');
    });

    testWidgets('tapping list button toggles unordered prefix', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'an item');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.list));
      await tester.pump();

      expect(controller.currentValue, '- an item');
    });

    testWidgets('tapping listOrdered button toggles ordered prefix',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'an item');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.listOrdered));
      await tester.pump();

      expect(controller.currentValue, '1. an item');
    });
  });
}
