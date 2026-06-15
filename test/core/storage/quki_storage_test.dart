import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';

void main() {
  late Directory tmpDir;
  late QuKiStorage storage;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('quki_storage_test_');
    storage = QuKiStorage(tmpDir);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  group('QuKiStorage.create', () {
    test('writes .md and .meta files', () async {
      final meta = await storage.create('hello world');

      expect(meta.id, isNotEmpty);
      expect(meta.filePath, endsWith('${meta.id}.md'));

      final mdFile = File(meta.filePath);
      expect(await mdFile.exists(), isTrue);
      expect(await mdFile.readAsString(), 'hello world');

      final metaPath = '${tmpDir.path}/.meta/${meta.id}.json';
      expect(await File(metaPath).exists(), isTrue);
    });

    test('returned meta has matching createdAt and modifiedAt', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final meta = await storage.create('body');
      final after = DateTime.now().add(const Duration(seconds: 1));

      expect(meta.createdAt.isAfter(before), isTrue);
      expect(meta.createdAt.isBefore(after), isTrue);
      expect(meta.modifiedAt.isAfter(before), isTrue);
    });
  });

  group('QuKiStorage.read', () {
    test('returns the body of an existing QuKi', () async {
      final meta = await storage.create('read me');
      expect(await storage.read(meta.id), 'read me');
    });
  });

  group('QuKiStorage.update', () {
    test('overwrites the .md file content', () async {
      final meta = await storage.create('original');
      await storage.update(meta.id, 'updated');
      expect(await storage.read(meta.id), 'updated');
    });

    test('leaves .meta file unchanged', () async {
      final meta = await storage.create('v1');
      final metaPath = '${tmpDir.path}/.meta/${meta.id}.json';
      final contentBefore = await File(metaPath).readAsString();
      await storage.update(meta.id, 'v2');
      final contentAfter = await File(metaPath).readAsString();
      expect(contentAfter, contentBefore);
    });
  });

  group('QuKiStorage.softDelete', () {
    test('moves .md and .meta to .trash/', () async {
      final meta = await storage.create('to trash');
      await storage.softDelete(meta.id);

      expect(await File(meta.filePath).exists(), isFalse,
          reason: 'Active .md must be gone after soft delete');
      expect(await File('${tmpDir.path}/.trash/${meta.id}.md').exists(), isTrue,
          reason: '.md must exist in .trash/');
      expect(await File('${tmpDir.path}/.trash/.meta/${meta.id}.json').exists(),
          isTrue,
          reason: '.meta must exist in .trash/.meta/');
    });
  });

  group('QuKiStorage.restore', () {
    test('moves files back from .trash/ to active', () async {
      final meta = await storage.create('restore me');
      await storage.softDelete(meta.id);
      await storage.restore(meta.id);

      expect(await File(meta.filePath).exists(), isTrue,
          reason: 'Active .md must be back after restore');
      expect(
          await File('${tmpDir.path}/.trash/${meta.id}.md').exists(), isFalse,
          reason: '.md must be gone from .trash/');
    });

    test('restored file has original content', () async {
      final meta = await storage.create('keep me');
      await storage.softDelete(meta.id);
      await storage.restore(meta.id);
      expect(await storage.read(meta.id), 'keep me');
    });
  });

  group('QuKiStorage.hardDelete', () {
    test('permanently removes files from .trash/', () async {
      final meta = await storage.create('delete forever');
      await storage.softDelete(meta.id);
      await storage.hardDelete(meta.id);

      expect(
          await File('${tmpDir.path}/.trash/${meta.id}.md').exists(), isFalse);
      expect(await File('${tmpDir.path}/.trash/.meta/${meta.id}.json').exists(),
          isFalse);
    });
  });

  group('QuKiStorage.scanActive', () {
    test('returns empty list when no QuKis', () async {
      expect(await storage.scanActive(), isEmpty);
    });

    test('returns created QuKis sorted newest-first by mtime', () async {
      await storage.create('first');
      await storage.create('second');

      final results = await storage.scanActive();
      expect(results.length, 2);
      // Verify sort invariant — newer mtime must come before older.
      expect(
        results[0].modifiedAt.compareTo(results[1].modifiedAt),
        greaterThanOrEqualTo(0),
      );
    });

    test('does not include soft-deleted QuKis', () async {
      final meta = await storage.create('hidden');
      await storage.softDelete(meta.id);
      expect(await storage.scanActive(), isEmpty);
    });
  });

  group('QuKiStorage.scanTrash', () {
    test('returns empty list when trash is empty', () async {
      expect(await storage.scanTrash(), isEmpty);
    });

    test('returns soft-deleted QuKis', () async {
      final meta = await storage.create('trashed');
      await storage.softDelete(meta.id);
      final trash = await storage.scanTrash();
      expect(trash.length, 1);
      expect(trash.first.id, meta.id);
    });

    test('does not include restored QuKis', () async {
      final meta = await storage.create('restored');
      await storage.softDelete(meta.id);
      await storage.restore(meta.id);
      expect(await storage.scanTrash(), isEmpty);
    });
  });
}
