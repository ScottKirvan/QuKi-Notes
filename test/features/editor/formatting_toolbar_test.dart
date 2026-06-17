import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';
import 'package:quki_notes/features/editor/formatting_toolbar.dart';

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
  Future<void> update(String id, String body) async {}

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
}

void main() {
  group('FormattingToolbar icon presence', () {
    test('all toolbar icon constants are defined', () {
      expect(LucideIcons.bold, isNotNull);
      expect(LucideIcons.italic, isNotNull);
      expect(LucideIcons.strikethrough, isNotNull);
      expect(LucideIcons.list, isNotNull);
      expect(LucideIcons.listOrdered, isNotNull);
      expect(LucideIcons.listChecks, isNotNull);
      expect(LucideIcons.link, isNotNull);
      expect(LucideIcons.keyboard, isNotNull);
      expect(LucideIcons.keyboardOff, isNotNull);
    });

    testWidgets('renders all expected toolbar buttons', (tester) async {
      await _pumpEditor(tester);

      expect(find.byIcon(LucideIcons.bold), findsOneWidget);
      expect(find.byIcon(LucideIcons.italic), findsOneWidget);
      expect(find.byIcon(LucideIcons.strikethrough), findsOneWidget);
      expect(find.byIcon(LucideIcons.list), findsOneWidget);
      expect(find.byIcon(LucideIcons.listOrdered), findsOneWidget);
      expect(find.byIcon(LucideIcons.listChecks), findsOneWidget);
      expect(find.byIcon(LucideIcons.link), findsOneWidget);

      await cleanup(tester);
    });

    testWidgets('formatting buttons are all disabled in Stage 1', (tester) async {
      await _pumpEditor(tester);

      IconButton getButton(IconData icon) => tester.widget<IconButton>(
            find.ancestor(
              of: find.byIcon(icon),
              matching: find.byType(IconButton),
            ),
          );

      expect(getButton(LucideIcons.bold).onPressed, isNull);
      expect(getButton(LucideIcons.italic).onPressed, isNull);
      expect(getButton(LucideIcons.strikethrough).onPressed, isNull);
      expect(getButton(LucideIcons.list).onPressed, isNull);
      expect(getButton(LucideIcons.listOrdered).onPressed, isNull);
      expect(getButton(LucideIcons.listChecks).onPressed, isNull);
      expect(getButton(LucideIcons.link).onPressed, isNull);

      await cleanup(tester);
    });
  });

  group('FormattingToolbar keyboard toggle', () {
    testWidgets(
        'shows keyboard icon at cold launch — '
        'regression: showed keyboardOff at launch because FocusNode.hasFocus '
        'was true even though IME was not visible (#post-96, #72)',
        (tester) async {
      await _pumpEditor(tester);
      await tester.pump(); // process post-frame focus request

      expect(find.byIcon(LucideIcons.keyboard), findsOneWidget,
          reason: 'At cold launch keyboard is not visible — show-keyboard icon expected');
      expect(find.byIcon(LucideIcons.keyboardOff), findsNothing);

      await cleanup(tester);
    });

    testWidgets('shows keyboardOff after tapping show-keyboard', (tester) async {
      await _pumpEditor(tester);
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.keyboard));
      await tester.pump();

      expect(find.byIcon(LucideIcons.keyboardOff), findsOneWidget);
      expect(find.byIcon(LucideIcons.keyboard), findsNothing);

      await cleanup(tester);
    });

    testWidgets('shows keyboard icon after tapping keyboardOff', (tester) async {
      await _pumpEditor(tester);
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.keyboard));
      await tester.pump();
      expect(find.byIcon(LucideIcons.keyboardOff), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.keyboardOff));
      await tester.pump();

      expect(find.byIcon(LucideIcons.keyboard), findsOneWidget);
      expect(find.byIcon(LucideIcons.keyboardOff), findsNothing);

      await cleanup(tester);
    });
  });

  group('FormattingToolbar direct widget', () {
    testWidgets('renders standalone with keyboardVisible=false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormattingToolbar(
              keyboardVisible: false,
              onToggleKeyboard: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.keyboard), findsOneWidget);
      expect(find.byIcon(LucideIcons.keyboardOff), findsNothing);
    });

    testWidgets('renders standalone with keyboardVisible=true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormattingToolbar(
              keyboardVisible: true,
              onToggleKeyboard: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.keyboardOff), findsOneWidget);
      expect(find.byIcon(LucideIcons.keyboard), findsNothing);
    });
  });
}
