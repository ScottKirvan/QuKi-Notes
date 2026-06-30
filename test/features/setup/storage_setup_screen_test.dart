import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/core/storage/storage_base_path_provider.dart';
import 'package:quki_notes/core/storage/storage_location_service.dart';
import 'package:quki_notes/features/setup/storage_setup_screen.dart';

// ---------------------------------------------------------------------------
// FilePicker mock — extends FilePicker so default methods are inherited.
// Only getDirectoryPath() needs to be overridden for these tests.
// ---------------------------------------------------------------------------

class _MockFilePicker extends FilePicker with MockPlatformInterfaceMixin {
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

Widget _buildSetup(
  StorageLocationService svc, {
  bool isChangingLocation = false,
  AndroidStorageCallbacks? androidCallbacks,
  bool? useAndroidFlow,
}) =>
    ProviderScope(
      overrides: [
        storageLocationServiceProvider.overrideWithValue(svc),
        quKiStorageProvider.overrideWithValue(_FakeStorage()),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
      ],
      child: MaterialApp(
        home: StorageSetupScreen(
          isChangingLocation: isChangingLocation,
          androidCallbacks: androidCallbacks ?? const AndroidStorageCallbacks(),
          useAndroidFlow: useAndroidFlow,
        ),
      ),
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
  late _MockFilePicker mockPicker;

  setUp(() {
    mockPicker = _MockFilePicker();
    FilePicker.platform = mockPicker;
  });

  group('StorageSetupScreen renders', () {
    testWidgets('shows both storage options', (tester) async {
      final svc = await _freshService();
      await tester.pumpWidget(_buildSetup(svc));
      await tester.pump();

      // "Use app storage" is always present regardless of platform.
      expect(find.text('Use app storage'), findsOneWidget);
      // The filesystem option text varies by platform; just confirm one
      // filesystem-related option is visible.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == 'Choose a folder' ||
                  (w.data?.startsWith('Filesystem storage') ?? false)),
        ),
        findsOneWidget,
      );
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

  // Desktop-only path: file_picker directory picker.
  group('StorageSetupScreen — "Choose a folder" (desktop)', () {
    testWidgets('on success calls setPath and navigates to editor',
        (tester) async {
      // This test only applies on non-Android platforms (desktop/CI host).
      if (Platform.isAndroid) return;

      mockPicker.willReturn('/custom/QuKiNotes');

      final svc = await _freshService();
      await tester.pumpWidget(_buildSetup(svc));
      await tester.pump();

      await tester.tap(find.text('Choose a folder'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      expect(svc.isFirstLaunch, isFalse);
      expect(svc.basePath, '/custom/QuKiNotes');
      expect(find.byType(StorageSetupScreen), findsNothing);
      await cleanup(tester);
    });

    testWidgets('cancelling picker stays on setup screen', (tester) async {
      if (Platform.isAndroid) return;

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

  // Android permission flow — injected via androidCallbacks so no real
  // MethodChannel is needed. useAndroidFlow: true forces the Android code path
  // regardless of the host platform.
  group('StorageSetupScreen — Android filesystem storage', () {
    testWidgets(
        'permission already granted: calls setPath and navigates to editor',
        (tester) async {
      const externalPath = '/sdcard/Documents/QuKi_Notes';
      final svc = await _freshService();

      final callbacks = AndroidStorageCallbacks(
        isExternalStorageManager: () async => true,
        getExternalDocumentsPath: () async => externalPath,
        requestAllFilesAccess: () async {},
        createDirectory: (_) async {}, // no-op: avoid real I/O in FakeAsync
      );

      await tester.pumpWidget(_buildSetup(
        svc,
        androidCallbacks: callbacks,
        useAndroidFlow: true,
      ));
      await tester.pump();

      // With useAndroidFlow: true the card shows the Android title.
      await tester.tap(
          find.textContaining('Filesystem storage — Documents/QuKi_Notes'));
      // Allow async callbacks to complete; do NOT use pumpAndSettle as
      // EditorScreen may schedule ongoing frames (animations, timers).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Storage choice must be saved.
      expect(svc.isFirstLaunch, isFalse);
      expect(svc.basePath, externalPath);
      await cleanup(tester);
    });

    testWidgets(
        'permission not granted: stays on screen; on resume with grant completes',
        (tester) async {
      const externalPath = '/sdcard/Documents/QuKi_Notes';
      final svc = await _freshService();

      // First isExternalStorageManager call returns false (before settings).
      // Second call (on resume) returns true (user granted in settings).
      var callCount = 0;
      final callbacks = AndroidStorageCallbacks(
        isExternalStorageManager: () async {
          callCount++;
          return callCount > 1; // false on first, true on second
        },
        getExternalDocumentsPath: () async => externalPath,
        requestAllFilesAccess: () async {},
        createDirectory: (_) async {}, // no-op: avoid real I/O in FakeAsync
      );

      await tester.pumpWidget(_buildSetup(
        svc,
        androidCallbacks: callbacks,
        useAndroidFlow: true,
      ));
      await tester.pump();

      await tester.tap(
          find.textContaining('Filesystem storage — Documents/QuKi_Notes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Still on setup screen — waiting for permission.
      expect(find.byType(StorageSetupScreen), findsOneWidget);
      expect(svc.isFirstLaunch, isTrue);

      // Simulate app resume (user returned from system settings with grant).
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Now permission was granted — storage choice must be saved.
      expect(svc.isFirstLaunch, isFalse);
      expect(svc.basePath, externalPath);
      await cleanup(tester);
    });

    testWidgets(
        'on resume with permission still denied: returns to idle on setup screen',
        (tester) async {
      final svc = await _freshService();

      final callbacks = AndroidStorageCallbacks(
        isExternalStorageManager: () async => false, // always denied
        getExternalDocumentsPath: () async => '/docs/QuKi_Notes',
        requestAllFilesAccess: () async {},
      );

      await tester.pumpWidget(_buildSetup(
        svc,
        androidCallbacks: callbacks,
        useAndroidFlow: true,
      ));
      await tester.pump();

      await tester.tap(
          find.textContaining('Filesystem storage — Documents/QuKi_Notes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Simulate app resume with permission still denied.
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Setup screen still visible; no choice saved.
      expect(find.byType(StorageSetupScreen), findsOneWidget);
      expect(svc.isFirstLaunch, isTrue);
      await cleanup(tester);
    });
  });

  group('StorageSetupScreen — isChangingLocation', () {
    testWidgets('back button pops without calling useAppStorage',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'storage.base_path': _appStoragePath,
        'storage.location_chosen': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = StorageLocationService(prefs, _appStoragePath);

      bool popped = false;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          storageLocationServiceProvider.overrideWithValue(svc),
          quKiStorageProvider.overrideWithValue(_FakeStorage()),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push<void>(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      const StorageSetupScreen(isChangingLocation: true),
                ),
              ).then((_) => popped = true),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(StorageSetupScreen), findsOneWidget);

      // Simulate back via Navigator.maybePop.
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.maybePop();
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      // isAppStorage still true and isFirstLaunch still false — no change.
      expect(svc.isAppStorage, isTrue);
      expect(svc.isFirstLaunch, isFalse);
      await cleanup(tester);
    });
  });

  group('StorageSetupScreen — system back (first launch)', () {
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

  // Tests that verify storageBasePathProvider is updated after a choice is made.
  group('StorageSetupScreen — storageBasePathProvider updates', () {
    testWidgets(
        '"Use app storage" pushes app storage path to storageBasePathProvider',
        (tester) async {
      final svc = await _freshService();

      late ProviderContainer container;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          storageLocationServiceProvider.overrideWithValue(svc),
          quKiStorageProvider.overrideWithValue(_FakeStorage()),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: StorageSetupScreen());
          },
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Use app storage'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(storageBasePathProvider), _appStoragePath);
      await cleanup(tester);
    });

    testWidgets(
        'Android filesystem storage pushes external path to storageBasePathProvider',
        (tester) async {
      const externalPath = '/sdcard/Documents/QuKi_Notes';
      final svc = await _freshService();

      final callbacks = AndroidStorageCallbacks(
        isExternalStorageManager: () async => true,
        getExternalDocumentsPath: () async => externalPath,
        requestAllFilesAccess: () async {},
        createDirectory: (_) async {},
      );

      late ProviderContainer container;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          storageLocationServiceProvider.overrideWithValue(svc),
          quKiStorageProvider.overrideWithValue(_FakeStorage()),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: StorageSetupScreen(
                androidCallbacks: callbacks,
                useAndroidFlow: true,
              ),
            );
          },
        ),
      ));
      await tester.pump();

      await tester.tap(
          find.textContaining('Filesystem storage — Documents/QuKi_Notes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(storageBasePathProvider), externalPath);
      await cleanup(tester);
    });
  });
}
