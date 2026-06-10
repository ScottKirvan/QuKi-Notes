import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'package:super_editor/super_editor.dart';

import 'package:quki_notes/app.dart';
import 'package:quki_notes/core/database/app_database.dart';
import 'package:quki_notes/core/database/database_provider.dart';
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

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildEditor() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
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
      // Post-frame callback fires after the first pump.
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

      // Open hamburger menu then tap Send...
      // Use pump with a fixed duration instead of pumpAndSettle — the editor's
      // periodic auto-save timer prevents pumpAndSettle from ever settling.
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
        overrides: [appDatabaseProvider.overrideWithValue(db)],
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

      // Chrome never changes regardless of navigator position
      expect(find.byIcon(LucideIcons.fileStack), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      await cleanup(tester);
    });

    testWidgets('root editor has no back button when QuKi loaded via provider',
        (tester) async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'quki-nav-test',
        body: const Value('nav test body'),
        createdAt: now,
        modifiedAt: now,
      ));

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // Load a QuKi into the root editor via the provider
      container.read(activeQukiIdProvider.notifier).setId('quki-nav-test');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Chrome must not change — still QuKis icon + plus + hamburger, no back
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
        (tester) async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'existing',
        body: const Value('existing content'),
        createdAt: now,
        modifiedAt: now,
      ));

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // Load the existing QuKi
      container.read(activeQukiIdProvider.notifier).setId('existing');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap + to start a new QuKi
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Provider must be null (blank QuKi)
      expect(container.read(activeQukiIdProvider), isNull);
      // Still no back button
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);
      // Existing QuKi still in DB untouched
      final row = await (db.select(db.qukis)
            ..where((t) => t.id.equals('existing')))
          .getSingleOrNull();
      expect(row?.body, 'existing content');

      await cleanup(tester);
    });

    testWidgets('SuperEditor has autocorrect and suggestions disabled (#32)',
        (tester) async {
      await tester.pumpWidget(buildEditor());
      await tester.pump();

      // super_editor 0.3.0-dev.x does not expose textCapitalization on
      // SuperEditorImeConfiguration; disabling autocorrect + suggestions is
      // the available mechanism to suppress auto-capitalization on Android IMEs.
      final superEditor = tester.widget<SuperEditor>(find.byType(SuperEditor));
      expect(
        superEditor.imeConfiguration?.enableAutocorrect,
        isFalse,
        reason: 'Autocorrect must be off to suppress IME auto-capitalization',
      );
      expect(
        superEditor.imeConfiguration?.enableSuggestions,
        isFalse,
        reason: 'Suggestions must be off to suppress IME auto-capitalization',
      );

      await cleanup(tester);
    });

    testWidgets('QuKis list animates in from the left', (tester) async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // Insert a QuKi so the icon is enabled (#86 — icon disabled when empty).
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'nav-anim-quki',
        body: const Value('content'),
        createdAt: now,
        modifiedAt: now,
      ));
      await tester.pump(); // stream emits hasQukis=true → icon enabled

      // Tap QuKis icon to push StreamScreen
      await tester.tap(find.byIcon(LucideIcons.fileStack));
      await tester.pump(); // process tap
      await tester
          .pump(Duration.zero); // drain microtasks: flush + Navigator.push
      await tester.pump(const Duration(milliseconds: 50)); // mid-animation

      // StreamScreen must be in the tree
      expect(find.byType(StreamScreen), findsOneWidget);

      // The SlideTransition that wraps StreamScreen (not just any SlideTransition
      // in the tree — super_editor also uses SlideTransition internally)
      final slideFinder = find.ancestor(
        of: find.byType(StreamScreen),
        matching: find.byType(SlideTransition),
      );
      expect(slideFinder, findsWidgets);

      // Slide comes from the left: x must be negative mid-animation
      final slide = tester.widget<SlideTransition>(slideFinder.first);
      expect(slide.position.value.dx, lessThan(0));

      await cleanup(tester);
    });
  });

  group('EditorScreen toss error handling', () {
    testWidgets(
        'shows error snackbar with Retry action when plugin throws — '
        'regression: plugin crash left UI in indeterminate state',
        (tester) async {
      // Pre-insert a QuKi so the body is non-empty and the toss path is reached.
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'toss-error-quki',
        body: const Value('some content to toss'),
        createdAt: now,
        modifiedAt: now,
      ));

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // Replace enabled transports with a single throwing one.
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

      // Load the QuKi so the editor has content.
      container.read(activeQukiIdProvider.notifier).setId('toss-error-quki');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open hamburger menu and tap Send...
      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send...'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Smart send (#85): exactly 1 transport → picker skipped, transport fires
      // directly, throws, and error snackbar appears without any sheet tap.
      expect(find.text('Send failed — unexpected error.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await cleanup(tester);
    });
  });

  group('EditorScreen smart send (#85)', () {
    testWidgets(
        'fires direct when exactly one transport is enabled — no bottom sheet shown — '
        'regression: always showed picker sheet regardless of transport count (#85)',
        (tester) async {
      // Pre-insert a QuKi so the body is non-empty.
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'smart-send-quki',
        body: const Value('smart send content'),
        createdAt: now,
        modifiedAt: now,
      ));

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // A single throwing transport — will throw if reached, confirming
          // no picker sheet is shown and the transport is called directly.
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

      container.read(activeQukiIdProvider.notifier).setId('smart-send-quki');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open hamburger menu and tap Send...
      await tester.tap(find.byIcon(LucideIcons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Send...'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // No picker sheet — the _ThrowingTransport is called directly and
      // produces the error snackbar.
      expect(find.text('Throwing Transport'), findsNothing);
      expect(find.text('Send failed — unexpected error.'), findsOneWidget);

      await cleanup(tester);
    });
  });

  group('EditorScreen QuKis icon disabled when empty (#86)', () {
    testWidgets(
        'QuKis icon is disabled when DB is empty — '
        'regression: icon was always enabled regardless of DB state (#86)',
        (tester) async {
      // DB starts empty.
      await tester.pumpWidget(buildEditor());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final iconButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(LucideIcons.fileStack),
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButton.onPressed, isNull,
          reason: 'QuKis icon must be disabled when the DB is empty');

      await cleanup(tester);
    });

    testWidgets(
        'QuKis icon is enabled after a QuKi is inserted — '
        'regression: icon did not react to DB changes (#86)', (tester) async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Icon should be disabled initially.
      final iconButtonBefore = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(LucideIcons.fileStack),
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButtonBefore.onPressed, isNull);

      // Insert a QuKi.
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'icon-test-quki',
        body: const Value('hello'),
        createdAt: now,
        modifiedAt: now,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Icon should now be enabled.
      final iconButtonAfter = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(LucideIcons.fileStack),
          matching: find.byType(IconButton),
        ),
      );
      expect(iconButtonAfter.onPressed, isNotNull,
          reason: 'QuKis icon must be enabled after a QuKi is inserted');

      await cleanup(tester);
    });
  });

  group('EditorScreen _switchDocument does not bump modifiedAt (#75)', () {
    testWidgets(
        '_switchDocument does not call notifyChanged on AutoSaveController — '
        'regression: opening a note without editing bumped modifiedAt (#75)',
        (tester) async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'no-bump-quki',
        body: const Value('load me'),
        createdAt: now,
        modifiedAt: now,
      ));

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();

      // Record modifiedAt before loading.
      final before = await db.qukisDao.getById('no-bump-quki');
      final modifiedBefore = before!.modifiedAt;

      // Load the QuKi — triggers _switchDocument.
      container.read(activeQukiIdProvider.notifier).setId('no-bump-quki');
      await tester.pump();
      // Two nested post-frame callbacks are needed to clear _isLoadingDocument
      // because super_editor fires DocumentChangeLog events across multiple
      // frames during layout/initialisation (#post-96 regression of #75).
      await tester.pump(); // first post-frame callback
      await tester
          .pump(); // second post-frame callback (clears _isLoadingDocument)
      await tester.pump(const Duration(milliseconds: 100));

      // modifiedAt must not have changed — no user edit occurred.
      final after = await db.qukisDao.getById('no-bump-quki');
      expect(after!.modifiedAt, equals(modifiedBefore),
          reason:
              'Opening a QuKi without editing must not change its modifiedAt');

      await cleanup(tester);
    });
  });
}
