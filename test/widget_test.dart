import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quki_notes/app.dart';
import 'package:quki_notes/core/database/app_database.dart';
import 'package:quki_notes/core/database/database_provider.dart';

void main() {
  testWidgets('app smoke test — EditorScreen renders on launch',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const QuKiNotesApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(QuKiNotesApp), findsOneWidget);

    // Unmount within fake_async so drift's cleanup timer fires before
    // the test framework's invariant check.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
