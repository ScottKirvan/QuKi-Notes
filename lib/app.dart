import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'core/storage/quki_index.dart';
import 'core/storage/storage_location_service.dart';
import 'features/editor/editor_screen.dart';
import 'features/setup/storage_setup_screen.dart';
import 'features/share_in/share_handler.dart';
import 'features/window/window_state_scope.dart';

final _log = Logger('ShareAwareHome');

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
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          // Primer Light High Contrast
          surface: Color(0xffffffff), // canvas.default → surface
          onSurface: Color(0xff0d1117), // fg.default
          onSurfaceVariant: Color(0xff59636e), // fg.muted
          primary: Color(0xff0550ae), // accent.fg
          onPrimary: Color(0xffffffff),
          primaryContainer: Color(0xff0969da), // accent.emphasis
          onPrimaryContainer: Color(0xffffffff),
          secondary: Color(0xff0550ae),
          onSecondary: Color(0xffffffff),
          secondaryContainer: Color(0xffdff7ff),
          onSecondaryContainer: Color(0xff0d1117),
          tertiary: Color(0xff0550ae),
          onTertiary: Color(0xffffffff),
          tertiaryContainer: Color(0xffdff7ff),
          onTertiaryContainer: Color(0xff0d1117),
          error: Color(0xffd1242f), // danger.fg
          onError: Color(0xffffffff),
          errorContainer: Color(0xffFFebe9),
          onErrorContainer: Color(0xff0d1117),
          outline: Color(0xff3d444d), // border.default
          shadow: Color(0xff0d1117),
          inverseSurface: Color(0xff0d1117),
          onInverseSurface: Color(0xffffffff),
          inversePrimary: Color(0xff71b7ff),
          surfaceTint: Color(0xff0550ae),
          surfaceContainerHighest: Color(0xfff6f8fa), // canvas.subtle
        ),
        checkboxTheme: const CheckboxThemeData(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          // Primer Dark High Contrast
          surface: Color(0xff0a0c10), // canvas.default → surface
          surfaceContainerHighest: Color(0xff272b33), // canvas.subtle
          onSurface: Color(0xfff0f3f9), // fg.default
          onSurfaceVariant: Color(0xff9ea7b4), // fg.muted
          primary: Color(0xff71b7ff), // accent.fg
          onPrimary: Color(0xff0a0c10),
          primaryContainer: Color(0xff1f6feb), // accent.emphasis
          onPrimaryContainer: Color(0xfff0f3f9),
          secondary: Color(0xff71b7ff),
          onSecondary: Color(0xff0a0c10),
          secondaryContainer: Color(0xff1f2937),
          onSecondaryContainer: Color(0xfff0f3f9),
          tertiary: Color(0xff71b7ff),
          onTertiary: Color(0xff0a0c10),
          tertiaryContainer: Color(0xff1f2937),
          onTertiaryContainer: Color(0xfff0f3f9),
          error: Color(0xffff9492), // danger.fg dark
          onError: Color(0xff0a0c10),
          errorContainer: Color(0xff300d0d),
          onErrorContainer: Color(0xfff0f3f9),
          outline: Color(0xff7a828e), // border.default
          shadow: Color(0xff0a0c10),
          inverseSurface: Color(0xfff0f3f9),
          onInverseSurface: Color(0xff0a0c10),
          inversePrimary: Color(0xff0550ae),
          surfaceTint: Color(0xff71b7ff),
        ),
        checkboxTheme: const CheckboxThemeData(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        useMaterial3: true,
      ),
      home: const _AppHome(),
    );
    if (Platform.isWindows || Platform.isLinux) {
      return WindowStateScope(child: app);
    }
    return app;
  }
}

/// Root home widget.
///
/// On first launch shows [StorageSetupScreen]; on subsequent launches shows
/// [_ShareAwareHome] directly.
class _AppHome extends ConsumerWidget {
  const _AppHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationSvc = ref.read(storageLocationServiceProvider);
    if (locationSvc.isFirstLaunch) {
      return const StorageSetupScreen();
    }
    return const _ShareAwareHome();
  }
}

/// Inner home that listens for incoming share intents and loads the shared text
/// as a new QuKi in the root editor — never pushes a second screen.
class _ShareAwareHome extends ConsumerWidget {
  const _ShareAwareHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<String?>>(shareStreamProvider, (_, next) {
      next.whenData((text) {
        if (text == null) return;
        () async {
          try {
            final storage = ref.read(quKiStorageProvider);
            final meta = await storage.create(text);
            ref.read(quKiIndexProvider.notifier).addMeta(meta);
            ref.read(activeQukiIdProvider.notifier).setId(meta.id);
          } catch (e, st) {
            _log.severe('Failed to save shared content', e, st);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to save shared content.'),
                  duration: Duration(seconds: 4),
                ),
              );
            }
          }
        }();
      });
    });

    return const EditorScreen();
  }
}
