import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

// Helper: pump the editor with an initial value and return the controller.
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

      // Select "world"
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

      // Collapsed cursor at end
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
      // Put cursor on "line two" (e.g. offset 12)
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

      // Simulate pressing Enter
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

      // First Enter: auto-continue creates "- item\n- "
      await tester.enterText(find.byType(TextField), '- item');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '- item\n');
      await tester.pump();
      expect(controller.currentValue, '- item\n- ');

      // Second Enter on empty "- " line: list exit removes the prefix.
      await tester.enterText(find.byType(TextField), '- item\n- \n');
      await tester.pump();

      expect(controller.currentValue, '- item\n\n');
    });
  });

  group('dismissKeyboard', () {
    testWidgets('unfocuses the internal FocusNode', (tester) async {
      final controller = MarkdownEditorController();
      final focusSpy = FocusNode();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: '',
            controller: controller,
            focusNode: focusSpy,
            autofocus: true,
          ),
        ),
      ));
      await tester.pump();

      // Confirm focus is held
      expect(focusSpy.hasFocus, isTrue);

      controller.dismissKeyboard();
      await tester.pump();

      expect(focusSpy.hasFocus, isFalse);

      focusSpy.dispose();
    });
  });

  group('FormattingToolbar widget', () {
    testWidgets('renders bold/italic/strikethrough/heading/checklist buttons',
        (tester) async {
      await pumpEditor(tester);

      expect(find.byIcon(Icons.format_bold), findsOneWidget);
      expect(find.byIcon(Icons.format_italic), findsOneWidget);
      expect(find.byIcon(Icons.format_strikethrough), findsOneWidget);
      expect(find.byIcon(Icons.title), findsOneWidget);
      expect(find.byIcon(Icons.checklist), findsOneWidget);
    });

    testWidgets('tapping bold button wraps cursor text with **',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'bold me');

      // Select all text
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 7);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pump();

      expect(controller.currentValue, '**bold me**');
    });

    testWidgets('tapping heading button toggles # prefix', (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'a heading');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.title));
      await tester.pump();

      expect(controller.currentValue, '# a heading');

      await tester.tap(find.byIcon(Icons.title));
      await tester.pump();

      expect(controller.currentValue, 'a heading');
    });

    testWidgets('tapping checklist button toggles - [ ]  prefix',
        (tester) async {
      final controller = await pumpEditor(tester, initialValue: 'task item');

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pump();

      expect(controller.currentValue, '- [ ] task item');
    });
  });
}
