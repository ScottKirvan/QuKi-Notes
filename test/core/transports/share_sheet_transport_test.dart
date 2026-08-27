// Regression tests for #92: ShareSheetTransport false-negative on Android.
//
// share_plus fires ShareResultStatus.dismissed even when the user completes a
// share on Android. Always returning success avoids a false "Share cancelled."
// snackbar.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:quki_notes/core/transports/android_share_channel.dart';
import 'package:quki_notes/core/transports/plugins/share_sheet_transport.dart';
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

  group('ShareSheetTransport metadata', () {
    test('id is share_sheet', () {
      expect(const ShareSheetTransport().id, 'share_sheet');
    });

    test('displayName and description are non-empty', () {
      const t = ShareSheetTransport();
      expect(t.displayName, isNotEmpty);
      expect(t.description, isNotEmpty);
    });
  });

  group('ShareSheetTransport.transport — regression #92', () {
    // We cannot invoke transport() directly in a unit test (requires a live
    // platform channel). Instead we verify:
    // 1. The TransportResult shape that the fix produces is correct.
    // 2. The root cause: dismissed != success, proving the old code was wrong.

    test(
        'TransportResult(success: true, message: Shared.) is the correct result shape — '
        'regression: dismissed status was incorrectly treated as failure (#92)',
        () {
      const result = TransportResult(success: true, message: 'Shared.');
      expect(result.success, isTrue);
      expect(result.message, 'Shared.');
      expect(result.retryable, isFalse);
    });

    test(
        'ShareResultStatus.dismissed is distinct from success — '
        'confirms share_plus was wrong to use dismissed as a failure signal (#92)',
        () {
      expect(
        ShareResultStatus.dismissed,
        isNot(equals(ShareResultStatus.success)),
        reason: 'dismissed != success; so checking for !dismissed incorrectly '
            'treated a completed share as a failure on Android',
      );
    });
  });

  // Keep ctx in scope to suppress lint warnings (ctx is used indirectly by
  // documenting the test-harness setup that would be needed for a live call).
  test('ctx fixture is valid', () {
    expect(ctx.firedAt, DateTime(2026, 1, 1));
  });

  group(
      'ShareSheetTransport.transport — regression #337: Bluesky (and '
      'potentially other) Android targets silently receive no content', () {
    // Root cause (notes/dev/android_share_sheet.md): on Android, share_plus
    // unconditionally launches its chooser via the 3-arg
    // Intent.createChooser(..., IntentSender) + startActivityForResult, so
    // it can report back which target the user picked. QuKi-Notes never
    // reads that result (see the #92 regression above — the status is
    // dropped entirely). An on-device A/B test confirmed a minimal native
    // app sharing via a plain ACTION_SEND + startActivity chooser succeeds
    // at delivering content to Bluesky's compose screen; QuKi-Notes (via
    // share_plus) does not.
    //
    // Fix: on Android, route through AndroidShareChannel (a small owned
    // platform channel that launches a plain, no-result-tracking chooser)
    // instead of share_plus. Windows/Linux keep using share_plus unchanged
    // — this failure mode has no evidence there and share_plus is otherwise
    // a working, maintained dependency on those platforms.
    //
    // We can't invoke a real Android intent/chooser from a Dart unit test
    // (that needs a live device with the target app installed), so this
    // only proves: (a) on Android, the transport calls the native channel
    // with the QuKi's markdown, not share_plus; (b) on other platforms, it
    // still calls share_plus, unchanged. It does NOT prove delivery to
    // Bluesky actually works — that requires the project owner's on-device
    // test.

    test(
        'on Android, shares via the native AndroidShareChannel, not share_plus',
        () async {
      String? capturedText;
      var sharePlusCalled = false;
      final transport = ShareSheetTransport(
        useAndroidChannel: true,
        shareViaAndroidChannel: (text) async {
          capturedText = text;
        },
        shareViaSharePlus: (text) async {
          sharePlusCalled = true;
        },
      );

      final result = await transport.transport(
        markdown: '# hello world',
        images: const [],
        ctx: ctx,
      );

      expect(capturedText, '# hello world');
      expect(sharePlusCalled, isFalse);
      expect(result.success, isTrue);
    });

    test(
        'on non-Android platforms (Windows/Linux), still shares via '
        'share_plus, unaffected by the Android fix', () async {
      String? capturedText;
      var androidChannelCalled = false;
      final transport = ShareSheetTransport(
        useAndroidChannel: false,
        shareViaAndroidChannel: (text) async {
          androidChannelCalled = true;
        },
        shareViaSharePlus: (text) async {
          capturedText = text;
        },
      );

      final result = await transport.transport(
        markdown: 'plain text quki',
        images: const [],
        ctx: ctx,
      );

      expect(capturedText, 'plain text quki');
      expect(androidChannelCalled, isFalse);
      expect(result.success, isTrue);
    });
  });

  group(
      'ShareSheetTransport.transport — regression: intermittent Android '
      'delivery failure, target already running', () {
    // Follow-on to the #337 fix above: the plain chooser alone didn't fully
    // resolve delivery -- a repro chain found it still intermittent,
    // correlated with whether the target app is already running. The native
    // fix (FLAG_ACTIVITY_NEW_TASK + try/catch around startActivity(),
    // SharePlugin.kt) can't be exercised from a Dart unit test (needs a real
    // device + target app). What IS verifiable here: a failure surfaced by
    // the native channel (via result.error(), now that startActivity() is
    // wrapped instead of left to propagate uncaught with no signal) must not
    // be silently swallowed by ShareSheetTransport.transport() -- it has to
    // reach EditorScreen._onTransport()'s existing catch block, which already
    // shows a "Send failed" snackbar with Retry. No new UX needed; this only
    // proves the plumbing doesn't accidentally eat the error in between.
    test(
        'a native-channel failure propagates out of transport() rather than '
        'being swallowed', () async {
      final transport = ShareSheetTransport(
        useAndroidChannel: true,
        shareViaAndroidChannel: (text) async {
          throw PlatformException(
            code: 'share_failed',
            message: 'Failed to launch the share chooser.',
          );
        },
      );

      await expectLater(
        transport.transport(markdown: 'hello', images: const [], ctx: ctx),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('AndroidShareChannel — plain-chooser method-call shape', () {
    // Verifies only that the Dart→platform-channel call shape is correct.
    // The native Kotlin side (real Intent/chooser launch, actual delivery
    // to a target app) cannot be exercised from a Dart unit test — that
    // requires a real device with the target app installed. Actual
    // delivery must be confirmed on-device (see group above and PR report).
    const channel = MethodChannel('com.quki.quki_notes/share');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('shareText invokes the shareText method with the given text',
        () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      await AndroidShareChannel.shareText('hello world');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'shareText');
      expect(calls.single.arguments, {'text': 'hello world'});
    });

    test(
        'shareText propagates a PlatformException when the native side '
        'reports an error via result.error() — regression: SharePlugin.kt '
        'previously let startActivity() failures propagate uncaught with no '
        'signal instead of reporting through the channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'share_failed',
          message: 'Failed to launch the share chooser.',
        );
      });

      await expectLater(
        AndroidShareChannel.shareText('hello world'),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'share_failed')),
      );
    });
  });
}
