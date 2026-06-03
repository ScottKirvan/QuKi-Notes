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
}
