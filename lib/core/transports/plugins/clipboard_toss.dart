import 'package:flutter/services.dart';

import '../transport_plugin.dart';

class ClipboardToss extends TransportPlugin {
  const ClipboardToss();

  @override
  String get id => 'clipboard';

  @override
  String get displayName => 'Clipboard';

  @override
  String get description =>
      'Copy the QuKi as markdown to the system clipboard.';

  @override
  Future<TossResult> toss({
    required String markdown,
    required List<TossImage> images,
    required TossContext ctx,
  }) async {
    await Clipboard.setData(ClipboardData(text: markdown));
    return const TossResult(success: true, message: 'Copied to clipboard.');
  }
}
