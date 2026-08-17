import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
// Reaches into the package's implementation library for
// QuikiEditorState.debugForceMobile — see the mobile-visibility group's own
// setUp/tearDown below for why this is needed as of
// fix/toolbar-visibility-suppression-gap.
import 'package:markdown_live_editor/src/quiki_editor.dart';

import 'package:quki_notes/core/storage/quki_index.dart';
import 'package:quki_notes/core/storage/quki_meta.dart';
import 'package:quki_notes/core/storage/quki_storage.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';
import 'package:quki_notes/features/share_in/share_handler.dart'
    show isMobileProvider;

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

/// Same as [_pumpEditor] but overrides [isMobileProvider] to true, so
/// editor_screen.dart's FormattingToolbar/T-button visibility follows
/// MediaQuery.viewInsets.bottom instead of the desktop fallback
/// (hasActiveBlock/FocusNode.hasFocus) — see
/// notes/dev/keyboard_focus_state.md's Round 2 pivot. tester.view.viewInsets
/// is NOT touched here (stays at its default 0) — callers simulate the
/// keyboard themselves once focused, matching the real
/// requestFocus()-then-async-keyboard ordering.
Future<void> _pumpEditorMobile(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quKiStorageProvider.overrideWithValue(_FakeQuKiStorage()),
        quKiIndexProvider.overrideWith(() => _FakeQuKiIndex()),
        isMobileProvider.overrideWithValue(true),
      ],
      child: const MaterialApp(home: EditorScreen()),
    ),
  );
  await tester.pump();

  await tester.tap(find.byType(MarkdownEditor));
  await tester.pump(const Duration(milliseconds: 400));
}

/// True if the T-button's current icon widget is the markdown-mark
/// CustomPaint icon (`_MarkdownMarkIcon`, private to editor_screen.dart).
/// `runtimeType.toString()` reads the class name as plain text regardless of
/// library privacy, which is the only way to identify a private type from
/// outside its own library.
bool _tButtonShowsMarkdownMark(WidgetTester tester) {
  final button = tester.widget<IconButton>(find.ancestor(
    of: find.byTooltip('Plain text'),
    matching: find.byType(IconButton),
  ));
  return button.icon.runtimeType.toString() == '_MarkdownMarkIcon';
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

  group(
      'FormattingToolbar / T-button visibility on mobile — driven by '
      'viewInsets.bottom, not FocusNode.hasFocus '
      '(notes/dev/keyboard_focus_state.md Round 2 pivot)', () {
    // fix/toolbar-visibility-suppression-gap: editor_screen.dart's mobile
    // branch now reads MarkdownEditorController.isKeyboardVisible, which
    // forwards to QuikiEditorState.isKeyboardVisible (_showCursor()) — and
    // that getter gates on the PACKAGE's own _isMobile (Platform.isAndroid
    // || Platform.isIOS || debugForceMobile), independent of this app's
    // isMobileProvider override used by _pumpEditorMobile above. Without
    // also forcing the package's own mobile gate here, _showCursor() would
    // silently take its desktop fallback (FocusNode.hasFocus) on this
    // desktop/CI test host — which never goes false just because
    // viewInsets.bottom does — defeating the exact scenario these three
    // tests exist to catch.
    setUp(() {
      QuikiEditorState.debugForceMobile = true;
    });

    tearDown(() {
      QuikiEditorState.debugForceMobile = false;
    });

    testWidgets(
        'toolbar stays hidden and T-button shows the reading-mode icon '
        'after focusing if viewInsets.bottom is still 0 — the exact '
        "reported bug (keyboard visibly gone, but FocusNode.hasFocus can't "
        'be trusted)', (tester) async {
      await _pumpEditorMobile(tester);

      expect(tester.view.viewInsets.bottom, 0.0,
          reason: 'sanity: no keyboard inset simulated');
      expect(find.byType(FormattingToolbar), findsNothing,
          reason: 'focus alone must not be enough to show the toolbar on '
              'mobile');
      expect(find.byIcon(LucideIcons.bookOpen), findsOneWidget,
          reason: 'T-button must show the reading-mode icon, not the '
              'markdown-mark edit-mode icon, while no keyboard inset is '
              'present');
      expect(_tButtonShowsMarkdownMark(tester), isFalse);

      await cleanup(tester);
      tester.view.resetViewInsets();
    });

    testWidgets(
        'toolbar appears and T-button switches to the markdown-mark icon '
        'once viewInsets.bottom > 0', (tester) async {
      await _pumpEditorMobile(tester);
      expect(find.byType(FormattingToolbar), findsNothing);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();

      expect(find.byType(FormattingToolbar), findsOneWidget,
          reason: 'viewInsets.bottom > 0 while focused must show the '
              'toolbar');
      expect(_tButtonShowsMarkdownMark(tester), isTrue,
          reason: 'T-button must switch to the markdown-mark edit-mode icon');
      expect(find.byIcon(LucideIcons.bookOpen), findsNothing);

      await cleanup(tester);
      tester.view.resetViewInsets();
    });

    testWidgets(
        'toolbar hides again and T-button reverts to the reading-mode icon '
        'when viewInsets.bottom returns to 0 while focus remains true — '
        "mirrors Round 1's one open risk (Android's own keyboard-dismiss "
        'icon not clearing focus)', (tester) async {
      await _pumpEditorMobile(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(find.byType(FormattingToolbar), findsOneWidget);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();

      expect(find.byType(FormattingToolbar), findsNothing,
          reason: 'toolbar must hide when the keyboard visibly goes away, '
              'even if focus never changed');
      expect(_tButtonShowsMarkdownMark(tester), isFalse);
      expect(find.byIcon(LucideIcons.bookOpen), findsOneWidget);

      await cleanup(tester);
      tester.view.resetViewInsets();
    });
  });

  group('FormattingToolbar / T-button visibility on desktop (non-regression)',
      () {
    // isMobileProvider deliberately left at its real default (false on this
    // desktop/CI test host) — desktop has no software keyboard, so it must
    // keep following FocusNode.hasFocus via hasActiveBlock, exactly as
    // _pumpEditor's two pre-existing tests above already rely on implicitly.

    testWidgets(
        'toolbar and markdown-mark icon show on focus alone, with '
        'viewInsets.bottom pinned at 0', (tester) async {
      await _pumpEditor(tester);

      expect(tester.view.viewInsets.bottom, 0.0,
          reason: 'sanity: desktop never raises this');
      expect(find.byType(FormattingToolbar), findsOneWidget,
          reason: 'on desktop, focus alone must still be sufficient');
      expect(_tButtonShowsMarkdownMark(tester), isTrue);

      await cleanup(tester);
    });
  });
}
