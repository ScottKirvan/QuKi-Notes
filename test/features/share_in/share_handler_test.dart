import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:quki_notes/core/database/app_database.dart';
import 'package:quki_notes/core/database/database_provider.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';
import 'package:quki_notes/features/share_in/share_handler.dart';

void main() {
  group('ShareHandler.extractText', () {
    test('returns null for empty list', () {
      expect(ShareHandler.extractText([]), isNull);
    });

    test('returns null for image-only list', () {
      expect(
        ShareHandler.extractText([
          SharedMediaFile(path: '/img.jpg', type: SharedMediaType.image),
        ]),
        isNull,
      );
    });

    test('returns single text item unchanged', () {
      expect(
        ShareHandler.extractText([
          SharedMediaFile(path: 'hello', type: SharedMediaType.text),
        ]),
        'hello',
      );
    });

    test('joins multiple text items with double newline', () {
      expect(
        ShareHandler.extractText([
          SharedMediaFile(path: 'first', type: SharedMediaType.text),
          SharedMediaFile(path: 'second', type: SharedMediaType.text),
        ]),
        'first\n\nsecond',
      );
    });

    test('ignores non-text items in a mixed list', () {
      expect(
        ShareHandler.extractText([
          SharedMediaFile(path: '/img.jpg', type: SharedMediaType.image),
          SharedMediaFile(path: 'the text', type: SharedMediaType.text),
        ]),
        'the text',
      );
    });

    test('returns null when text items have empty path', () {
      expect(
        ShareHandler.extractText([
          SharedMediaFile(path: '', type: SharedMediaType.text),
        ]),
        isNull,
      );
    });
  });

  group('platform guard', () {
    test(
        'shareStreamProvider emits nothing when not on Android '
        '— regression: Platform guard missing', () async {
      // FIXME: failing — guard not yet implemented; shareStreamProvider calls
      // ReceiveSharingIntent regardless of platform. On real Windows/Linux this
      // causes MissingPluginException at runtime; here mock values prove that
      // RSI is still invoked even when isAndroidProvider=false.
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(
              path: 'should not appear', type: SharedMediaType.text),
        ],
        mediaStream: const Stream.empty(),
      );

      final container = ProviderContainer(
        overrides: [isAndroidProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);

      final emitted = <String?>[];
      container.listen<AsyncValue<String?>>(
        shareStreamProvider,
        (_, next) => next.whenData(emitted.add),
        fireImmediately: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Without the guard, RSI is called and 'should not appear' is emitted.
      // With the guard, the stream returns early and nothing is emitted.
      expect(emitted, isEmpty);
    });
  });

  group('share-in navigation', () {
    testWidgets('share-in never pushes a second EditorScreen', (tester) async {
      // Regression test for the old behaviour (Navigator.push(EditorScreen))
      // which produced a second EditorScreen with a back button. If that
      // regression returns, find.byType(EditorScreen) will return findsWidgets
      // and this test will fail.
      //
      // The async DB insert + provider update happen on an isolate-backed
      // database and cannot reliably be asserted in FakeAsync widget tests.
      // The architectural guarantee (one root editor, never a push) is what
      // matters here; the handler logic is covered by other unit tests.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => db.close());

      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(path: 'shared text', type: SharedMediaType.text),
        ],
        mediaStream: const Stream.empty(),
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          isAndroidProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Only one EditorScreen — share-in must NOT push a second one.
      expect(find.byType(EditorScreen), findsOneWidget);
      // No back button — EditorScreen is always root.
      expect(find.byIcon(LucideIcons.arrowLeft), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  });
}
