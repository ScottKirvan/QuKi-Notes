import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/storage/storage_location_service.dart';
import 'features/window/window_state_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    await WindowStateService.restore();
  }

  final prefs = await SharedPreferences.getInstance();
  final appDir = await getApplicationDocumentsDirectory();
  final appStoragePath = p.join(appDir.path, 'qukis');

  final locationService = StorageLocationService(prefs, appStoragePath);
  await locationService.adoptAppStorageIfUpgrading();

  runApp(ProviderScope(
    overrides: [
      storageLocationServiceProvider.overrideWithValue(locationService),
    ],
    child: const QuKiNotesApp(),
  ));
}
