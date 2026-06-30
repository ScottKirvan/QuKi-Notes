import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/storage_base_path_provider.dart';
import 'package:quki_notes/core/storage/storage_location_service.dart';

const _appStoragePath = '/app/documents/qukis';

StorageLocationService _freshService(SharedPreferences prefs) =>
    StorageLocationService(prefs, _appStoragePath);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StorageBasePathNotifier', () {
    test('initial state equals storageLocationService.basePath', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = _freshService(prefs);

      final container = ProviderContainer(
        overrides: [
          storageLocationServiceProvider.overrideWithValue(svc),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(storageBasePathProvider), _appStoragePath);
    });

    test('setPath updates state to the new path', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = _freshService(prefs);

      final container = ProviderContainer(
        overrides: [
          storageLocationServiceProvider.overrideWithValue(svc),
        ],
      );
      addTearDown(container.dispose);

      const newPath = '/sdcard/Documents/QuKi_Notes';
      container.read(storageBasePathProvider.notifier).setPath(newPath);

      expect(container.read(storageBasePathProvider), newPath);
    });

    test('initial state equals custom path when service has one set', () async {
      SharedPreferences.setMockInitialValues({
        'storage.base_path': '/custom/path',
        'storage.location_chosen': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, _appStoragePath);

      final container = ProviderContainer(
        overrides: [
          storageLocationServiceProvider.overrideWithValue(svc),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(storageBasePathProvider), '/custom/path');
    });
  });

  group('quKiStorageProvider reactivity', () {
    test('rebuilds when storageBasePathProvider changes', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = _freshService(prefs);

      final container = ProviderContainer(
        overrides: [
          storageLocationServiceProvider.overrideWithValue(svc),
        ],
      );
      addTearDown(container.dispose);

      final storageBefore = container.read(quKiStorageProvider);
      expect(storageBefore.basePath, _appStoragePath);

      const newPath = '/sdcard/Documents/QuKi_Notes';
      container.read(storageBasePathProvider.notifier).setPath(newPath);

      final storageAfter = container.read(quKiStorageProvider);
      expect(storageAfter.basePath, newPath);
    });
  });
}
