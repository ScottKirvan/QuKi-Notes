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
import 'package:quki_notes/features/setup/storage_setup_screen.dart';

// ---------------------------------------------------------------------------
// FilePicker mock — extends FilePickerPlatform so default methods are inherited.
// Only getDirectoryPath() needs to be overridden for these tests.
// ---------------------------------------------------------------------------

class _MockFilePickerPlatform extends FilePickerPlatform
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
// Fake QuKiStorage — avoids disk I/O inside FakeAsync.
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

Widget _buildSetup(StorageLocationService svc) => ProviderScope(
      overrides: [
        storageLocationServiceProvider.overrideWithValue(svc),
        quKiStorageProvider.overrideWithValue(_FakeStorage()),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
      ],
      child: const MaterialApp(home: StorageSetupScreen()),
    );

Future<StorageLocationService> _freshService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return StorageLocationService(prefs, _appStoragePath);
}

Future<void> cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockFilePickerPlatform mockPicker;

  setUp(() {
    mockPicker = _MockFilePickerPlatform();
    FilePickerPlatform.instance = mockPicker;
  });

  group('StorageSetupScreen renders', () {
    testWidgets('shows both storage options', (tester) async {
      final svc = await _freshService();
      await tester.pumpWidget(_buildSetup(svc));
      await tester.pump();

      expect(find.text('Choose a folder'), findsOneWidget);
      expect(find.text('Use app storage'), findsOneWidget);
      await cleanup(tester);
    });
  });

  group('StorageSetupScreen — "Use app storage"', () {
    testWidgets('calls useAppStorage and navigates to editor', (tester) async {
      final svc = await _freshService();
      await tester.pumpWidget(_buildSetup(svc));
      await tester.pump();

      await tester.tap(find.text('Use app storage'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // State must be saved regardless of animation state.
      expect(svc.isFirstLaunch, isFalse);
      expect(svc.isAppStorage, isTrue);
      // Screen must no longer be visible after animation settles.
      expect(find.byType(StorageSetupScreen), findsNothing);
      await cleanup(tester);
    });
  });

  group('StorageSetupScreen — "Choose a folder"', () {
    testWidgets('on success calls setPath and navigates to editor',
        (tester) async {
      mockPicker.willReturn('/sdcard/QuKiNotes');

      final svc = await _freshService();
      await tester.pumpWidget(_buildSetup(svc));
      await tester.pump();

      await tester.tap(find.text('Choose a folder'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(svc.isFirstLaunch, isFalse);
      expect(svc.basePath, '/sdcard/QuKiNotes');
      expect(find.byType(StorageSetupScreen), findsNothing);
      await cleanup(tester);
    });

    testWidgets('cancelling picker stays on setup screen', (tester) async {
      mockPicker.willReturn(null); // user pressed Cancel

      final svc = await _freshService();
      await tester.pumpWidget(_buildSetup(svc));
      await tester.pump();

      await tester.tap(find.text('Choose a folder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Still on setup screen — no navigation, no choice saved.
      expect(find.byType(StorageSetupScreen), findsOneWidget);
      expect(svc.isFirstLaunch, isTrue);
      await cleanup(tester);
    });
  });

  group('StorageSetupScreen — system back', () {
    testWidgets(
        'when no choice has been made, back saves app storage and navigates',
        (tester) async {
      final svc = await _freshService();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          storageLocationServiceProvider.overrideWithValue(svc),
          quKiStorageProvider.overrideWithValue(_FakeStorage()),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
        ],
        child: const MaterialApp(home: StorageSetupScreen()),
      ));
      await tester.pump();

      // Simulate system back via the Android back button.
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(svc.isFirstLaunch, isFalse);
      expect(svc.isAppStorage, isTrue);
      await cleanup(tester);
    });
  });
}
