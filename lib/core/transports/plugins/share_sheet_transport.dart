import 'dart:io' show Platform;

import 'package:share_plus/share_plus.dart';

import '../android_share_channel.dart';
import '../transport_plugin.dart';

class ShareSheetTransport extends TransportPlugin {
  const ShareSheetTransport({
    bool? useAndroidChannel,
    Future<void> Function(String text)? shareViaAndroidChannel,
    Future<void> Function(String text)? shareViaSharePlus,
  })  : _useAndroidChannel = useAndroidChannel,
        _shareViaAndroidChannel = shareViaAndroidChannel,
        _shareViaSharePlus = shareViaSharePlus;

  /// Override for [Platform.isAndroid]. When null (default) the real
  /// Platform.isAndroid is used. Set in tests to exercise either branch
  /// without depending on the host OS running the test.
  final bool? _useAndroidChannel;

  /// Injectable override for the native Android share call. Production code
  /// uses the default, which delegates to [AndroidShareChannel.shareText].
  /// Tests supply a fake here to avoid invoking a real platform channel.
  final Future<void> Function(String text)? _shareViaAndroidChannel;

  /// Injectable override for the share_plus call (used on non-Android
  /// platforms). Production code uses the default, which delegates to
  /// [Share.share]. Tests supply a fake here for the same reason as above.
  final Future<void> Function(String text)? _shareViaSharePlus;

  bool get _isAndroid => _useAndroidChannel ?? Platform.isAndroid;

  @override
  String get id => 'share_sheet';

  @override
  String get displayName => 'Share Sheet';

  @override
  String get description => 'Send the QuKi via the system share sheet.';

  @override
  Future<TransportResult> transport({
    required String markdown,
    required List<TransportImage> images,
    required TransportContext ctx,
  }) async {
    // On Android, route through a plain ACTION_SEND chooser with no
    // result-tracking (AndroidShareChannel) rather than share_plus's
    // startActivityForResult-based chooser, which is implicated in some
    // targets (Bluesky, confirmed) silently failing to receive the shared
    // content — see notes/dev/android_share_sheet.md. share_plus remains
    // the implementation on Windows/Linux, which show no evidence of the
    // same failure mode.
    if (_isAndroid) {
      final share = _shareViaAndroidChannel ?? AndroidShareChannel.shareText;
      await share(markdown);
    } else {
      final share = _shareViaSharePlus ?? (text) => Share.share(text);
      await share(markdown);
    }
    // share_plus fires ShareResultStatus.dismissed on Android even when the
    // user completes a share successfully (#92). Drop the status check and
    // always return success so users don't see a false "Share cancelled."
    // snackbar. The native Android channel above reports no result at all
    // for the same reason — nothing here ever read it anyway.
    return const TransportResult(success: true, message: 'Shared.');
  }
}
