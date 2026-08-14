import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'package:quki_notes/app.dart';
import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/features/stream/stream_screen.dart';

/// Fake [QuKiIndexNotifier] pre-populated with a list.
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
  void updateMeta(String id, DateTime modifiedAt) {}

  @override
  void removeMeta(String id) {
    state.whenData((list) {
      state = AsyncValue.data(list.where((m) => m.id != id).toList());
    });
  }

  @override
  Future<void> refresh() async {}
}

/// No-dart:io [QuKiStorage] stub — avoids the real-file-I/O-inside-a-
/// FakeAsync-widget-callback deadlock documented on the (skipped) tests
/// below: `_QuKiTile.initState()` calls `storage.read()` synchronously as
/// part of its own widget lifecycle, and real dart:io there hangs a
/// FakeAsync `testWidgets` zone. Used only by the delete-snackbar tests,
/// which don't need real file content — just that `softDelete()`/`read()`
/// resolve without touching the filesystem.
class _FakeQuKiStorage extends QuKiStorage {
  _FakeQuKiStorage() : super(Directory.systemTemp);

  final softDeleted = <String>[];

  @override
  Future<void> softDelete(String id) async {
    softDeleted.add(id);
  }

  @override
  Future<String> read(String id) async => '';
}

void main() {
  late Directory tmpDir;
  late QuKiStorage storage;
  late List<QuKiMeta> preloaded;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('quki_stream_test_');
    storage = QuKiStorage(tmpDir);
    preloaded = [];
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  Future<QuKiMeta> insertQuki({
    String body = '',
    DateTime? modifiedAt,
  }) async {
    final meta = await storage.create(body);
    // Patch modifiedAt in the index (real mtime can't be controlled precisely).
    final effective = modifiedAt ?? meta.modifiedAt;
    final patched = QuKiMeta(
      id: meta.id,
      filePath: meta.filePath,
      createdAt: meta.createdAt,
      modifiedAt: effective,
    );
    preloaded.add(patched);
    return patched;
  }

  Widget buildUnderTest() => ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider
              .overrideWith(() => _FakeQuKiIndex(List.from(preloaded))),
        ],
        child: const MaterialApp(home: StreamScreen()),
      );

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  group('StreamScreen', () {
    testWidgets('shows empty-state message when no QuKis', (tester) async {
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(find.textContaining('No QuKis yet'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('shows QuKi preview text in list',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      await insertQuki(body: 'Hello world');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      // _QuKiTile loads preview asynchronously — pump again to settle.
      await tester.pump(Duration.zero);
      expect(find.text('Hello world'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('strips markdown heading markers from preview',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      await insertQuki(body: '## My heading');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(find.text('My heading'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('shows (empty) for blank body',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      await insertQuki(body: '');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(find.text('(empty)'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('lists newest QuKi first',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final older = DateTime(2026, 1, 1);
      final newer = DateTime(2026, 1, 2);
      await insertQuki(body: 'Older note', modifiedAt: older);
      await insertQuki(body: 'Newer note', modifiedAt: newer);
      // Sort preloaded so the fake index returns newest-first.
      preloaded.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      final titles = tiles
          .map((t) => (t.title as Text).data)
          .where((s) => s != null && s != '…')
          .toList();
      expect(titles.first, 'Newer note');
      expect(titles.last, 'Older note');
      await cleanup(tester);
    });

    testWidgets('swipe to delete soft-deletes the QuKi',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await insertQuki(body: 'To be swiped');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      await tester.drag(find.text('To be swiped'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('To be swiped'), findsNothing);
      // File should now be in .trash/
      expect(
        await File(meta.filePath).exists(),
        isFalse,
        reason: 'Active file must be moved to trash on soft delete',
      );
      await cleanup(tester);
    });

    testWidgets('search field filters the list',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      await insertQuki(body: 'buy milk');
      await insertQuki(body: 'call dentist');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      await tester.enterText(find.byType(TextField), 'milk');
      // Wait for async search future to complete.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(Duration.zero);

      expect(find.text('buy milk'), findsOneWidget);
      expect(find.text('call dentist'), findsNothing);
      await cleanup(tester);
    });

    testWidgets('clear search button restores full list',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      await insertQuki(body: 'buy milk');
      await insertQuki(body: 'call dentist');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      await tester.enterText(find.byType(TextField), 'milk');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(Duration.zero);
      expect(find.text('call dentist'), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(find.text('call dentist'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('shows no-results message when search matches nothing',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      await insertQuki(body: 'buy milk');
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(Duration.zero);

      expect(find.textContaining('No results for'), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('app bar shows back button when pushed onto a navigator',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(const [])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => Navigator.push<void>(
                ctx,
                MaterialPageRoute(builder: (_) => const StreamScreen()),
              ),
              child: const Text('Push'),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);
      await cleanup(tester);
    });

    testWidgets('tapping QuKi row sets activeQukiIdProvider and pops',
        skip:
            true, // dart:io in widget callbacks deadlocks FakeAsync — needs QuKiStorage interface for mocking
        (tester) async {
      final meta = await insertQuki(body: 'Row tap test');

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  ctx,
                  MaterialPageRoute(builder: (_) => const StreamScreen()),
                ),
                child: const Text('Push Stream'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Push Stream'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(Duration.zero); // settle index

      expect(find.text('Row tap test'), findsOneWidget);
      await tester.tap(find.text('Row tap test'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(StreamScreen), findsNothing);
      expect(container.read(activeQukiIdProvider), meta.id);

      await cleanup(tester);
    });

    testWidgets('+ New button sets activeQukiIdProvider to null and pops',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(const [])),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeQukiIdProvider.notifier).setId('existing-id');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  ctx,
                  MaterialPageRoute(builder: (_) => const StreamScreen()),
                ),
                child: const Text('Push Stream'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Push Stream'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(StreamScreen), findsNothing);
      expect(container.read(activeQukiIdProvider), isNull);

      await cleanup(tester);
    });

    testWidgets('Ctrl+N sets activeQukiIdProvider to null and pops stream',
        (tester) async {
      if (!Platform.isWindows && !Platform.isLinux) return;

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(const [])),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeQukiIdProvider.notifier).setId('some-id');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  ctx,
                  MaterialPageRoute(builder: (_) => const StreamScreen()),
                ),
                child: const Text('Push Stream'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Push Stream'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(StreamScreen), findsNothing);
      expect(container.read(activeQukiIdProvider), isNull);

      await cleanup(tester);
    });
  });

  group('StreamScreen delete snackbar', () {
    // Replaces the former (skipped) "undo snackbar has duration >= 3s" and
    // "undo delete restores the QuKi file" tests — both asserted behavior
    // of the inline Undo action, which no longer exists. Uses
    // _FakeQuKiStorage (no real dart:io) rather than the shared
    // buildUnderTest()/real-QuKiStorage setup above, so these run for real
    // instead of joining the skipped group.
    Widget buildWithFakeStorage(QuKiStorage fakeStorage, List<QuKiMeta> index) {
      return ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(fakeStorage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(index)),
        ],
        child: const MaterialApp(home: StreamScreen()),
      );
    }

    QuKiMeta fakeMeta(String id) => QuKiMeta(
          id: id,
          filePath: '/fake/$id.md',
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
        );

    testWidgets('delete snackbar has no action and shows the expected text',
        (tester) async {
      final fakeStorage = _FakeQuKiStorage();
      final meta = fakeMeta('del-no-action');

      await tester.pumpWidget(buildWithFakeStorage(fakeStorage, [meta]));
      await tester.pump();
      await tester.pump(Duration.zero);

      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('QuKi moved to Trash.'), findsOneWidget);
      expect(
        find.byType(SnackBarAction),
        findsNothing,
        reason: 'inline Undo action removed — recovery is via the separate '
            'Recently Deleted screen only',
      );

      await cleanup(tester);
    });

    testWidgets('delete snackbar duration is 1500ms (Android LENGTH_SHORT)',
        (tester) async {
      final fakeStorage = _FakeQuKiStorage();
      final meta = fakeMeta('del-duration');

      await tester.pumpWidget(buildWithFakeStorage(fakeStorage, [meta]));
      await tester.pump();
      await tester.pump(Duration.zero);

      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.duration, const Duration(milliseconds: 1500));

      await cleanup(tester);
    });
  });

  group('StreamScreen AppBar action button spacing (density tightening)', () {
    testWidgets(
        'action IconButtons render tighter than the Material default '
        '(48x48) — fix/tighten-button-spacing', (tester) async {
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      final settingsButton = find.ancestor(
        of: find.byIcon(LucideIcons.settings),
        matching: find.byType(IconButton),
      );
      final size = tester.getSize(settingsButton);

      // Default Material IconButton in this test host (platform: android)
      // is 48x48 — asserting the actual value, not just "smaller than
      // something", so a future accidental revert to the untouched default
      // is caught.
      expect(size, isNot(const Size(48, 48)));
      expect(size.width, lessThan(48));
      expect(size.height, lessThanOrEqualTo(48));
      // Still comfortably tappable — nowhere near a drastic reduction.
      expect(size.width, greaterThanOrEqualTo(32));

      await cleanup(tester);
    });

    testWidgets(
        'adjacent action IconButtons sit closer together than the default '
        '48px-per-button spacing', (tester) async {
      await tester.pumpWidget(buildUnderTest());
      await tester.pump();

      final plusLeft = tester
          .getTopLeft(find.ancestor(
            of: find.byIcon(LucideIcons.plus),
            matching: find.byType(IconButton),
          ))
          .dx;
      final helpLeft = tester
          .getTopLeft(find.ancestor(
            of: find.byIcon(LucideIcons.circleHelp),
            matching: find.byType(IconButton),
          ))
          .dx;

      // Adjacent action buttons in the actions list — the gap between their
      // left edges is exactly one button's tightened width.
      expect(helpLeft - plusLeft, lessThan(48));

      await cleanup(tester);
    });
  });
}
