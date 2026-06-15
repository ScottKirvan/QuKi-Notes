import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';

// Direct tests of QuKiStorage scan behaviour that underlies QuKiIndexNotifier.
// The Riverpod notifier is thin coordination around storage.scan*(), which is
// already tested in quki_storage_test.dart. Here we test the sort invariant
// and incremental update pattern.

void main() {
  late Directory tmpDir;
  late QuKiStorage storage;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('quki_index_test_');
    storage = QuKiStorage(tmpDir);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('scanActive returns items sorted by modifiedAt descending', () async {
    for (var i = 0; i < 3; i++) {
      await storage.create('item $i');
    }
    final index = await storage.scanActive();
    expect(index.length, 3);
    // Verify sort invariant — each entry must be >= the next.
    for (var i = 0; i < index.length - 1; i++) {
      expect(
        index[i].modifiedAt.compareTo(index[i + 1].modifiedAt),
        greaterThanOrEqualTo(0),
        reason: 'index[$i].modifiedAt must be ≥ index[${i + 1}].modifiedAt',
      );
    }
  });

  test('update() advances mtime so scanActive puts it first', () async {
    // Create two QuKis and read their initial mtimes from the OS.
    final a = await storage.create('alpha');
    final b = await storage.create('beta');
    final mtimeBefore =
        (await storage.scanActive()).firstWhere((m) => m.id == a.id).modifiedAt;

    // Wait 1s — well past any OS mtime granularity — then update a.
    await Future<void>.delayed(const Duration(seconds: 1));
    await storage.update(a.id, 'alpha updated');

    final after = await storage.scanActive();
    final aAfter = after.firstWhere((m) => m.id == a.id);

    // a's mtime must have advanced.
    expect(
      aAfter.modifiedAt.isAfter(mtimeBefore),
      isTrue,
      reason: 'update() must produce a newer mtime than before the write',
    );
    // a must now be first (newest).
    expect(after.first.id, a.id, reason: 'updated QuKi must sort to the top');
    // b is still in the list.
    expect(after.any((m) => m.id == b.id), isTrue);
  });

  test('QuKiMeta.copyWith preserves id and filePath', () {
    final m = QuKiMeta(
      id: 'abc',
      filePath: '/some/path.md',
      createdAt: _epoch,
      modifiedAt: _epoch,
    );
    final now = DateTime(2026, 6, 14);
    final copy = m.copyWith(modifiedAt: now);
    expect(copy.id, 'abc');
    expect(copy.filePath, '/some/path.md');
    expect(copy.modifiedAt, now);
    expect(copy.createdAt, _epoch);
  });
}

final _epoch = DateTime.utc(2000);
