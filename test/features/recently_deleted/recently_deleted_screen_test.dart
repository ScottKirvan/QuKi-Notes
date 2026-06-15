import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/features/recently_deleted/recently_deleted_screen.dart';

/// Fake [TrashIndexNotifier] pre-populated with a list.
class _FakeTrashIndex extends TrashIndexNotifier {
  _FakeTrashIndex(this._initial);
  final List<QuKiMeta> _initial;

  @override
  Future<List<QuKiMeta>> build() async => List.from(_initial);

  @override
  void addMeta(QuKiMeta meta) {
    state.whenData((list) => state = AsyncValue.data([meta, ...list]));
  }

  @override
  void removeMeta(String id) {
    state.whenData((list) {
      state = AsyncValue.data(list.where((m) => m.id != id).toList());
    });
  }

  @override
  Future<void> refresh() async {}
}

/// Fake [QuKiIndexNotifier] — the recently-deleted screen calls refresh() on it
/// after restore. Keep it minimal; we don't need real scan behaviour here.
class _FakeQuKiIndex extends QuKiIndexNotifier {
  @override
  Future<List<QuKiMeta>> build() async => [];

  @override
  void addMeta(QuKiMeta meta) {}

  @override
  void updateMeta(String id, DateTime modifiedAt) {}

  @override
  void removeMeta(String id) {}

  @override
  Future<void> refresh() async {}
}

void main() {
  late Directory tmpDir;
  late QuKiStorage storage;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('quki_recently_del_test_');
    storage = QuKiStorage(tmpDir);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  Widget buildUnderTest(List<QuKiMeta> trashed) => ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
          trashIndexProvider.overrideWith(() => _FakeTrashIndex(trashed)),
        ],
        child: const MaterialApp(home: RecentlyDeletedScreen()),
      );

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  group('RecentlyDeletedScreen', () {
    testWidgets('shows empty message when trash is empty', (tester) async {
      await tester.pumpWidget(buildUnderTest([]));
      await tester.pump();
      await tester.pump(Duration.zero);

      expect(find.textContaining('No notes in Trash'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('lists trashed QuKis',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('trashed body');
      await storage.softDelete(meta.id);
      // Patch filePath to trash location for preview loading.
      final trashMeta = QuKiMeta(
        id: meta.id,
        filePath: '${tmpDir.path}/.trash/${meta.id}.md',
        createdAt: meta.createdAt,
        modifiedAt: meta.modifiedAt,
      );

      await tester.pumpWidget(buildUnderTest([trashMeta]));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero); // preview load

      expect(find.text('trashed body'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('tapping row calls restore and pops',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('restore me');
      await storage.softDelete(meta.id);
      final trashMeta = QuKiMeta(
        id: meta.id,
        filePath: '${tmpDir.path}/.trash/${meta.id}.md',
        createdAt: meta.createdAt,
        modifiedAt: meta.modifiedAt,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
          trashIndexProvider.overrideWith(() => _FakeTrashIndex([trashMeta])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push<void>(
                ctx,
                MaterialPageRoute(
                    builder: (_) => const RecentlyDeletedScreen()),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      await tester.tap(find.text('restore me'));
      await tester.pump();
      await tester.pump(Duration.zero);

      // Confirmation dialog must appear.
      expect(find.text('Restore note?'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pump();
      await tester.pump(Duration.zero);

      // Screen should have popped.
      expect(find.byType(RecentlyDeletedScreen), findsNothing);
      // File should be back in active location.
      expect(await File(meta.filePath).exists(), isTrue);

      await cleanup(tester);
    });

    testWidgets('swipe to hard-delete shows confirmation dialog',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('delete forever');
      await storage.softDelete(meta.id);
      final trashMeta = QuKiMeta(
        id: meta.id,
        filePath: '${tmpDir.path}/.trash/${meta.id}.md',
        createdAt: meta.createdAt,
        modifiedAt: meta.modifiedAt,
      );

      await tester.pumpWidget(buildUnderTest([trashMeta]));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      await tester.drag(find.text('delete forever'), const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Delete permanently?'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('confirming hard-delete removes the row',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('gone forever');
      await storage.softDelete(meta.id);
      final trashMeta = QuKiMeta(
        id: meta.id,
        filePath: '${tmpDir.path}/.trash/${meta.id}.md',
        createdAt: meta.createdAt,
        modifiedAt: meta.modifiedAt,
      );

      await tester.pumpWidget(buildUnderTest([trashMeta]));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      await tester.drag(find.text('gone forever'), const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap the Delete button in the confirmation dialog.
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(Duration.zero);

      expect(find.text('gone forever'), findsNothing);
      // File must be removed from trash.
      expect(
          await File('${tmpDir.path}/.trash/${meta.id}.md').exists(), isFalse);

      await cleanup(tester);
    });
  });
}
