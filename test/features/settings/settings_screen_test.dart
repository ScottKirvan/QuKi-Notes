import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/core/storage/storage_location_service.dart';
import 'package:quki_notes/features/settings/settings_screen.dart';
import 'package:quki_notes/features/setup/storage_setup_screen.dart';

// ---------------------------------------------------------------------------
// Fake storage / index
// ---------------------------------------------------------------------------

class _FakeStorage extends QuKiStorage {
  _FakeStorage() : super(Directory.systemTemp);

  @override
  Future<List<QuKiMeta>> scanActive() async => [];
  @override
  Future<List<QuKiMeta>> scanTrash() async => [];
  @override
  Future<QuKiMeta> create(String body) async => QuKiMeta(
        id: 'x',
        filePath: '/x.md',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
  @override
  Future<DateTime> update(String id, String body,
          {DateTime? modifiedAt}) async =>
      modifiedAt?.toUtc() ?? DateTime.now().toUtc();
  @override
  Future<String> read(String id) async => '';
}

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _appStoragePath = '/app/documents/qukis';

Future<StorageLocationService> _appStorageSvc() async {
  SharedPreferences.setMockInitialValues({
    'storage.base_path': _appStoragePath,
    'storage.location_chosen': true,
  });
  final prefs = await SharedPreferences.getInstance();
  return StorageLocationService(prefs, _appStoragePath);
}

Future<StorageLocationService> _customStorageSvc(String path) async {
  SharedPreferences.setMockInitialValues({
    'storage.base_path': path,
    'storage.location_chosen': true,
  });
  final prefs = await SharedPreferences.getInstance();
  return StorageLocationService(prefs, _appStoragePath);
}

Widget _buildSettings(StorageLocationService svc) => ProviderScope(
      overrides: [
        storageLocationServiceProvider.overrideWithValue(svc),
        quKiStorageProvider.overrideWithValue(_FakeStorage()),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );

Future<void> cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SettingsScreen — Storage section', () {
    testWidgets('Storage section header is visible', (tester) async {
      final svc = await _appStorageSvc();
      await tester.pumpWidget(_buildSettings(svc));
      await tester.pump();

      expect(find.text('STORAGE'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets(
        'app-storage warning subtitle visible when isAppStorage is true',
        (tester) async {
      final svc = await _appStorageSvc();
      await tester.pumpWidget(_buildSettings(svc));
      await tester.pump();

      expect(
        find.textContaining('Files will be removed on uninstall'),
        findsOneWidget,
      );
      await cleanup(tester);
    });

    testWidgets(
        'app-storage warning not shown when filesystem storage is active',
        (tester) async {
      final svc = await _customStorageSvc('/sdcard/QuKiNotes');
      await tester.pumpWidget(_buildSettings(svc));
      await tester.pump();

      expect(
        find.textContaining('Files will be removed on uninstall'),
        findsNothing,
      );
      expect(find.text('Filesystem storage'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('"Change location" tile navigates to StorageSetupScreen',
        (tester) async {
      final svc = await _appStorageSvc();
      await tester.pumpWidget(_buildSettings(svc));
      await tester.pump();

      await tester.tap(find.text('Change location'));
      await tester.pumpAndSettle();

      expect(find.byType(StorageSetupScreen), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets(
        'StorageSetupScreen pushed from settings has isChangingLocation true',
        (tester) async {
      final svc = await _appStorageSvc();
      await tester.pumpWidget(_buildSettings(svc));
      await tester.pump();

      await tester.tap(find.text('Change location'));
      await tester.pumpAndSettle();

      final screen =
          tester.widget<StorageSetupScreen>(find.byType(StorageSetupScreen));
      expect(screen.isChangingLocation, isTrue);
      await cleanup(tester);
    });
  });
}
