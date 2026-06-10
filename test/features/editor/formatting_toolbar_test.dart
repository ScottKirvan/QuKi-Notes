import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:super_editor/super_editor.dart';

import 'package:quki_notes/core/database/app_database.dart';
import 'package:quki_notes/core/database/database_provider.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  // Replaces the widget tree with a minimal widget and drains any pending
  // timers (e.g. drift stream-cleanup timers) left by ProviderScope disposal.
  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  group('FormattingToolbar', () {
    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: EditorScreen()),
        ),
      );
      await tester.pump();
    }

    test('toolbar button icons are defined', () {
      expect(LucideIcons.bold, isNotNull);
      expect(LucideIcons.italic, isNotNull);
      expect(LucideIcons.strikethrough, isNotNull);
      expect(LucideIcons.list, isNotNull);
      expect(LucideIcons.listOrdered, isNotNull);
      expect(LucideIcons.listChecks, isNotNull);
      expect(LucideIcons.link, isNotNull);
      expect(LucideIcons.keyboardOff, isNotNull);
      expect(LucideIcons.keyboard, isNotNull);
    });

    testWidgets(
        'renders all expected toolbar buttons — code button replaced by listChecks (#82)',
        (tester) async {
      await pumpEditor(tester);
      expect(find.byIcon(LucideIcons.bold), findsOneWidget);
      expect(find.byIcon(LucideIcons.italic), findsOneWidget);
      expect(find.byIcon(LucideIcons.strikethrough), findsOneWidget);
      expect(find.byIcon(LucideIcons.list), findsOneWidget);
      expect(find.byIcon(LucideIcons.listOrdered), findsOneWidget);
      // code button replaced by listChecks (#82)
      expect(find.byIcon(LucideIcons.code), findsNothing);
      expect(find.byIcon(LucideIcons.listChecks), findsOneWidget);
      expect(find.byIcon(LucideIcons.link), findsOneWidget);
      // keyboard dismiss button present (either icon depending on focus)
      expect(
        find.byIcon(LucideIcons.keyboardOff).evaluate().isNotEmpty ||
            find.byIcon(LucideIcons.keyboard).evaluate().isNotEmpty,
        isTrue,
      );
      await cleanup(tester);
    });

    testWidgets('link button shows stub snackbar', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(LucideIcons.link));
      await tester.pump();
      expect(find.text('Link formatting coming soon.'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets(
        'keyboard toggle shows keyboard icon at cold launch — '
        'regression: icon showed keyboardOff at launch because FocusNode.hasFocus '
        'was true even though IME keyboard was not visible (#post-96, #72)',
        (tester) async {
      await pumpEditor(tester);
      // Post-frame focus request fires after initState — FocusNode gets focus
      // but IME keyboard is not visible (#72 known issue). The icon should
      // reflect keyboard visibility, not focus state.
      await tester.pump();

      // At cold launch _keyboardVisible is false — shows "show keyboard" icon.
      expect(find.byIcon(LucideIcons.keyboard), findsOneWidget,
          reason:
              'At cold launch keyboard is not visible so the show-keyboard icon '
              'must be shown, not keyboardOff');
      expect(find.byIcon(LucideIcons.keyboardOff), findsNothing);
      await cleanup(tester);
    });

    testWidgets(
        'keyboard toggle shows keyboardOff after tapping show-keyboard — '
        'regression: icon state did not update after tapping (#78, #post-96)',
        (tester) async {
      await pumpEditor(tester);
      await tester.pump(); // process post-frame focus request

      // At cold launch the toolbar shows the keyboard (show) icon.
      expect(find.byIcon(LucideIcons.keyboard), findsOneWidget);

      // Tap "show keyboard" — sets _keyboardVisible = true.
      await tester.tap(find.byIcon(LucideIcons.keyboard));
      await tester.pump();

      // Now _keyboardVisible = true — toggle shows keyboardOff.
      expect(find.byIcon(LucideIcons.keyboardOff), findsOneWidget);
      expect(find.byIcon(LucideIcons.keyboard), findsNothing);
      await cleanup(tester);
    });

    testWidgets(
        'keyboard toggle shows keyboard icon after tapping keyboardOff — '
        'regression: button was static regardless of focus state (#78)',
        (tester) async {
      await pumpEditor(tester);
      await tester.pump(); // process post-frame focus request

      // Tap show-keyboard first to get into visible state.
      await tester.tap(find.byIcon(LucideIcons.keyboard));
      await tester.pump();
      expect(find.byIcon(LucideIcons.keyboardOff), findsOneWidget);

      // Tap dismiss — sets _keyboardVisible = false.
      await tester.tap(find.byIcon(LucideIcons.keyboardOff));
      await tester.pump();

      // Now _keyboardVisible = false — shows keyboard icon again.
      expect(find.byIcon(LucideIcons.keyboard), findsOneWidget);
      expect(find.byIcon(LucideIcons.keyboardOff), findsNothing);
      await cleanup(tester);
    });

    testWidgets(
        'format buttons (bold, italic, strikethrough, list, numbered list, task list) '
        'are disabled after keyboard is dismissed (selection cleared) — '
        'regression: buttons showed snackbar instead of being greyed out (#post-96, Bug 4)',
        (tester) async {
      await pumpEditor(tester);
      await tester.pump(); // let super_editor process focus → places initial cursor

      // Show keyboard first (tapping the keyboard icon sets _keyboardVisible=true).
      await tester.tap(find.byIcon(LucideIcons.keyboard));
      await tester.pump();

      // Dismiss keyboard — calls FocusScope.unfocus(), which clears
      // super_editor's composer.selection. Buttons should become disabled.
      await tester.tap(find.byIcon(LucideIcons.keyboardOff));
      await tester.pump();

      IconButton getButton(IconData icon) => tester.widget<IconButton>(
            find.ancestor(
              of: find.byIcon(icon),
              matching: find.byType(IconButton),
            ),
          );

      expect(getButton(LucideIcons.bold).onPressed, isNull,
          reason: 'bold must be disabled when selection is cleared by unfocus');
      expect(getButton(LucideIcons.italic).onPressed, isNull,
          reason: 'italic must be disabled when selection is cleared by unfocus');
      expect(getButton(LucideIcons.strikethrough).onPressed, isNull,
          reason: 'strikethrough must be disabled when selection is cleared by unfocus');
      expect(getButton(LucideIcons.list).onPressed, isNull,
          reason: 'bullet list must be disabled when selection is cleared by unfocus');
      expect(getButton(LucideIcons.listOrdered).onPressed, isNull,
          reason: 'numbered list must be disabled when selection is cleared by unfocus');
      expect(getButton(LucideIcons.listChecks).onPressed, isNull,
          reason: 'task list must be disabled when selection is cleared by unfocus');

      await cleanup(tester);
    });
  });

  group('FormattingToolbar task list insertion (#82, #post-96 Bug 5)', () {
    test(
        'TaskNode serializes to "- [ ] " (with space) in markdown — '
        'regression: InsertTextRequest-based approach produced "- []" missing '
        'the space between brackets (#82 regression, #post-96 Bug 5)', () {
      // This is a unit test of the serialization — the fix converts a paragraph
      // to TaskNode directly via ReplaceNodeRequest, bypassing the markdown
      // reaction pipeline. Verify that a TaskNode round-trips correctly.
      final document = MutableDocument(nodes: [
        TaskNode(id: 'task1', text: AttributedText('hello'), isComplete: false),
      ]);

      final markdown = serializeDocumentToMarkdown(
        document,
        syntax: MarkdownSyntax.normal,
      );

      expect(markdown, contains('- [ ] hello'),
          reason:
              'TaskNode must serialize to "- [ ] " (with space between brackets), '
              'not "- []" (#82 regression, #post-96 Bug 5)');
      expect(markdown, isNot(contains('- []')),
          reason:
              'Broken "- []" pattern must not appear in serialized markdown');
    });

    test('TaskNode (complete) serializes to "- [x] " in markdown', () {
      final document = MutableDocument(nodes: [
        TaskNode(id: 'task1', text: AttributedText('done'), isComplete: true),
      ]);

      final markdown = serializeDocumentToMarkdown(
        document,
        syntax: MarkdownSyntax.normal,
      );

      expect(markdown, contains('- [x] done'));
    });
  });
}
