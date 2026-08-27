import 'dart:io' show Platform;

// MethodChannel is a Flutter import. This file is an acceptable exception to
// the Flutter-free lib/core/ rule, analogous to lib/core/storage/
// android_storage_channel.dart (ADR-21).
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Dart wrapper for the native Kotlin SharePlugin method channel.
///
/// Launches the system share chooser via a plain ACTION_SEND intent with no
/// result-tracking, bypassing share_plus's startActivityForResult-based
/// chooser on Android, which is implicated in some targets (Bluesky,
/// confirmed) silently failing to receive the shared content — see
/// notes/dev/android_share_sheet.md.
///
/// Only relevant on Android. All methods will throw [MissingPluginException]
/// if called on other platforms — guard with [isSupported] first.
class AndroidShareChannel {
  static const _channel = MethodChannel('com.quki.quki_notes/share');

  static bool get isSupported => Platform.isAndroid;

  /// Opens the system share chooser with [text] as plain-text content.
  static Future<void> shareText(String text) async {
    // TEMPORARY DIAGNOSTIC (see Agents/quiki-dev/CLAUDE.md "Android Share
    // Sheet delivery is intermittent"). Brackets the Dart<->Kotlin
    // MethodChannel round trip with timestamps so it can be compared against
    // the native-side timestamps logged in SharePlugin.kt, to see how much
    // of the gap between "Send tapped" and "startActivity() fires" this hop
    // actually accounts for. Uses debugPrint rather than this app's
    // package:logging Logger because Logger.root has no listener registered
    // anywhere in the app (a separate, pre-existing gap — see PR report) so
    // Logger calls currently produce no visible output at all; debugPrint is
    // guaranteed visible via `flutter logs` / `adb logcat` (tag "flutter").
    // Grep "TEMPORARY DIAGNOSTIC" to find and remove every part of this.
    final before = DateTime.now();
    debugPrint('[ShareDiag] invokeMethod(shareText) start at $before');
    await _channel.invokeMethod('shareText', {'text': text});
    final after = DateTime.now();
    debugPrint('[ShareDiag] invokeMethod(shareText) returned at $after '
        '(${after.difference(before).inMilliseconds}ms)');
  }
}
