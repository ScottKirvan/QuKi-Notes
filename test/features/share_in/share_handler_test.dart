import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:quki_notes/features/share_in/share_handler.dart';

// Navigation widget tests are covered by manual device testing: mounting two
// EditorScreen instances simultaneously (home + pushed) triggers a duplicate
// IME input registration in super_editor that crashes flutter_test.

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
}
