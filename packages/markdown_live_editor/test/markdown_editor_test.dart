import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

Widget _buildEditor({
  required String initialValue,
  MarkdownEditorController? controller,
  ValueChanged<String>? onChanged,
  bool autofocus = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MarkdownEditor(
        initialValue: initialValue,
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
      ),
    ),
  );
}

void main() {
  group('MarkdownEditorController — currentValue', () {
    testWidgets('currentValue returns initialValue before any edits',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      expect(controller.currentValue, 'hello world');
    });

    testWidgets('currentValue returns empty string when no editor attached',
        (tester) async {
      final controller = MarkdownEditorController();
      expect(controller.currentValue, '');
    });
  });

  group('MarkdownEditorController — setValue', () {
    testWidgets('setValue updates currentValue', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
      ));

      controller.setValue('updated text');
      await tester.pump();

      expect(controller.currentValue, 'updated text');
    });

    testWidgets('setValue resets cursor to 0', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'abc',
        controller: controller,
      ));

      controller.setValue('new content');
      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller!.selection.baseOffset, 0);
    });

    testWidgets('setValue is safe when value is unchanged', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'same',
        controller: controller,
      ));

      controller.setValue('same');
      await tester.pump();

      expect(controller.currentValue, 'same');
    });
  });

  group('MarkdownEditorController — plainTextMode', () {
    test('plainTextMode defaults to false', () {
      final controller = MarkdownEditorController();
      expect(controller.plainTextMode, isFalse);
    });

    testWidgets('togglePlainTextMode switches between styled and raw',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      expect(controller.plainTextMode, isFalse);

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.plainTextMode, isTrue);

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.plainTextMode, isFalse);
    });

    testWidgets('content is preserved across plain-text toggle', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'some text',
        controller: controller,
      ));

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.currentValue, 'some text');

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.currentValue, 'some text');
    });
  });

  group('MarkdownEditorController — hasActiveBlock', () {
    test('hasActiveBlock is false when no editor is attached', () {
      final controller = MarkdownEditorController();
      expect(controller.hasActiveBlock, isFalse);
    });

    testWidgets('hasActiveBlock reflects FocusNode.hasFocus', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      // No focus yet.
      expect(controller.hasActiveBlock, isFalse);

      // Tap to focus the TextField.
      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(controller.hasActiveBlock, isTrue);
    });

    testWidgets('focusFirstBlock focuses the editor', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      expect(controller.hasActiveBlock, isFalse);

      controller.focusFirstBlock();
      await tester.pump();

      expect(controller.hasActiveBlock, isTrue);
    });

    testWidgets('requestFocus focuses the editor', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();

      expect(controller.hasActiveBlock, isTrue);
    });
  });

  group('MarkdownEditor — widget structure', () {
    testWidgets('renders a single TextField in all modes', (tester) async {
      await tester.pumpWidget(_buildEditor(initialValue: 'hello'));

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('controller detaches on dispose', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'before dispose',
        controller: controller,
      ));

      expect(controller.currentValue, 'before dispose');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(controller.currentValue, '');
    });
  });

  group('MarkdownEditor — onChanged', () {
    testWidgets('fires onChanged when text is edited', (tester) async {
      final changes = <String>[];

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        onChanged: changes.add,
      ));

      await tester.enterText(find.byType(TextField), 'new text');
      await tester.pump();

      expect(changes, contains('new text'));
    });

    testWidgets('does not fire onChanged on setValue (programmatic update)',
        (tester) async {
      final controller = MarkdownEditorController();
      final changes = <String>[];

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
        onChanged: changes.add,
      ));

      controller.setValue('programmatic');
      await tester.pump();

      expect(changes, isEmpty);
    });
  });

  group('MarkdownEditorController — wrapSelection', () {
    testWidgets('wraps selected text with bold markers', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          const TextSelection(baseOffset: 6, extentOffset: 11);
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, 'hello **world**');
    });

    testWidgets('inserts markers at cursor when no selection', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.wrapSelection('_', '_');
      await tester.pump();

      expect(controller.currentValue, 'hello__');
    });

    testWidgets('wraps with strikethrough markers', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'word',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();

      controller.wrapSelection('~~', '~~');
      await tester.pump();

      expect(controller.currentValue, '~~word~~');
    });
  });

  group('MarkdownEditorController — toggleLinePrefix', () {
    testWidgets('adds heading prefix when absent', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'my heading',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, '# my heading');
    });

    testWidgets('removes heading prefix when present', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '# my heading',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, 'my heading');
    });

    testWidgets('operates on the correct line in multi-line text',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'line one\nline two\nline three',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 12);
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, 'line one\n# line two\nline three');
    });

    testWidgets('adds task prefix when absent', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'do the thing',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      controller.toggleLinePrefix('- [ ] ');
      await tester.pump();

      expect(controller.currentValue, '- [ ] do the thing');
    });
  });

  group('MarkdownEditorController — toggleUnorderedList', () {
    testWidgets('adds "- " prefix when line has no list marker', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'plain item',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, '- plain item');
    });

    testWidgets('removes "- " prefix when already present', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '- plain item',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'plain item');
    });

    testWidgets('strips full task list prefix when toggling off', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '- [ ] task item',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 8);
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'task item');
    });
  });

  group('MarkdownEditorController — toggleOrderedList', () {
    testWidgets('adds "1. " prefix when line has no ordered marker',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'first item',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, '1. first item');
    });

    testWidgets('removes ordered prefix regardless of number', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '3. third item',
        controller: controller,
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, 'third item');
    });
  });

  group('MarkdownEditorController — saved selection (toolbar focus loss)',
      () {
    testWidgets(
        'wrapSelection with valid selection [0,4] on "word" produces "**word**"'
        ' — regression: toolbar bold no-op', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'word',
        controller: controller,
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, '**word**');
      // Cursor should be at offset 8 (end of '**word**').
      expect(tf.controller!.selection.baseOffset, 8);
    });

    testWidgets(
        'wrapSelection falls back to saved selection when tc.selection is invalid'
        ' — regression: toolbar no-op on focus loss', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'word',
        controller: controller,
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final tf = tester.widget<TextField>(find.byType(TextField));
      // Set a valid selection [0, 4] so _savedSelection is populated.
      tf.controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();

      // Directly set the controller to an invalid selection, simulating what
      // Flutter does when the toolbar button steals focus before onPressed fires.
      tf.controller!.selection = const TextSelection.collapsed(offset: -1);
      await tester.pump();

      // Before fix: wrapSelection calls `if (!sel.isValid) return` → no-op.
      // After fix: wrapSelection uses _savedSelection [0,4] → wraps correctly.
      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, '**word**',
          reason:
              'wrapSelection must use saved selection [0,4] when tc.selection is invalid');
    });
  });
}
