import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for [StorageLocationService].
///
/// Must be overridden in [main()] after [SharedPreferences] and
/// [getApplicationDocumentsDirectory()] are resolved.
final storageLocationServiceProvider = Provider<StorageLocationService>(
  (ref) => throw UnimplementedError(
      'storageLocationServiceProvider must be overridden'),
);

/// Owns reading/writing the user-chosen storage location to [SharedPreferences].
class StorageLocationService {
  static const _keyBasePath = 'storage.base_path';
  static const _keyChosen = 'storage.location_chosen';

  final SharedPreferences _prefs;

  /// The absolute path of the app's sandboxed documents directory.
  /// Used as the fallback when no choice has been made, and as the reference
  /// for [isAppStorage].
  final String _appStoragePath;

  StorageLocationService(this._prefs, this._appStoragePath);

  /// True on first launch — neither key has been written yet.
  bool get isFirstLaunch => !_prefs.containsKey(_keyChosen);

  /// The resolved absolute path for the QuKis root directory.
  ///
  /// Falls back to [_appStoragePath] until the user makes a choice.
  String get basePath => _prefs.getString(_keyBasePath) ?? _appStoragePath;

  /// True when the current [basePath] equals the sandboxed app-documents path.
  bool get isAppStorage => basePath == _appStoragePath;

  /// Save [path] as the chosen storage location and mark setup complete.
  Future<void> setPath(String path) async {
    await _prefs.setString(_keyBasePath, path);
    await _prefs.setBool(_keyChosen, true);
  }

  /// Save the app's sandboxed directory as the chosen location and mark setup
  /// complete.
  Future<void> useAppStorage() async {
    await _prefs.setString(_keyBasePath, _appStoragePath);
    await _prefs.setBool(_keyChosen, true);
  }

  /// Silently adopts app storage when upgrading from a pre-ADR-27 build.
  ///
  /// On a fresh install [isFirstLaunch] is true and the storage directory is
  /// empty — the setup dialog should appear. On an upgrade the directory
  /// already contains QuKi files even though no choice was ever recorded.
  /// Calling this before the first frame prevents the dialog from appearing
  /// for existing users.
  Future<void> adoptAppStorageIfUpgrading() async {
    if (!isFirstLaunch) return;
    final dir = Directory(_appStoragePath);
    if (!await dir.exists()) return;
    final hasData =
        await dir.list().any((e) => e is File && e.path.endsWith('.md'));
    if (hasData) await useAppStorage();
  }
}
