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
  void Function(String, String)? onSplit,
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
        onSplit: onSplit,
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

    testWidgets(
        'bare list/heading marker renders without throwing (flutter_markdown regression)',
        (tester) async {
      // A line such as "- [ ] " (empty task item) was crashing flutter_markdown
      // with '_inlines.isEmpty': is not true.  A zero-width space is appended
      // so the parser has one inline while the marker (checkbox/bullet) still
      // renders visually.
      await tester.pumpWidget(_buildBlock(content: '- [ ] '));
      expect(find.byType(MarkdownBody), findsOneWidget);

      await tester.pumpWidget(_buildBlock(content: '- '));
      expect(find.byType(MarkdownBody), findsOneWidget);

      await tester.pumpWidget(_buildBlock(content: '1. '));
      expect(find.byType(MarkdownBody), findsOneWidget);
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
        autofocus: true,
      ));

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

    testWidgets('onSplit fires with correct before/after when Enter is pressed',
        (tester) async {
      String? splitBefore;
      String? splitAfter;

      await tester.pumpWidget(_buildBlock(
        content: 'hello',
        autofocus: true,
        onSplit: (b, a) {
          splitBefore = b;
          splitAfter = a;
        },
      ));
      await tester.pump();

      // Simulate Enter at end by setting text with newline via controller.
      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.text = 'hello\n';
      await tester.pump();

      expect(splitBefore, 'hello');
      expect(splitAfter, '');
    });

    testWidgets('onSplit with list prefix continues list on next block',
        (tester) async {
      String? splitAfter;

      await tester.pumpWidget(_buildBlock(
        content: '- item',
        autofocus: true,
        onSplit: (_, a) => splitAfter = a,
      ));
      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.text = '- item\n';
      await tester.pump();

      expect(splitAfter, '- ');
    });

    testWidgets('onSplit exits list when Enter on empty list item',
        (tester) async {
      String? splitBefore;

      await tester.pumpWidget(_buildBlock(
        content: '- ',
        autofocus: true,
        onSplit: (b, _) => splitBefore = b,
      ));
      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      tf.controller!.text = '- \n';
      await tester.pump();

      expect(splitBefore, '');
    });
  });

  group('MarkdownBlock autofocus', () {
    testWidgets('autofocus: true shows TextField on the very first frame',
        (tester) async {
      await tester.pumpWidget(_buildBlock(
        content: 'hello',
        autofocus: true,
      ));
      // No pump needed — _editing starts true, TextField is in first build.
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
