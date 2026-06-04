import 'dart:io' show Platform;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'core/database/app_database.dart';
import 'core/database/database_provider.dart';
import 'features/editor/editor_screen.dart';
import 'features/share_in/share_handler.dart';
import 'features/window/window_state_scope.dart';

// ID of the QuKi currently loaded in the root editor.
// null = blank new QuKi. Set by StreamScreen on row-tap or + New.
class ActiveQukiIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setId(String? id) => state = id;
}

final activeQukiIdProvider =
    NotifierProvider<ActiveQukiIdNotifier, String?>(ActiveQukiIdNotifier.new);

class QuKiNotesApp extends ConsumerWidget {
  const QuKiNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = MaterialApp(
      title: 'QuKi-Notes',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _ShareAwareHome(),
    );
    if (Platform.isWindows || Platform.isLinux) {
      return WindowStateScope(child: app);
    }
    return app;
  }
}

/// Root home widget that listens for incoming share intents and loads the
/// shared text as a new QuKi in the root editor — never pushes a second screen.
class _ShareAwareHome extends ConsumerWidget {
  const _ShareAwareHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<String?>>(shareStreamProvider, (_, next) {
      next.whenData((text) {
        if (text == null) return;
        // Save as a new QuKi and open it in the root editor.
        () async {
          final db = ref.read(appDatabaseProvider);
          final id = const Uuid().v4();
          final now = DateTime.now();
          await db.qukisDao.insertQuki(QukisCompanion.insert(
            id: id,
            body: Value(text),
            createdAt: now,
            modifiedAt: now,
          ));
          ref.read(activeQukiIdProvider.notifier).setId(id);
        }();
      });
    });

    return const EditorScreen();
  }
}
