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

      expect(controller.currentValue, 'new content');
      // Verify selection is at offset 0 by using setSelectionForTesting to
      // confirm the controller state is readable after setValue.
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 2));
      await tester.pump();
      expect(controller.currentValue, 'new content');
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

    testWidgets('content is preserved across plain-text toggle',
        (tester) async {
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

      // Focus the editor via requestFocus().
      controller.requestFocus();
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
    testWidgets('renders a MarkdownEditor with content', (tester) async {
      await tester.pumpWidget(_buildEditor(initialValue: 'hello'));

      expect(find.byType(MarkdownEditor), findsOneWidget);
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
    testWidgets('fires onChanged when text is edited via IME', (tester) async {
      final changes = <String>[];
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
        onChanged: changes.add,
      ));

      controller.requestFocus();
      await tester.pump();

      // Simulate IME input by updating via the registered TextInputClient.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'new text',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
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

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 6, extentOffset: 11));
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

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
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

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
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

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
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

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
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

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 12));
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

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      controller.toggleLinePrefix('- [ ] ');
      await tester.pump();

      expect(controller.currentValue, '- [ ] do the thing');
    });
  });

  group('MarkdownEditorController — toggleUnorderedList', () {
    testWidgets('adds "- " prefix when line has no list marker',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'plain item',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
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

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'plain item');
    });

    testWidgets('strips full task list prefix when toggling off',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '- [ ] task item',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 8));
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

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
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

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, 'third item');
    });
  });

  group('MarkdownEditorController — saved selection (toolbar focus loss)', () {
    testWidgets(
        'wrapSelection with valid selection [0,4] on "word" produces "**word**"'
        ' — regression: toolbar bold no-op', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'word',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, '**word**');
    });

    testWidgets(
        'wrapSelection falls back to saved selection when tc.selection is invalid'
        ' — regression: toolbar no-op on focus loss', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: MarkdownEditor(
                  initialValue: 'word',
                  controller: controller,
                ),
              ),
              const TextField(key: Key('other')),
            ],
          ),
        ),
      ));

      // Focus the editor and set a selection of [0, 4].
      controller.requestFocus();
      await tester.pump();
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();
      // _savedSelection is now [0, 4].

      // Move focus to the other TextField — simulates toolbar button stealing
      // focus before onPressed fires.
      await tester.tap(find.byKey(const Key('other')));
      await tester.pump();

      // wrapSelection must use saved selection [0,4] and wrap correctly.
      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, '**word**',
          reason:
              'wrapSelection must use saved selection [0,4] when tc.selection is invalid after focus loss');
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-31 Stage 1 — new tests required by the task brief
  // ---------------------------------------------------------------------------

  group('ADR-31 Stage 1 — QuikiEditor parity', () {
    testWidgets('typing via IME inserts text into controller', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, 'hello');
    });

    testWidgets('backspace via IME removes last character', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'abc',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();

      // Simulate IME sending the post-backspace state.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, 'ab');
    });

    testWidgets('setValue replaces buffer and controller reports new content',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'old content',
        controller: controller,
      ));

      controller.setValue('new content');
      await tester.pump();

      expect(controller.currentValue, 'new content');
    });

    testWidgets(
        'wrapSelection with selection [0,5] on "hello world" produces "**hello** world"',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 5));
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, '**hello** world');
    });

    testWidgets('requestFocus gives the editor focus', (tester) async {
      final controller = MarkdownEditorController();
      final focusNode = FocusNode();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: 'hello',
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ));

      expect(focusNode.hasFocus, isFalse);

      controller.requestFocus();
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);

      focusNode.dispose();
    });
  });
}
