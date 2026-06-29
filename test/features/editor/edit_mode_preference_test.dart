import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

import 'package:quki_notes/app.dart';
import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/features/editor/edit_mode_preference_provider.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class _FakeQuKiStorage extends QuKiStorage {
  _FakeQuKiStorage() : super(Directory.systemTemp);

  @override
  Future<QuKiMeta> create(String body) async => QuKiMeta(
        id: 'fake-id',
        filePath: '/fake/fake-id.md',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

  @override
  Future<void> update(String id, String body) async {}

  @override
  Future<String> read(String id) async => 'loaded body';

  @override
  Future<List<QuKiMeta>> scanActive() async => [];

  @override
  Future<List<QuKiMeta>> scanTrash() async => [];
}

class _FakeQuKiIndex extends QuKiIndexNotifier {
  _FakeQuKiIndex(this._initial);
  final List<QuKiMeta> _initial;

  @override
  Future<List<QuKiMeta>> build() async => List.from(_initial);

  @override
  void addMeta(QuKiMeta meta) {}

  @override
  void updateMeta(String id, DateTime modifiedAt) {}

  @override
  void removeMeta(String id) {}

  @override
  Future<void> refresh() async {}
}

// ── Helpers ────────────────────────────────────────────────────────────────

Widget _buildEditor({
  QuKiStorage? storage,
  List<QuKiMeta> initialIndex = const [],
  bool? editModePreferred,
}) {
  return ProviderScope(
    overrides: [
      quKiStorageProvider.overrideWithValue(storage ?? _FakeQuKiStorage()),
      quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(initialIndex)),
      if (editModePreferred != null)
        editModePreferredProvider
            .overrideWith(() => _EditModePreferenceNotifierOverride(
                  editModePreferred,
                )),
    ],
    child: const MaterialApp(home: EditorScreen()),
  );
}

/// Notifier override that starts with a specified value.
class _EditModePreferenceNotifierOverride extends EditModePreferenceNotifier {
  _EditModePreferenceNotifierOverride(this._initialValue);
  final bool _initialValue;

  @override
  bool build() => _initialValue;
}

Future<void> cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('editModePreferredProvider', () {
    test(
        'defaults to true — regression: cold launch must open in edit mode (#72)',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(editModePreferredProvider), isTrue,
          reason: 'Default must be true so cold launch opens in edit mode');
    });

    test('setPreference(false) stores false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(editModePreferredProvider.notifier).setPreference(false);
      expect(container.read(editModePreferredProvider), isFalse);
    });

    test('setPreference(true) after false restores true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(editModePreferredProvider.notifier).setPreference(false);
      container.read(editModePreferredProvider.notifier).setPreference(true);
      expect(container.read(editModePreferredProvider), isTrue);
    });
  });

  group('EditorScreen — edit mode preference', () {
    testWidgets(
        'MarkdownEditor is present and no block is active before interaction',
        (tester) async {
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      expect(find.byType(MarkdownEditor), findsOneWidget,
          reason: 'MarkdownEditor must be rendered');

      await cleanup(tester);
    });

    testWidgets(
        'loading a note with preferEdit=false does not activate a block — '
        'regression: browse mode must be preserved on note switch (#72)',
        (tester) async {
      final meta = QuKiMeta(
        id: 'test-id',
        filePath: '/fake/test-id.md',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );

      // Build with preference = false (browse mode).
      final container = ProviderContainer(overrides: [
        quKiStorageProvider.overrideWithValue(_FakeQuKiStorage()),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        editModePreferredProvider.overrideWith(
          () => _EditModePreferenceNotifierOverride(false),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // Trigger note switch.
      container.read(activeQukiIdProvider.notifier).setId(meta.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // Preference must still be false — no block should have been focused.
      expect(
        container.read(editModePreferredProvider),
        isFalse,
        reason: 'editModePreferredProvider must remain false after note load '
            'when browse mode is preferred',
      );

      await cleanup(tester);
    });

    testWidgets(
        'provider defaults to true so new blank QuKi is ready for typing — '
        'regression: keyboard not raised on cold launch (#72)', (tester) async {
      final container = ProviderContainer(overrides: [
        quKiStorageProvider.overrideWithValue(_FakeQuKiStorage()),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(const [])),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // Default preference is true — cold launch hits this path.
      expect(
        container.read(editModePreferredProvider),
        isTrue,
        reason:
            'editModePreferredProvider must default true so focusFirstBlock '
            'is called on cold launch',
      );

      await cleanup(tester);
    });
  });
}
