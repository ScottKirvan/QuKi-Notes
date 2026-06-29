import 'dart:io';

import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/core/storage/storage_location_service.dart';
import 'package:quki_notes/features/settings/settings_screen.dart';
import 'package:quki_notes/features/setup/storage_setup_screen.dart';

// ---------------------------------------------------------------------------
// FilePicker mock
// ---------------------------------------------------------------------------

class _MockFilePicker extends FilePickerPlatform
    with MockPlatformInterfaceMixin {
  String? _returnPath;
  void willReturn(String? path) => _returnPath = path;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async =>
      _returnPath;
}

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
  Future<void> update(String id, String body) async {}
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
  late _MockFilePicker mockPicker;

  setUp(() {
    mockPicker = _MockFilePicker();
    FilePickerPlatform.instance = mockPicker;
  });

  group('SettingsScreen — Storage section', () {
    testWidgets('Storage section header is visible', (tester) async {
      final svc = await _appStorageSvc();
      await tester.pumpWidget(_buildSettings(svc));
      await tester.pump();

      expect(find.text('STORAGE'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('app-storage warning subtitle visible when isAppStorage is true',
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

    testWidgets(
        '"Change location" tap opens picker; on success shows "not moved" snackbar',
        (tester) async {
      mockPicker.willReturn('/new/custom/path');

      final svc = await _appStorageSvc();
      await tester.pumpWidget(_buildSettings(svc));
      await tester.pump();

      await tester.tap(find.text('Change location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Existing files were not moved'),
        findsOneWidget,
      );
      expect(svc.basePath, '/new/custom/path');
      await cleanup(tester);
    });

    testWidgets('"Change location" cancel leaves path unchanged', (tester) async {
      mockPicker.willReturn(null); // user cancelled

      final svc = await _appStorageSvc();
      final pathBefore = svc.basePath;

      await tester.pumpWidget(_buildSettings(svc));
      await tester.pump();

      await tester.tap(find.text('Change location'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // No snackbar, no path change.
      expect(
        find.textContaining('Existing files were not moved'),
        findsNothing,
      );
      expect(svc.basePath, pathBefore);
      await cleanup(tester);
    });
  });
}
