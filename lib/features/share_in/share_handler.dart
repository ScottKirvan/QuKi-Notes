import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareHandler {
  const ShareHandler._();

  /// Extracts text from a share intent, joining multiple items with '\n\n'.
  /// Returns null if the list is empty or contains only non-text items.
  static String? extractText(List<SharedMediaFile> items) {
    final texts = items
        .where((f) => f.type == SharedMediaType.text)
        .map((f) => f.path)
        .where((s) => s.isNotEmpty)
        .toList();
    return texts.isEmpty ? null : texts.join('\n\n');
  }
}

/// Overridable platform check. Override with false in tests to simulate non-mobile.
final isMobileProvider =
    Provider<bool>((ref) => Platform.isAndroid || Platform.isIOS);

/// Emits shared text when another app shares into QuKi-Notes, then null after
/// the intent is consumed. Null emissions are a reset signal — listeners should
/// only act on non-null values.
final shareStreamProvider = StreamProvider<String?>((ref) async* {
  if (!ref.read(isMobileProvider)) return;

  // Cold start: text shared while the app was not running.
  final initial = await ReceiveSharingIntent.instance.getInitialMedia();
  final initialText = ShareHandler.extractText(initial);
  yield initialText;
  if (initialText != null) {
    await ReceiveSharingIntent.instance.reset();
  }

  // Warm start: text shared while the app is already in the foreground.
  await for (final media in ReceiveSharingIntent.instance.getMediaStream()) {
    yield ShareHandler.extractText(media);
  }
});
