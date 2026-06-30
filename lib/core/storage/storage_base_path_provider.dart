import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage_location_service.dart';

/// Holds the current storage base path as reactive Riverpod state.
///
/// Initialised from [storageLocationServiceProvider] in [build()].
/// Call [setPath] after any [StorageLocationService.setPath] or
/// [StorageLocationService.useAppStorage] call to push the change to all
/// downstream providers ([quKiStorageProvider], [quKiIndexProvider], etc.).
class StorageBasePathNotifier extends Notifier<String> {
  @override
  String build() => ref.read(storageLocationServiceProvider).basePath;

  void setPath(String path) => state = path;
}

final storageBasePathProvider =
    NotifierProvider<StorageBasePathNotifier, String>(
  StorageBasePathNotifier.new,
);
