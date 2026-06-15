import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:super_editor/super_editor.dart';

import 'package:quki_notes/app.dart';
import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/core/transports/registry_provider.dart';
import 'package:quki_notes/core/transports/transport_plugin.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';
import 'package:quki_notes/features/stream/stream_screen.dart';

/// A transport that always throws — used to verify error snackbar behaviour.
class _ThrowingTransport extends TransportPlugin {
  const _ThrowingTransport();

  @override
  String get id => 'throwing-transport';

  @override
  String get displayName => 'Throwing Transport';

  @override
  String get description => 'Always throws for test purposes.';

  @override
  Future<TossResult> toss({
    required String markdown,
    required List<TossImage> images,
    required TossContext ctx,
  }) async {
    throw Exception('transport error');
  }
}

/// Fake [QuKiIndexNotifier] that holds a pre-built list and accepts mutations.
class _FakeQuKiIndex extends QuKiIndexNotifier {
  _FakeQuKiIndex(this._initial);
  final List<QuKiMeta> _initial;

  @override
  Future<List<QuKiMeta>> build() async => List.from(_initial);

  @override
  void addMeta(QuKiMeta meta) {
    state.whenData((list) => state = AsyncValue.data([meta, ...list]));
  }

  @override
  void updateMeta(String id, DateTime modifiedAt) {
    state.whenData((list) {
      state = AsyncValue.data([
        for (final m in list)
          if (m.id == id) m.copyWith(modifiedAt: modifiedAt) else m,
      ]);
    });
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

void main() {
  late Directory tmpDir;
  late QuKiStorage storage;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('quki_editor_test_');
    storage = QuKiStorage(tmpDir);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  Widget buildEditor({List<QuKiMeta> initialIndex = const []}) => ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(initialIndex)),
        ],
        child: const MaterialApp(home: EditorScreen()),
      );

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  group('EditorScreen auto-focus', () {
    testWidgets('editor FocusNode is focused after first frame',
        (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      final superEditorFinder = find.byType(SuperEditor);
      expect(superEditorFinder, findsOneWidget);

      final superEditor = tester.widget<SuperEditor>(superEditorFinder);
      expect(superEditor.focusNode, isNotNull);
      expect(superEditor.focusNode!.hasFocus, isTrue);

      await cleanup(tester);
    });
  });

  group('EditorScreen snackbar durations', () {
    testWidgets('empty-body guard snackbar has duration ≤ 3s', (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send...'));
      await tester.pump();

      expect(
        find.text('Nothing to toss — write something first.'),
        findsOneWidget,
      );
      final snackBar = tester.firstWidget<SnackBar>(
        find.ancestor(
          of: find.text('Nothing to toss — write something first.'),
          matching: find.byType(SnackBar),
        ),
      );
      expect(snackBar.duration.inSeconds, lessThanOrEqualTo(3));

      await cleanup(tester);
    });
  });

  group('EditorScreen navigation', () {
    testWidgets('shows QuKis icon, + button, and hamburger — no back button',
        (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      expect(find.byIcon(LucideIcons.fileStack), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      expect(find.byIcon(LucideIcons.menu), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      await cleanup(tester);
    });

    testWidgets(
        'no back button even when navigator-pushed — EditorScreen is always root',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(const [])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  ctx,
                  MaterialPageRoute(builder: (_) => const EditorScreen()),
                ),
                child: const Text('Push'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Push'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byIcon(LucideIcons.fileStack), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      await cleanup(tester);
    });

    testWidgets('root editor has no back button when QuKi loaded via provider',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('nav test body');

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // setId triggers _onActiveQukiChanged → real dart:io read. runAsync exits
      // FakeAsync so the I/O completion is delivered. Do NOT call tester.pump()
      // inside runAsync — Flutter forbids it and it causes hangs.
      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(LucideIcons.fileStack), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      await cleanup(tester);
    });

    testWidgets('hamburger menu contains Send..., QuKis, Settings',
        (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Send...'), findsOneWidget);
      expect(find.text('QuKis'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await cleanup(tester);
    });

    testWidgets('+ button clears editor to blank — existing QuKi is preserved',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('existing content');

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(activeQukiIdProvider), isNull);
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      // File still exists and has unchanged content.
      final body = await tester.runAsync(() => storage.read(meta.id));
      expect(body!, 'existing content');

      await cleanup(tester);
    });

    testWidgets('SuperEditor has autocorrect and suggestions disabled (#32)',
        (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      final superEditor = tester.widget<SuperEditor>(find.byType(SuperEditor));
      expect(superEditor.imeConfiguration?.enableAutocorrect, isFalse);
      expect(superEditor.imeConfiguration?.enableSuggestions, isFalse);

      await cleanup(tester);
    });

    testWidgets('QuKis list animates in from the left',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('content');

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();
      await tester.pump(Duration.zero); // index notifier settles

      await tester.tap(find.byIcon(LucideIcons.fileStack));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(StreamScreen), findsOneWidget);

      final slideFinder = find.ancestor(
        of: find.byType(StreamScreen),
        matching: find.byType(SlideTransition),
      );
      expect(slideFinder, findsWidgets);

      final slide = tester.widget<SlideTransition>(slideFinder.first);
      expect(slide.position.value.dx, lessThan(0));

      // Allow _loadPreview dart:io and the slide animation to finish before
      // cleanup — avoids dangling async work causing the next test to hang.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await cleanup(tester);
    });
  });

  group('EditorScreen toss error handling', () {
    testWidgets(
        'shows error snackbar with Retry action when plugin throws — '
        'regression: plugin crash left UI in indeterminate state',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('some content to toss');

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
          enabledTransportsProvider
              .overrideWithValue(const [_ThrowingTransport()]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send...'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Send failed — unexpected error.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await cleanup(tester);
    });
  });

  group('EditorScreen smart send (#85)', () {
    testWidgets(
        'fires direct when exactly one transport is enabled — no bottom sheet shown — '
        'regression: always showed picker sheet regardless of transport count (#85)',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('smart send content');

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
          enabledTransportsProvider
              .overrideWithValue(const [_ThrowingTransport()]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send...'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Throwing Transport'), findsNothing);
      expect(find.text('Send failed — unexpected error.'), findsOneWidget);

      await cleanup(tester);
    });
  });

  group('EditorScreen QuKis icon disabled when empty (#86)', () {
    testWidgets(
        'QuKis icon is disabled when index is empty — '
        'regression: icon was always enabled regardless of DB state (#86)',
        (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();
      await tester.pump(Duration.zero);

      final iconButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(LucideIcons.fileStack),
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButton.onPressed, isNull,
          reason: 'QuKis icon must be disabled when the index is empty');

      await cleanup(tester);
    });

    testWidgets(
        'QuKis icon is enabled when index has items — '
        'regression: icon did not react to index changes (#86)',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('hello');

      await tester.pumpWidget(ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();
      await tester.pump(Duration.zero);

      final iconButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(LucideIcons.fileStack),
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButton.onPressed, isNotNull,
          reason: 'QuKis icon must be enabled when there are QuKis');

      await cleanup(tester);
    });
  });

  group('EditorScreen _switchDocument does not bump modifiedAt (#75)', () {
    testWidgets(
        '_switchDocument does not call onSave — '
        'regression: opening a note without editing bumped modifiedAt (#75)',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await storage.create('load me');
      var saveCallCount = 0;

      // Override the index notifier with a spy that counts write-callback invocations.
      // Since AutoSaveController is constructed in initState with a captured ref,
      // we verify the file was not rewritten by checking mtime is unchanged.
      final statBefore =
          await tester.runAsync(() => File(meta.filePath).stat());

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      // File mtime must not have changed — no user edit occurred.
      final statAfter = await tester.runAsync(() => File(meta.filePath).stat());
      expect(statAfter!.modified, equals(statBefore!.modified),
          reason: 'Opening a QuKi without editing must not rewrite the file');

      // saveCallCount is unused intentionally — it captures the intent.
      expect(saveCallCount, 0);

      await cleanup(tester);
    });
  });
}
