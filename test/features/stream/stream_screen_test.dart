import 'dart:io' show Platform;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:quki_notes/core/database/app_database.dart';
import 'package:quki_notes/core/database/database_provider.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';
import 'package:quki_notes/features/stream/stream_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildUnderTest() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: StreamScreen()),
      );

  // Unmounts the widget tree inside fake_async so drift's 0ms cleanup
  // timer fires before the test framework's invariant check.
  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> insertQuki(
    AppDatabase db, {
    required String id,
    String body = '',
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    final now = DateTime.now();
    return db.qukisDao.insertQuki(QukisCompanion.insert(
      id: id,
      body: Value(body),
      createdAt: createdAt ?? now,
      modifiedAt: modifiedAt ?? now,
    ));
  }

  group('StreamScreen', () {
    testWidgets('shows empty-state message when no QuKis', (tester) async {
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      expect(find.textContaining('No QuKis yet'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('shows QuKi preview text in list', (tester) async {
      await insertQuki(db, id: const Uuid().v4(), body: 'Hello world');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      expect(find.text('Hello world'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('strips markdown heading markers from preview', (tester) async {
      await insertQuki(db, id: const Uuid().v4(), body: '## My heading');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      expect(find.text('My heading'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('shows (empty) for blank body', (tester) async {
      await insertQuki(db, id: const Uuid().v4(), body: '');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      expect(find.text('(empty)'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('lists newest QuKi first', (tester) async {
      final older = DateTime(2026, 1, 1);
      final newer = DateTime(2026, 1, 2);
      await insertQuki(db,
          id: 'a', body: 'Older note', createdAt: older, modifiedAt: older);
      await insertQuki(db,
          id: 'b', body: 'Newer note', createdAt: newer, modifiedAt: newer);
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      final titles = tiles
          .map((t) => (t.title as Text).data)
          .where((s) => s != null)
          .toList();
      expect(titles.first, 'Newer note');
      expect(titles.last, 'Older note');
      await cleanup(tester);
    });

    testWidgets('swipe to delete soft-deletes the QuKi', (tester) async {
      const id = 'del-test';
      await insertQuki(db, id: id, body: 'To be swiped');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      await tester.drag(find.text('To be swiped'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('To be swiped'), findsNothing);
      final row = await (db.select(db.qukis)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(row?.deletedAt, isNotNull);
      await cleanup(tester);
    });

    testWidgets('undo delete restores the QuKi to the list', (tester) async {
      const id = 'undo-test';
      await insertQuki(db, id: id, body: 'Undo me');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      await tester.drag(find.text('Undo me'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      final row = await (db.select(db.qukis)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(row?.deletedAt, isNull);
      await cleanup(tester);
    });

    testWidgets('search field filters the list', (tester) async {
      await insertQuki(db, id: 'x1', body: 'buy milk');
      await insertQuki(db, id: 'x2', body: 'call dentist');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'milk');
      await tester
          .pumpAndSettle(); // wait for new stream to emit filtered results

      expect(find.text('buy milk'), findsOneWidget);
      expect(find.text('call dentist'), findsNothing);
      await cleanup(tester);
    });

    testWidgets('clear search button restores full list', (tester) async {
      await insertQuki(db, id: 'y1', body: 'buy milk');
      await insertQuki(db, id: 'y2', body: 'call dentist');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'milk');
      await tester.pumpAndSettle(); // wait for filtered stream
      expect(find.text('call dentist'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle(); // wait for full stream to restore
      expect(find.text('call dentist'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('shows no-results message when search matches nothing',
        (tester) async {
      await insertQuki(db, id: 'z1', body: 'buy milk');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle(); // wait for filtered stream

      expect(find.textContaining('No results for'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('Ctrl+N opens new editor on desktop platforms', (tester) async {
      // This test only verifies the shortcut on platforms where it is registered.
      if (!Platform.isWindows && !Platform.isLinux) return;

      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // pumpAndSettle would timeout — EditorScreen's periodic auto-save timer
      // never settles. Pump enough frames for the push animation to complete.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(EditorScreen), findsOneWidget);
      await cleanup(tester);
    });
  });
}
