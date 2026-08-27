import 'dart:io' show Platform;

// MethodChannel is a Flutter import. This file is an acceptable exception to
// the Flutter-free lib/core/ rule, analogous to lib/core/storage/
// android_storage_channel.dart (ADR-21).
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
  static Future<void> shareText(String text) =>
      _channel.invokeMethod('shareText', {'text': text});
}
