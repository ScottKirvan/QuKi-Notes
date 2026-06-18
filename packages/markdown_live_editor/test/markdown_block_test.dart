import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

Widget _buildBlock({
  required String content,
  ValueChanged<String>? onChanged,
  ValueChanged<TextEditingController>? onFocused,
  VoidCallback? onUnfocused,
  VoidCallback? onMergeWithPrevious,
  VoidCallback? onEnterAtEnd,
  bool autofocus = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MarkdownBlock(
        content: content,
        onChanged: onChanged ?? (_) {},
        config: const MarkdownEditorConfig(),
        onFocused: onFocused,
        onUnfocused: onUnfocused,
        onMergeWithPrevious: onMergeWithPrevious,
        onEnterAtEnd: onEnterAtEnd,
        autofocus: autofocus,
      ),
    ),
  );
}

void main() {
  group('MarkdownBlock render mode', () {
    testWidgets('shows MarkdownBody and no TextField initially',
        (tester) async {
      await tester.pumpWidget(_buildBlock(content: 'hello'));

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('tapping enters edit mode (TextField appears)', (tester) async {
      await tester.pumpWidget(_buildBlock(content: 'hello'));

      await tester.tap(find.byType(MarkdownBody));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);
    });
  });

  group('MarkdownBlock edit mode', () {
    testWidgets('unfocusing exits edit mode (MarkdownBody reappears)',
        (tester) async {
      await tester.pumpWidget(_buildBlock(content: 'hello'));

      // Enter edit mode.
      await tester.tap(find.byType(MarkdownBody));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);

      // Remove focus to exit edit mode.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('onChanged fires when text is edited', (tester) async {
      final changes = <String>[];

      await tester.pumpWidget(_buildBlock(
        content: '',
        onChanged: changes.add,
      ));

      await tester.tap(find.byType(MarkdownBody));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'typed');
      await tester.pump();

      expect(changes, contains('typed'));
    });

    testWidgets('onFocused fires with the block TextEditingController',
        (tester) async {
      TextEditingController? capturedController;

      await tester.pumpWidget(_buildBlock(
        content: 'hello',
        onFocused: (tc) => capturedController = tc,
      ));

      await tester.tap(find.byType(MarkdownBody));
      await tester.pump();

      expect(capturedController, isNotNull);
      expect(capturedController!.text, 'hello');
    });

    testWidgets('onUnfocused fires when focus is lost', (tester) async {
      var unfocusedCalled = false;

      await tester.pumpWidget(_buildBlock(
        content: 'hello',
        onUnfocused: () => unfocusedCalled = true,
      ));

      await tester.tap(find.byType(MarkdownBody));
      await tester.pump();

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(unfocusedCalled, isTrue);
    });
  });

  group('MarkdownBlock keyboard callbacks', () {
    testWidgets(
        'onEnterAtEnd fires when Enter pressed at end of non-list block',
        (tester) async {
      var enterAtEndCalled = false;

      await tester.pumpWidget(_buildBlock(
        content: 'hello',
        onEnterAtEnd: () => enterAtEndCalled = true,
      ));

      await tester.tap(find.byType(MarkdownBody));
      await tester.pump();

      // Move cursor to end.
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          TextSelection.collapsed(offset: tf.controller!.text.length);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(enterAtEndCalled, isTrue);
    });

    testWidgets('onMergeWithPrevious fires on Backspace at position 0',
        (tester) async {
      var mergeCalled = false;

      await tester.pumpWidget(_buildBlock(
        content: 'hello',
        onMergeWithPrevious: () => mergeCalled = true,
      ));

      await tester.tap(find.byType(MarkdownBody));
      await tester.pump();

      // Move cursor to start.
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(mergeCalled, isTrue);
    });

    testWidgets('onEnterAtEnd does NOT fire for list blocks', (tester) async {
      var enterAtEndCalled = false;

      await tester.pumpWidget(_buildBlock(
        content: '- list item',
        onEnterAtEnd: () => enterAtEndCalled = true,
      ));

      await tester.tap(find.byType(MarkdownBody));
      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.selection =
          TextSelection.collapsed(offset: tf.controller!.text.length);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(enterAtEndCalled, isFalse);
    });
  });

  group('MarkdownBlock autofocus', () {
    testWidgets('autofocus: true enters edit mode on first build',
        (tester) async {
      await tester.pumpWidget(_buildBlock(
        content: 'hello',
        autofocus: true,
      ));
      await tester.pump(); // postFrameCallback fires

      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
