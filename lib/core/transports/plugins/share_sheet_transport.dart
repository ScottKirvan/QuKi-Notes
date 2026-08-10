import 'package:share_plus/share_plus.dart';

import '../transport_plugin.dart';

class ShareSheetTransport extends TransportPlugin {
  const ShareSheetTransport();

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
    await Share.share(markdown);
    // share_plus fires ShareResultStatus.dismissed on Android even when the
    // user completes a share successfully (#92). Drop the status check and
    // always return success so users don't see a false "Share cancelled."
    // snackbar.
    return const TransportResult(success: true, message: 'Shared.');
  }
}
