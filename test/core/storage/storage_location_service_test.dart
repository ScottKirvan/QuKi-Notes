import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quki_notes/core/storage/storage_location_service.dart';

void main() {
  const appStoragePath = '/app/documents/qukis';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StorageLocationService.isFirstLaunch', () {
    test('true when neither key is present in prefs', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, appStoragePath);

      expect(svc.isFirstLaunch, isTrue);
    });

    test('false after setPath()', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, appStoragePath);

      await svc.setPath('/custom/path');

      expect(svc.isFirstLaunch, isFalse);
    });

    test('false after useAppStorage()', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, appStoragePath);

      await svc.useAppStorage();

      expect(svc.isFirstLaunch, isFalse);
    });
  });

  group('StorageLocationService.basePath', () {
    test('returns app storage path when no prefs key set', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, appStoragePath);

      expect(svc.basePath, appStoragePath);
    });

    test('returns saved path after setPath()', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, appStoragePath);

      await svc.setPath('/sdcard/QuKiNotes');

      expect(svc.basePath, '/sdcard/QuKiNotes');
    });
  });

  group('StorageLocationService.adoptAppStorageIfUpgrading', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('quki_upgrade_test_');
    });

    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    test('does nothing when already chosen (not first launch)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, tmpDir.path);
      await svc.useAppStorage(); // marks chosen
      await File(p.join(tmpDir.path, 'abc.md')).writeAsString('hello');

      await svc.adoptAppStorageIfUpgrading();

      // basePath was already app storage; isFirstLaunch still false
      expect(svc.isFirstLaunch, isFalse);
    });

    test('does nothing when directory does not exist', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final missingPath = p.join(tmpDir.path, 'nonexistent');
      final svc = StorageLocationService(prefs, missingPath);

      await svc.adoptAppStorageIfUpgrading();

      expect(svc.isFirstLaunch, isTrue);
    });

    test('does nothing when directory is empty', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, tmpDir.path);

      await svc.adoptAppStorageIfUpgrading();

      expect(svc.isFirstLaunch, isTrue);
    });

    test('does nothing when directory has no .md files', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, tmpDir.path);
      await File(p.join(tmpDir.path, 'note.txt')).writeAsString('hello');

      await svc.adoptAppStorageIfUpgrading();

      expect(svc.isFirstLaunch, isTrue);
    });

    test('silently adopts app storage when .md files exist (upgrade path)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, tmpDir.path);
      await File(p.join(tmpDir.path, 'abc123.md')).writeAsString('a quiki');

      await svc.adoptAppStorageIfUpgrading();

      expect(svc.isFirstLaunch, isFalse);
      expect(svc.isAppStorage, isTrue);
    });
  });

  group('StorageLocationService.isAppStorage', () {
    test('true when path matches app storage path', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, appStoragePath);

      await svc.useAppStorage();

      expect(svc.isAppStorage, isTrue);
    });

    test('false when a custom path is set', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, appStoragePath);

      await svc.setPath('/sdcard/QuKiNotes');

      expect(svc.isAppStorage, isFalse);
    });

    test('true by default (before any choice is made)', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, appStoragePath);

      // basePath defaults to appStoragePath, so isAppStorage must be true.
      expect(svc.isAppStorage, isTrue);
    });
  });
}
