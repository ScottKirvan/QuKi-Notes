import 'package:share_plus/share_plus.dart';

import '../transport_plugin.dart';

class ShareSheetToss extends TransportPlugin {
  const ShareSheetToss();

  @override
  String get id => 'share_sheet';

  @override
  String get displayName => 'Share Sheet';

  @override
  String get description => 'Send the QuKi via the system share sheet.';

  @override
  Future<TossResult> toss({
    required String markdown,
    required List<TossImage> images,
    required TossContext ctx,
  }) async {
    final result = await Share.share(markdown);
    final success = result.status != ShareResultStatus.dismissed;
    return TossResult(
      success: success,
      message: success ? 'Shared.' : 'Share cancelled.',
    );
  }
}
