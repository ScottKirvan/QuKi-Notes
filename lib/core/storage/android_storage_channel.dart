import 'dart:io' show Platform;

// MethodChannel is a Flutter import. This file is an acceptable exception to
// the Flutter-free lib/core/ rule, analogous to lib/core/transports/ (ADR-21).
// It must not be imported by storage_location_service.dart.
import 'package:flutter/services.dart';

/// Dart wrapper for the native Kotlin StoragePlugin method channel.
///
/// Only relevant on Android. All methods will throw [MissingPluginException]
/// if called on other platforms — guard with [isSupported] first.
class AndroidStorageChannel {
  static const _channel = MethodChannel('com.quki.quki_notes/storage');

  static bool get isSupported => Platform.isAndroid;

  /// Returns true when the app holds the MANAGE_EXTERNAL_STORAGE permission.
  ///
  /// Always returns true on Android < 11 where the permission does not exist.
  static Future<bool> isExternalStorageManager() => _channel
      .invokeMethod<bool>('isExternalStorageManager')
      .then((v) => v ?? false);

  /// Returns the fixed well-known path for QuKi notes on external storage:
  /// `<external documents dir>/QuKi_Notes`.
  static Future<String> getExternalDocumentsPath() =>
      _channel.invokeMethod<String>('getExternalDocumentsPath').then((v) => v!);

  /// Launches the system settings screen for granting all-files access.
  ///
  /// Returns immediately — the caller must detect permission grant via
  /// [AppLifecycleState.resumed].
  static Future<void> requestAllFilesAccess() =>
      _channel.invokeMethod('requestAllFilesAccess');
}
