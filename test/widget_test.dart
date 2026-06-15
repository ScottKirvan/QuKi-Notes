import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quki_notes/app.dart';
import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';

void main() {
  testWidgets('app smoke test — EditorScreen renders on launch',
      skip:
          true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
      (tester) async {
    final tmpDir = await Directory.systemTemp.createTemp('quki_smoke_');
    addTearDown(() => tmpDir.delete(recursive: true));
    final storage = QuKiStorage(tmpDir);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [quKiStorageProvider.overrideWithValue(storage)],
        child: const QuKiNotesApp(),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(find.byType(QuKiNotesApp), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
