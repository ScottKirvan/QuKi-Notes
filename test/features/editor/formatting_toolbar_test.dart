import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

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
        'keyboard toggle shows keyboardOff when editor has focus — '
        'regression: button was static keyboardOff regardless of focus state (#78)',
        (tester) async {
      await pumpEditor(tester);
      // Post-frame focus request fires after initState.
      await tester.pump();

      // Editor should be focused — toggle shows keyboardOff.
      expect(find.byIcon(LucideIcons.keyboardOff), findsOneWidget);
      expect(find.byIcon(LucideIcons.keyboard), findsNothing);
      await cleanup(tester);
    });

    testWidgets(
        'keyboard toggle shows keyboard icon after unfocus — '
        'regression: button was static regardless of focus state (#78)',
        (tester) async {
      await pumpEditor(tester);
      await tester.pump(); // process post-frame focus request

      // Tap the keyboardOff button to unfocus.
      await tester.tap(find.byIcon(LucideIcons.keyboardOff));
      await tester.pump();

      // Now unfocused — toggle should show the keyboard (show) icon.
      expect(find.byIcon(LucideIcons.keyboard), findsOneWidget);
      expect(find.byIcon(LucideIcons.keyboardOff), findsNothing);
      await cleanup(tester);
    });
  });
}
