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

    testWidgets('setValue updates the displayed text', (tester) async {
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
      expect(find.text('updated text'), findsOneWidget);
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

    test('plainTextMode is always true in Stage 1', () {
      final controller = MarkdownEditorController();
      expect(controller.plainTextMode, isTrue);
    });

    test('togglePlainTextMode is a no-op in Stage 1', () {
      final controller = MarkdownEditorController();
      controller.togglePlainTextMode();
      expect(controller.plainTextMode, isTrue);
    });
  });

  group('MarkdownEditor onChanged', () {
    testWidgets('fires onChanged when text changes', (tester) async {
      final changes = <String>[];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: '',
            onChanged: changes.add,
          ),
        ),
      ));

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

      // setValue uses TextEditingValue directly, bypassing onChanged.
      expect(changes, isEmpty);
    });
  });

  group('MarkdownEditor widget structure', () {
    testWidgets('renders a TextField', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(initialValue: ''),
        ),
      ));

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('TextField has null maxLines (unlimited)', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(initialValue: ''),
        ),
      ));

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.maxLines, isNull);
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

      // After dispose the state is detached — returns empty string.
      expect(controller.currentValue, '');
    });
  });
}
