import 'package:flutter/services.dart';

import '../transport_plugin.dart';

class ClipboardTransport extends TransportPlugin {
  const ClipboardTransport();

  @override
  String get id => 'clipboard';

  @override
  String get displayName => 'Clipboard';

  @override
  String get description =>
      'Copy the QuKi as markdown to the system clipboard.';

  @override
  Future<TransportResult> transport({
    required String markdown,
    required List<TransportImage> images,
    required TransportContext ctx,
  }) async {
    await Clipboard.setData(ClipboardData(text: markdown));
    return const TransportResult(
        success: true, message: 'Copied to clipboard.');
  }
}
