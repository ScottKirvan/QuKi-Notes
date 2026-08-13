import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:path/path.dart' as p;
// Reaches into the package's implementation library rather than its public
// barrel — the same convention the package's own tests already use (see
// e.g. packages/markdown_live_editor/test/checkbox_hit_target_test.dart) to
// get at QuikiRenderEditor/QuikiRenderWidget for real tap-coordinate
// geometry. Needed here to drive a REAL tap gesture at a checkbox's actual
// painted position through the full EditorScreen tree — the only way to
// exercise EditorScreen._onCheckboxToggle (#354) as production code, rather
// than calling it directly (it's private).
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

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
  final softDeleted = <String>[];

  // Not overridden by default: QuKiStorage.softDelete() does real dart:io
  // (File.exists()/rename()) against Directory.systemTemp, which — unlike
  // the create/update overrides below — would hit real I/O from inside a
  // FakeAsync testWidgets zone. Override it the same way create/update
  // already are, tracking calls instead of touching the filesystem.
  @override
  Future<void> softDelete(String id) async {
    softDeleted.add(id);
  }

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
  Future<DateTime> update(String id, String body,
      {DateTime? modifiedAt}) async {
    saves.add((id: id, body: body));
    return modifiedAt?.toUtc() ?? DateTime.now().toUtc();
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
    state.whenData((list) =>
        state = AsyncValue.data(list.where((m) => m.id != id).toList()));
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
  Future<TransportResult> transport({
    required String markdown,
    required List<TransportImage> images,
    required TransportContext ctx,
  }) async {
    throw Exception('transport error');
  }
}

Widget _buildEditor(
    {QuKiStorage? storage, List<QuKiMeta> initialIndex = const []}) {
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

QuikiRenderEditor _renderEditorOf(WidgetTester tester) =>
    tester.renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));

/// The global screen position of [slot]'s actual painted checkbox box.
///
/// Mirrors packages/markdown_live_editor/test/checkbox_hit_target_test.dart's
/// own `checkboxTapPoint`-equivalent geometry (kept as its own copy here,
/// per this codebase's existing convention of each test file owning its own
/// self-contained geometry helpers rather than sharing one across the app
/// and the package). Deliberately targets the exact glyph center — not the
/// #352 widened hit-test zone — so this test exercises only
/// EditorScreen._onCheckboxToggle's marker-read logic (#354), independent of
/// the separate hit-test-zone fix already on this branch.
Offset _checkboxTapPoint(
  WidgetTester tester,
  QuikiRenderEditor ro,
  CheckboxSlot slot,
) {
  final caret = ro.getOffsetForCaret(TextPosition(offset: slot.element.start));
  final lineHeight = ro.preferredLineHeight;
  final boxSize = lineHeight * 0.8;
  final tapX = caret.dx - 4.0 - boxSize / 2;
  final boxTop = caret.dy + (lineHeight - boxSize) / 2 + lineHeight / 3;
  final tapY = boxTop + boxSize / 2;
  final local = Offset(tapX, tapY) + ro.localPadding.topLeft;
  return tester.getTopLeft(find.byType(QuikiRenderWidget)) + local;
}

