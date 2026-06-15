import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/storage/quki_index.dart';
import 'core/storage/quki_storage.dart';
import 'features/window/window_state_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    await WindowStateService.restore();
  }
  final storage = await QuKiStorage.fromAppDir();
  runApp(ProviderScope(
    overrides: [quKiStorageProvider.overrideWithValue(storage)],
    child: const QuKiNotesApp(),
  ));
}
