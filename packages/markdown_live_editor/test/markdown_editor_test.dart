import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

void main() {
  group('MarkdownEditorController', () {
    testWidgets('currentValue returns initialValue before any edits',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: 'hello world',
            controller: controller,
          ),
        ),
      ));

      expect(controller.currentValue, 'hello world');
    });

    testWidgets('setValue updates currentValue', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: '',
            controller: controller,
          ),
        ),
      ));

      controller.setValue('updated text');
      await tester.pump();

      expect(controller.currentValue, 'updated text');
    });

    testWidgets('setValue is a no-op when value is unchanged', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: 'same',
            controller: controller,
          ),
        ),
      ));

      controller.setValue('same');
      await tester.pump();

      expect(controller.currentValue, 'same');
    });

    test('plainTextMode defaults to false (block mode)', () {
      final controller = MarkdownEditorController();
      expect(controller.plainTextMode, isFalse);
    });

    testWidgets('togglePlainTextMode switches between block and plain-text',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: 'hello',
            controller: controller,
          ),
        ),
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

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: 'some text',
            controller: controller,
          ),
        ),
      ));

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.currentValue, 'some text');

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.currentValue, 'some text');
    });
  });

  group('MarkdownEditor onChanged', () {
    testWidgets('fires onChanged when text changes in plain-text mode',
        (tester) async {
      final controller = MarkdownEditorController();
      final changes = <String>[];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: '',
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      ));

      // Switch to plain-text mode so we can type into the single TextField.
      controller.togglePlainTextMode();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'new text');
      await tester.pump();

      expect(changes, contains('new text'));
    });

    testWidgets('does not fire onChanged on setValue (programmatic update)',
        (tester) async {
      final controller = MarkdownEditorController();
      final changes = <String>[];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: '',
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      ));

      controller.setValue('programmatic');
      await tester.pump();

      expect(changes, isEmpty);
    });
  });

  group('MarkdownEditor widget structure', () {
    testWidgets('renders MarkdownBlock widgets in block mode', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(initialValue: 'hello'),
        ),
      ));

      expect(find.byType(MarkdownBlock), findsOneWidget);
    });

    testWidgets('renders a single TextField in plain-text mode',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: '',
            controller: controller,
          ),
        ),
      ));

      controller.togglePlainTextMode();
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('controller detaches on dispose', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: 'before dispose',
            controller: controller,
          ),
        ),
      ));

      expect(controller.currentValue, 'before dispose');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(controller.currentValue, '');
    });
  });
}