/// Settles the delayed single-tap resolution this editor's GestureDetector
/// always has — an onDoubleTapDown callback is unconditionally wired
/// alongside onTapDown (see packages/markdown_live_editor/test/
/// reading_mode_safety_test.dart's identically-named helper for the full
/// explanation), so onTapDown itself — including the checkbox-toggle branch
/// this test depends on — is deferred until kDoubleTapTimeout has elapsed
/// with no second tap.
Future<void> _settleSingleTap(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

/// Loads [body] into a fresh [EditorScreen], taps its single checkbox
/// (assumed to be the only one in [body]), waits past the auto-save
/// debounce, and returns the persisted file content.
///
/// Verifies via the FILE, not `tester.testTextInput.editingState` —
/// an existing QuKi loads into READING mode
/// (`_editorController.unfocus()` in `_onActiveQukiChanged`), which closes
/// the TextInputConnection. A checkbox toggle's `setValuePreservingSelection`
/// call is deliberately reading-mode-safe (#335/#266) — it must NOT
/// reconnect or request focus as a side effect — so there is no open
/// connection to push `editingState` through, and reading it back would
/// simply be null/stale regardless of whether the toggle itself worked.
/// Reading the file after the debounce is a reliable signal independent of
/// connection state, and doubles as this task's required persistence check.
Future<String> _toggleAndReadDisk(
  WidgetTester tester, {
  required String body,
}) async {
  late Directory tmpDir;
  late QuKiStorage storage;
  late QuKiMeta meta;

  await tester.runAsync(() async {
    tmpDir = await Directory.systemTemp.createTemp('quki_checkbox_toggle_');
    storage = QuKiStorage(tmpDir);
    meta = await storage.create(body);
  });
  addTearDown(() => tmpDir.delete(recursive: true));

  final container = ProviderContainer(
    overrides: [
      quKiStorageProvider.overrideWithValue(storage),
      quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: EditorScreen()),
    ),
  );
  await tester.pump();

  await tester.runAsync(() async {
    container.read(activeQukiIdProvider.notifier).setId(meta.id);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.pump();

  final ro = _renderEditorOf(tester);
  final slot = ro.renderModel.checkboxSlots.single;
  await tester.tapAt(_checkboxTapPoint(tester, ro, slot));
  await _settleSingleTap(tester);

  // Force an immediate flush rather than waiting on the 2s debounce Timer.
  // A Timer created during the tap (inside the widget test's fake-async
  // zone) only fires on a matching tester.pump(duration) — but the real
  // dart:io write its callback performs needs the REAL event loop to
  // actually complete, which tester.runAsync provides but does not itself
  // advance fake timers. Mixing the two reliably requires either driving
  // the Timer via fake pumps and separately re-entering runAsync for the
  // write (fragile to get the ordering right), or sidestepping the Timer
  // entirely: EditorScreen.didChangeAppLifecycleState already calls
  // _autoSave.save() directly and unconditionally on inactive/paused/
  // detached — the exact same underlying save this test needs — so
  // simulating that lifecycle transition inside tester.runAsync (mirroring
  // test/features/setup/storage_setup_screen_test.dart's existing
  // WidgetsBinding.instance.handleAppLifecycleStateChanged usage) triggers
  // one real, awaitable save without depending on Timer/FakeAsync timing at
  // all.
  // Poll the file rather than sleeping a fixed duration: a fixed real delay
  // (previously 300ms) was observed to be flaky under full-suite load — the
  // real dart:io write occasionally hadn't completed yet when a fixed sleep
  // elapsed, even though it always completes given enough time. Polling
  // with a generous overall timeout removes the timing assumption; the
  // "file no longer matches the ORIGINAL body" condition is a stand-in for
  // "the write is done" — a genuine toggle failure (the thing this test
  // guards against) instead exhausts the timeout and returns the unchanged
  // original body, which the caller's `expect` correctly flags as a
  // mismatch rather than this helper hanging or throwing.
  final onDisk = await tester.runAsync(() async {
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final file = File(meta.filePath);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    // QuKiStorage.update() writes to a temp file then renames over the
    // target (CLAUDE.md: "write-to-temp-then-rename for atomicity") — the
    // rename briefly makes the destination path momentarily inaccessible on
    // Windows, where a concurrent read during that instant throws
    // (FileSystemException / PathAccessException) rather than just
    // returning stale content. Observed as a genuine full-suite-only
    // flake (never reproduced running this file alone, where there's no
    // contention): treat a transient read failure the same as "not written
    // yet" and retry, instead of letting it escape and fail the test.
    String? content;
    while (DateTime.now().isBefore(deadline)) {
      try {
        content = await file.readAsString();
        if (content != body) break;
      } catch (_) {
        // Transient — most likely mid-rename. Fall through to retry.
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return content ?? body;
  });
  await tester.pump();

  // Tear down the widget tree (disposes EditorScreen -> AutoSaveController
  // .dispose(), cancelling the ORIGINAL debounce Timer notifyChanged()
  // scheduled from the tap, which was never cancelled by the lifecycle-
  // triggered save above — AutoSaveController.save() doesn't cancel
  // _debounce, only flush() does) before the caller's addTearDown deletes
  // the temp directory — otherwise that still-pending real Timer can fire
  // and race a concurrent write against the directory deletion.
  await cleanup(tester);

  return onDisk!;
}

void main() {
  group('EditorScreen renders', () {
    testWidgets('shows MarkdownEditor on launch with QuikiEditor',
        (tester) async {
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      // ADR-31 Stage 1: MarkdownEditor now wraps QuikiEditor (custom RenderObject).
      expect(find.byType(MarkdownEditor), findsOneWidget);

      await cleanup(tester);
    });

    testWidgets(
        'shows QuKis icon, + button, Send, Settings — no back button or hamburger',
        (tester) async {
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      expect(find.byIcon(LucideIcons.fileStack), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsOneWidget);
      expect(find.byIcon(LucideIcons.settings), findsOneWidget);
      expect(find.byIcon(LucideIcons.menu), findsNothing);
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      await cleanup(tester);
    });

    testWidgets('Send and Settings are standalone IconButtons (#251)',
        (tester) async {
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      // Send and Settings are direct AppBar actions — no popup required.
      expect(find.byIcon(LucideIcons.send), findsOneWidget);
      expect(find.byIcon(LucideIcons.settings), findsOneWidget);
      expect(find.byType(PopupMenuButton), findsNothing);

      await cleanup(tester);
    });
  });

  group('EditorScreen navigation', () {
    testWidgets(
        'no back button even when navigator-pushed — EditorScreen is always root',
        (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
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
        ),
      );
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
            matching: find.byType(IconButton)),
      );
      expect(
        iconButton.onPressed,
        isNull,
        reason: 'QuKis icon must be disabled when the index is empty',
      );

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
            matching: find.byType(IconButton)),
      );
      expect(
        iconButton.onPressed,
        isNotNull,
        reason: 'QuKis icon must be enabled when there are QuKis',
      );

      await cleanup(tester);
    });
  });

  group('EditorScreen transport — snackbars', () {
    testWidgets('empty-body guard snackbar has duration ≤ 3s', (tester) async {
      await tester.pumpWidget(_buildEditor());
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.send));
      await tester.pump();

      expect(find.text('Nothing to send — write something first.'),
          findsOneWidget);
      final snackBar = tester.firstWidget<SnackBar>(
        find.ancestor(
          of: find.text('Nothing to send — write something first.'),
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            quKiStorageProvider.overrideWithValue(_FakeQuKiStorage()),
            quKiIndexProvider.overrideWith(() => _FakeQuKiIndex(const [])),
            enabledTransportsProvider
                .overrideWithValue(const [_ThrowingTransport()]),
          ],
          child: const MaterialApp(home: EditorScreen()),
        ),
      );
      await tester.pump();

      // Focus the editor and inject text via the TextInputClient.
      //
      // The pump here is deliberately longer than kDoubleTapTimeout — see
      // the identical pattern earlier in this file (auto-save debounce
      // test) for the full explanation.
      await tester.tap(find.byType(MarkdownEditor));
      await tester.pump(const Duration(milliseconds: 400));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
            text: 'type me', selection: TextSelection.collapsed(offset: 7)),
      );
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.send));

      // Multiple pumps to let the async transport chain (flush → transport →
      // snackbar) settle.
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

      // Focus the editor and inject text via the TextInputClient.
      //
      // The pump here is deliberately longer than kDoubleTapTimeout: a
      // double-tap recognizer shares this GestureDetector's gesture arena
      // (feat/selection-stage1), so any tap through it delays onTapDown's
      // own resolution — including the requestFocus() call inside it —
      // until DoubleTapGestureRecognizer gives up waiting for a second tap.
      // See the identical pattern a few tests below this one.
      await tester.tap(find.byType(MarkdownEditor));
      await tester.pump(const Duration(milliseconds: 400));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'debounce test',
          selection: TextSelection.collapsed(offset: 13),
        ),
      );
      await tester.pump();

      // Advance past the 2s debounce — timer fires, save() runs.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(); // flush async save completion

      expect(
        storage.saves,
        isNotEmpty,
        reason: 'AutoSaveController must write after debounce fires',
      );
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

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EditorScreen()),
        ),
      );
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

      expect(
        statAfter!.modified,
        equals(statBefore!.modified),
        reason: 'mtime must not change when a QuKi is loaded without editing',
      );

      await cleanup(tester);
    });
  });

  group('EditorScreen switching QuKi', () {
    testWidgets('loads body of the selected QuKi into the editor',
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

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EditorScreen()),
        ),
      );
      await tester.pump();

      // Focus the editor so QuikiEditorState opens a TextInputConnection.
      // When setValue is called after load, the IME state will be updated.
      //
      // The pump here is deliberately longer than kDoubleTapTimeout: now
      // that a double-tap recognizer shares this GestureDetector's gesture
      // arena (feat/selection-stage1), any tap through it schedules
      // DoubleTapGestureRecognizer's internal "forget the last tap" timer,
      // which must be allowed to fire before the test ends or flutter_test's
      // own teardown assertion ('A Timer is still pending even after the
      // widget tree was disposed') fails — a test-harness bookkeeping
      // requirement, unrelated to app correctness. See
      // packages/markdown_live_editor/test/selection_test.dart's
      // doubleTapAt() doc comment for the full explanation.
      await tester.tap(find.byType(MarkdownEditor));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      // ADR-31 Stage 1: content is in the QuikiEditor's internal buffer.
      // Verify via the IME editing state that was pushed to the platform.
      expect(
        tester.testTextInput.editingState!['text'],
        'switched content',
        reason: 'Editor must display the loaded QuKi body after switch',
      );

      await cleanup(tester);
    });
  });

  group('EditorScreen checkbox toggle (#354)', () {
    testWidgets(
        'tapping a non-nested checkbox toggles it — regression guard: must '
        'keep working after the #354 fix', (tester) async {
      // 'Notes' precedes the checklist so the loaded cursor position
      // (offset 0, from MarkdownEditorController.setValue's document-switch
      // reset) lands in a plain line, not inside the checkbox element's own
      // [start, end] range — otherwise RenderModel would reveal the
      // checkbox as raw source (cursor-position reveal is not gated on
      // focus, see render_model.dart) and it would have no CheckboxSlot to
      // tap at all, unrelated to what this test means to exercise.
      final onDisk = await _toggleAndReadDisk(
        tester,
        body: 'Notes\n- [ ] Task',
      );

      expect(onDisk, 'Notes\n- [x] Task',
          reason: 'a non-nested checkbox must still toggle, and persist, '
              'after the #354 fix');
    });

    testWidgets(
        'tapping a NESTED checkbox toggles it — regression: #354, '
        'EditorScreen._onCheckboxToggle read a fixed 6-char marker starting '
        'exactly at the checkbox\'s source offset (the line\'s absolute '
        'start, before the leading indentation whitespace) and silently '
        'no-oped when it landed on whitespace instead', (tester) async {
      final onDisk = await _toggleAndReadDisk(
        tester,
        body: '- Parent\n  - [ ] Nested task',
      );

      expect(onDisk, '- Parent\n  - [x] Nested task',
          reason: 'a nested checkbox must toggle — and persist via the '
              'unchanged auto-save path — exactly like a non-nested one, '
              'regardless of leading whitespace length (#354)');
    });
  });

  group('EditorScreen delete button', () {
    testWidgets(
        'disabled on a brand-new, never-saved note — enabled once the '
        'first autosave lands', (tester) async {
      final storage = _FakeQuKiStorage();
      await tester.pumpWidget(_buildEditor(storage: storage));
      await tester.pump();
      await tester.pump(Duration.zero);

      IconButton trashButton() => tester.widget<IconButton>(
            find.ancestor(
                of: find.byIcon(LucideIcons.trash2),
                matching: find.byType(IconButton)),
          );

      expect(
        trashButton().onPressed,
        isNull,
        reason: 'Trash button must be disabled before the note is ever saved',
      );

      // Focus, type, and wait past the 2s debounce to trigger the first
      // autosave. See the identical pattern in the auto-save group above
      // for why the initial pump is longer than kDoubleTapTimeout.
      await tester.tap(find.byType(MarkdownEditor));
      await tester.pump(const Duration(milliseconds: 400));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(
        trashButton().onPressed,
        isNotNull,
        reason: 'Trash button must enable once the note has been saved once '
            '— the same quKiIndexProvider rebuild trigger already used to '
            'gate the QuKis-list icon (#86)',
      );

      await cleanup(tester);
    });

    testWidgets(
        'tapping Trash soft-deletes the active QuKi, removes it from the '
        'index, and lands on a blank new note (same end state as +New)',
        (tester) async {
      late Directory tmpDir;
      late QuKiStorage storage;
      late QuKiMeta meta;

      await tester.runAsync(() async {
        tmpDir = await Directory.systemTemp.createTemp('quki_editor_delete_');
        storage = QuKiStorage(tmpDir);
        meta = await storage.create('delete me');
      });
      addTearDown(() => tmpDir.delete(recursive: true));

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EditorScreen()),
        ),
      );
      await tester.pump();

      // Open the note via activeQukiIdProvider, same as tapping it from the
      // QuKis list — this is the branch where activeQukiIdProvider ==
      // AutoSaveController.savedId, so deleting it must also clear
      // activeQukiIdProvider back to null via the existing ref.listen path.
      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      // The Trash button's onPressed calls storage.softDelete(), a real
      // dart:io rename — run the tap itself inside runAsync so the real
      // write actually gets a chance to complete against the real event
      // loop rather than being left dangling in FakeAsync's zone.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(LucideIcons.trash2));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      final stillAtActivePath =
          await tester.runAsync(() => File(meta.filePath).exists());

      expect(
        stillAtActivePath,
        isFalse,
        reason: 'the active file must be moved to trash on delete',
      );

      expect(
        container.read(quKiIndexProvider).value,
        isEmpty,
        reason: 'the deleted QuKi must be removed from the index',
      );
      expect(
        container.read(activeQukiIdProvider),
        isNull,
        reason: 'activeQukiIdProvider must reset to null, same as +New',
      );

      final trashButton = tester.widget<IconButton>(
        find.ancestor(
            of: find.byIcon(LucideIcons.trash2),
            matching: find.byType(IconButton)),
      );
      expect(
        trashButton.onPressed,
        isNull,
        reason: 'Trash button must disable again — AutoSaveController.'
            'savedId must reset to null, same as landing on a brand-new '
            'note via +New',
      );

      await cleanup(tester);
    });

    testWidgets('a pending autosave does not resurrect the just-deleted QuKi',
        (tester) async {
      late Directory tmpDir;
      late QuKiStorage storage;
      late QuKiMeta meta;

      await tester.runAsync(() async {
        tmpDir =
            await Directory.systemTemp.createTemp('quki_editor_delete_race_');
        storage = QuKiStorage(tmpDir);
        meta = await storage.create('original content');
      });
      addTearDown(() => tmpDir.delete(recursive: true));

      final container = ProviderContainer(
        overrides: [
          quKiStorageProvider.overrideWithValue(storage),
          quKiIndexProvider.overrideWith(() => _FakeQuKiIndex([meta])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: EditorScreen()),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        container.read(activeQukiIdProvider.notifier).setId(meta.id);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      // Focus (an existing note loads into reading mode) and type, leaving
      // a 2s debounce Timer scheduled but NOT yet fired.
      await tester.tap(find.byType(MarkdownEditor));
      await tester.pump(const Duration(milliseconds: 400));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'unsaved edit',
          selection: TextSelection.collapsed(offset: 12),
        ),
      );
      await tester.pump();

      // Tap Trash before that debounce ever fires. The Trash button's
      // onPressed calls storage.softDelete(), a real dart:io rename — run
      // the tap itself inside runAsync so that real I/O actually gets to
      // complete against the real event loop, rather than being left
      // dangling in FakeAsync's zone.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(LucideIcons.trash2));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump();

      // Advance well past both the 2s debounce and the 30s periodic
      // interval. Neither can reach real dart:io here even if still
      // pending: AutoSaveController.save() bails out on an empty body
      // before ever calling the write callback, and _deleteCurrentQuki
      // clears the editor to '' before the delete even starts — so this is
      // safe to pump through directly, without tester.runAsync, exactly
      // because the guard being tested makes it a no-op.
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      final activeExists =
          await tester.runAsync(() => File(meta.filePath).exists());
      expect(
        activeExists,
        isFalse,
        reason: 'a pending autosave must not resurrect the deleted QuKi at '
            'its original active path',
      );

      final trashPath = p.join(tmpDir.path, '.trash', '${meta.id}.md');
      final trashedContent =
          await tester.runAsync(() => File(trashPath).readAsString());
      expect(
        trashedContent,
        'original content',
        reason: 'the trashed file must retain its original content — a '
            'stale pending autosave must not overwrite it after the fact',
      );

      await cleanup(tester);
    });

    testWidgets('delete snackbar has no action and shows the expected text',
        (tester) async {
      final storage = _FakeQuKiStorage();
      await tester.pumpWidget(_buildEditor(storage: storage));
      await tester.pump();

      await tester.tap(find.byType(MarkdownEditor));
      await tester.pump(const Duration(milliseconds: 400));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'to delete',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.trash2));
      await tester.pump();
      await tester.pump();

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
      final storage = _FakeQuKiStorage();
      await tester.pumpWidget(_buildEditor(storage: storage));
      await tester.pump();

      await tester.tap(find.byType(MarkdownEditor));
      await tester.pump(const Duration(milliseconds: 400));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'to delete',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      await tester.tap(find.byIcon(LucideIcons.trash2));
      await tester.pump();
      await tester.pump();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.duration, const Duration(milliseconds: 1500));

      await cleanup(tester);
    });
  });
}
