import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quki_notes/core/database/app_database.dart';
import 'package:quki_notes/core/database/database_provider.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildEditor({Future<void> Function(BuildContext)? onLeave}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: EditorScreen(onLeave: onLeave)),
    );
  }

  group('EditorScreen keyboard shortcuts', () {
    testWidgets('Escape triggers _onLeave on desktop platforms',
        (tester) async {
      // This test only verifies the shortcut on platforms where it is registered.
      if (!Platform.isWindows && !Platform.isLinux) return;

      var leaveCalled = false;
      await tester.pumpWidget(
        buildEditor(onLeave: (_) async {
          leaveCalled = true;
        }),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(leaveCalled, isTrue);
    });
  });
}
