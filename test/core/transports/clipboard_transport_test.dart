import 'package:flutter_test/flutter_test.dart';
import 'package:quki_notes/core/transports/plugins/clipboard_transport.dart';
import 'package:quki_notes/core/transports/transport_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  late TransportContext ctx;

  setUp(() {
    ctx = TransportContext(
      firedAt: DateTime(2026, 1, 1),
      quki: QukiMetadata(id: 'q1', createdAt: epoch, modifiedAt: epoch),
    );
  });

  group('ClipboardTransport metadata', () {
    test('id is clipboard',
        () => expect(const ClipboardTransport().id, 'clipboard'));

    test('displayName and description are non-empty', () {
      const t = ClipboardTransport();
      expect(t.displayName, isNotEmpty);
      expect(t.description, isNotEmpty);
    });
  });

  group('ClipboardTransport.transport', () {
    test('returns success result with message', () async {
      final result = await const ClipboardTransport().transport(
        markdown: '# Hello\n\nWorld',
        images: const [],
        ctx: ctx,
      );

      expect(result.success, isTrue);
      expect(result.retryable, isFalse);
      expect(result.message, isNotNull);
    });

    test('returns success even for empty markdown', () async {
      final result = await const ClipboardTransport().transport(
        markdown: '',
        images: const [],
        ctx: ctx,
      );

      expect(result.success, isTrue);
    });
  });
}
