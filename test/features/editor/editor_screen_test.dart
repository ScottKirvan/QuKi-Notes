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

  Widget buildEditor({String? initialBody}) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: EditorScreen(initialBody: initialBody),
        ),
      );

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  group('EditorScreen snackbar durations', () {
    testWidgets('empty-body guard snackbar has duration ≤ 3s', (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      // Open hamburger menu then tap Send...
      // Use pump with a fixed duration instead of pumpAndSettle — the editor's
      // periodic auto-save timer prevents pumpAndSettle from ever settling.
      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send...'));
      await tester.pump();

      expect(
        find.text('Nothing to toss — write something first.'),
        findsOneWidget,
      );
      final snackBar = tester.firstWidget<SnackBar>(
        find.ancestor(
          of: find.text('Nothing to toss — write something first.'),
          matching: find.byType(SnackBar),
        ),
      );
      expect(snackBar.duration.inSeconds, lessThanOrEqualTo(3));

      await cleanup(tester);
    });
  });

  group('EditorScreen navigation', () {
    testWidgets('root editor shows QuKis icon and hamburger, no back button',
        (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      expect(find.byIcon(LucideIcons.fileStack), findsOneWidget);
      expect(find.byIcon(LucideIcons.menu), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      await cleanup(tester);
    });

    testWidgets('editor opened with qukiId shows back button, no hamburger',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => const EditorScreen(qukiId: 'test-id'),
                  ),
                ),
                child: const Text('Push'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Push'));
      // Pump enough frames for the push animation to complete without
      // waiting for the editor's periodic auto-save timer to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);
      expect(find.byIcon(LucideIcons.menu), findsNothing);

      await cleanup(tester);
    });

    testWidgets('hamburger menu contains Send..., QuKis, Settings',
        (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Send...'), findsOneWidget);
      expect(find.text('QuKis'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await cleanup(tester);
    });
  });
}
