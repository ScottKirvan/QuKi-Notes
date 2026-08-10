import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';

Future<void> cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

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
  Future<DateTime> update(String id, String body,
          {DateTime? modifiedAt}) async =>
      modifiedAt?.toUtc() ?? DateTime.now().toUtc();

  @override
  Future<String> read(String id) async => '';

  @override
  Future<List<QuKiMeta>> scanActive() async => [];

  @override
  Future<List<QuKiMeta>> scanTrash() async => [];
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

Future<void> _pumpEditor(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quKiStorageProvider.overrideWithValue(_FakeQuKiStorage()),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
      ],
      child: const MaterialApp(home: EditorScreen()),
    ),
  );
  await tester.pump();

  // FormattingToolbar only renders while the editor is focused (reading vs.
  // edit mode) — there is no cold-launch auto-focus (it never worked
  // reliably in practice and was removed, 2026-08-09), so tests must tap to
  // focus the same way a real user would.
  //
  // The pump here is deliberately longer than kDoubleTapTimeout: a
  // double-tap recognizer shares this GestureDetector's gesture arena
  // (feat/selection-stage1), so any tap through it delays onTapDown's own
  // resolution — including the requestFocus() call inside it — until
  // DoubleTapGestureRecognizer gives up waiting for a second tap. See the
  // identical pattern in editor_screen_test.dart.
  await tester.tap(find.byType(MarkdownEditor));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('FormattingToolbar — Stage 2 (package toolbar)', () {
    testWidgets('renders all expected toolbar buttons', (tester) async {
      await _pumpEditor(tester);

      expect(find.byIcon(LucideIcons.bold), findsOneWidget);
      expect(find.byIcon(LucideIcons.italic), findsOneWidget);
      expect(find.byIcon(LucideIcons.strikethrough), findsOneWidget);
      expect(find.byIcon(LucideIcons.list), findsOneWidget);
      expect(find.byIcon(LucideIcons.listOrdered), findsOneWidget);
      expect(find.byIcon(LucideIcons.heading1), findsOneWidget);
      expect(find.byIcon(LucideIcons.listChecks), findsOneWidget);

      await cleanup(tester);
    });

    testWidgets('formatting buttons are all enabled in Stage 2',
        (tester) async {
      await _pumpEditor(tester);

      IconButton getButton(IconData icon) => tester.widget<IconButton>(
            find.ancestor(
              of: find.byIcon(icon),
              matching: find.byType(IconButton),
            ),
          );

      expect(getButton(LucideIcons.bold).onPressed, isNotNull);
      expect(getButton(LucideIcons.italic).onPressed, isNotNull);
      expect(getButton(LucideIcons.strikethrough).onPressed, isNotNull);
      expect(getButton(LucideIcons.list).onPressed, isNotNull);
      expect(getButton(LucideIcons.listOrdered).onPressed, isNotNull);
      expect(getButton(LucideIcons.heading1).onPressed, isNotNull);
      expect(getButton(LucideIcons.listChecks).onPressed, isNotNull);

      await cleanup(tester);
    });
  });
}
