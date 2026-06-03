import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/editor/editor_screen.dart';
import 'features/share_in/share_handler.dart';
import 'features/stream/stream_screen.dart';
import 'features/window/window_state_scope.dart';

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

/// Root home widget that listens for incoming share intents and pushes a new
/// EditorScreen pre-populated with the shared text.
class _ShareAwareHome extends ConsumerWidget {
  const _ShareAwareHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<String?>>(shareStreamProvider, (_, next) {
      next.whenData((text) {
        if (text != null && context.mounted) {
          Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => EditorScreen(initialBody: text),
            ),
          );
        }
      });
    });

    return EditorScreen(
      onLeave: (ctx) => Navigator.push<void>(
        ctx,
        MaterialPageRoute(builder: (_) => const StreamScreen()),
      ),
    );
  }
}
