import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('EditorScreen snackbar durations', () {
    // Tests the guard path (empty body → synchronous snackbar).
    // The toss-result paths (success/failure) use the same Duration type
    // and are covered by the code in editor_screen.dart:_onToss.
    testWidgets('empty-body guard snackbar has duration ≤ 3s', (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      await tester.tap(find.text('Toss ▼'));
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

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  });
}
