import 'package:flutter_test/flutter_test.dart';
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
