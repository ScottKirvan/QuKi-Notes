import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

import 'package:quki_notes/app.dart';
import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/core/transports/registry_provider.dart';
import 'package:quki_notes/core/transports/transport_plugin.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';

// In-memory storage: no dart:io, safe inside FakeAsync.
class _FakeQuKiStorage extends QuKiStorage {
  _FakeQuKiStorage() : super(Directory.systemTemp);

  final saves = <({String? id, String body})>[];

  @override
  Future<QuKiMeta> create(String body) async {
    saves.add((id: null, body: body));
    return QuKiMeta(
      id: 'fake-id',
      filePath: '/fake/fake-id.md',
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
  }

  @override
  Future<void> update(String id, String body) async {
    saves.add((id: id, body: body));
  }

  @override
  Future<String> read(String id) async => '';

  @override
  Future<List<QuKiMeta>> scanActive() async => [];

  @override
  Future<List<QuKiMeta>> scanTrash() async => [];
}

// Fake index notifier — holds a pre-built list.
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
    state.whenData(
      (list) => state = AsyncValue.data(list.where((m) => m.id != id).toList()),
    );
  }

  @override
  Future<void> refresh() async {}
}

// Transport that always throws — verifies error snackbar.
class _ThrowingTransport extends TransportPlugin {
  const _ThrowingTransport();

  @override
  String get id => 'throwing';

  @override
  String get displayName => 'Throwing Transport';

  @override
  String get description => 'Always throws.';

  @override
  Future<TossResult> toss({
    required String markdown,
    required List<TossImage> images,
    required TossContext ctx,
  }) async {
    throw Exception('transport error');
  }
}

Widget _buildEditor({
  QuKiStorage? storage,
  List<QuKiMeta> initialIndex = const [],
}) {
  final s = storage ?? _FakeQuKiStorage();
  return ProviderScope(
    overrides: [
      quKiStorageProvider.overrideWithValue(s),
      quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(initialIndex)),
    ],
    child: const MaterialApp(home: EditorScreen()),
  );
}

Future<void> cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  group('EditorScreen renders', () {
    testWidgets('shows MarkdownEditor on launch in view mode', (tester) async {
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      // Block mode: MarkdownEditor renders blocks as MarkdownBody widgets;
      // no TextField is active until the user taps a block.
      expect(find.byType(MarkdownEditor), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: 'No block should be in edit mode on launch (no autofocus)');

      await cleanup(tester);
    });

    testWidgets('shows QuKis icon, + button, hamburger — no back button',
        (tester) async {
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      expect(find.byIcon(LucideIcons.fileStack), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      expect(find.byIcon(LucideIcons.menu), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      await cleanup(tester);
    });

    testWidgets('hamburger menu contains Send..., QuKis, Settings',
        (tester) async {
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Send...'), findsOneWidget);
      expect(find.text('QuKis'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await cleanup(tester);
    });
  });

  group('EditorScreen navigation', () {
    testWidgets(
        'no back button even when navigator-pushed — EditorScreen is always root',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(_FakeQuKiStorage()),
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
  });

  group('EditorScreen QuKis icon (#86)', () {
    testWidgets(
        'disabled when index is empty — '
        'regression: icon was always enabled regardless of DB state (#86)',
        (tester) async {
      await tester.pumpWidget(_buildEditor());
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
        'enabled when index has items — '
        'regression: icon did not react to index changes (#86)',
        (tester) async {
      final meta = QuKiMeta(
        id: 'test-id',
        filePath: '/fake/test-id.md',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      await tester.pumpWidget(_buildEditor(initialIndex: [meta]));
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

  group('EditorScreen toss — snackbars', () {
    testWidgets('empty-body guard snackbar has duration ≤ 3s', (tester) async {
      await tester.pumpWidget(_buildEditor());
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

    testWidgets(
        'shows error snackbar with Retry when plugin throws — '
        'regression: plugin crash left UI in indeterminate state',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          quKiStorageProvider.overrideWithValue(_FakeQuKiStorage()),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(const [])),
          enabledTransportsProvider
              .overrideWithValue(const [_ThrowingTransport()]),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // Switch to plain-text mode so there is a single TextField to type into.
      await tester.tap(find.byIcon(LucideIcons.type));
      await tester.pump();

      // Type content so the empty-body guard does not fire.
      await tester.enterText(find.byType(TextField), 'toss me');
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send...'));

      // Multiple pumps to let the async toss chain (flush → toss → snackbar) settle.
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Send failed — unexpected error.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await cleanup(tester);
    });
  });

  group('EditorScreen auto-save', () {
    testWidgets('typing triggers write after 2s debounce', (tester) async {
      final storage = _FakeQuKiStorage();

      await tester.pumpWidget(_buildEditor(storage: storage));
      await tester.pump();

      // Switch to plain-text mode so there is a single TextField to type into.
      await tester.tap(find.byIcon(LucideIcons.type));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'debounce test');
      await tester.pump();

      // Advance past the 2s debounce — timer fires, save() runs.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(); // flush async save completion

      expect(storage.saves, isNotEmpty,
          reason: 'AutoSaveController must write after debounce fires');
      expect(storage.saves.first.body, 'debounce test');

      await cleanup(tester);
    });

    testWidgets(
        'loading a QuKi without editing does not rewrite the file — '
        'regression: _onActiveQukiChanged triggered spurious saves (#75)',
        (tester) async {
      late Directory tmpDir;
      late QuKiStorage storage;
      late QuKiMeta meta;

      await tester.runAsync(() async {
        tmpDir = await Directory.systemTemp.createTemp('quki_editor_nosave_');
        storage = QuKiStorage(tmpDir);
        meta = await storage.create('do not touch');
      });
      addTearDown(() => tmpDir.delete(recursive: true));

      final statBefore =
          await tester.runAsync(() => File(meta.filePath).stat());

      final container = ProviderContainer(overrides: [
        quKiStorageProvider.overrideWithValue(storage),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // setId triggers _onActiveQukiChanged → read → setValue.
      // No edit follows, so AutoSaveController must not write.
      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      final statAfter = await tester.runAsync(() => File(meta.filePath).stat());

      expect(statAfter!.modified, equals(statBefore!.modified),
          reason:
              'mtime must not change when a QuKi is loaded without editing');

      await cleanup(tester);
    });
  });

  group('EditorScreen switching QuKi', () {
    testWidgets('loads body of the selected QuKi into the TextField',
        (tester) async {
      late Directory tmpDir;
      late QuKiStorage storage;
      late QuKiMeta meta;

      await tester.runAsync(() async {
        tmpDir = await Directory.systemTemp.createTemp('quki_editor_switch_');
        storage = QuKiStorage(tmpDir);
        meta = await storage.create('switched content');
      });
      addTearDown(() => tmpDir.delete(recursive: true));

      final container = ProviderContainer(overrides: [
        quKiStorageProvider.overrideWithValue(storage),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
      ]);
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

      // In block mode content is rendered by MarkdownBody.  Read its data
      // directly — no need to enter edit mode to verify the load.
      final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody).first);
      expect(body.data, 'switched content',
          reason: 'Editor must display the loaded QuKi body after switch');

      await cleanup(tester);
    });
  });
}
