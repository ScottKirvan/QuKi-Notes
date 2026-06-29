import 'package:shared_preferences/shared_preferences.dart';

/// Owns reading/writing the user-chosen storage location to [SharedPreferences].
///
/// Pure Dart — no Flutter imports.
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
}
