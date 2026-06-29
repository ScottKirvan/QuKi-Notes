import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_location_service.dart';
import '../editor/editor_screen.dart';

/// Provider for [StorageLocationService].
///
/// Must be overridden in [main()] after [SharedPreferences] and
/// [getApplicationDocumentsDirectory()] are resolved.
final storageLocationServiceProvider = Provider<StorageLocationService>(
  (ref) => throw UnimplementedError(
      'storageLocationServiceProvider must be overridden'),
);

/// One-time setup screen shown on first launch.
///
/// The user chooses between filesystem storage (accessible via file manager,
/// survives uninstall) and app storage (private, removed on uninstall).
/// After a choice is saved the screen navigates to [EditorScreen] and never
/// appears again.
class StorageSetupScreen extends ConsumerStatefulWidget {
  const StorageSetupScreen({super.key});

  @override
  ConsumerState<StorageSetupScreen> createState() => _StorageSetupScreenState();
}

class _StorageSetupScreenState extends ConsumerState<StorageSetupScreen> {
  bool _picking = false;

  Future<void> _pickFolder() async {
    setState(() => _picking = true);
    try {
      final path = await FilePicker.getDirectoryPath();
      if (!mounted) return;
      if (path == null) {
        // User cancelled — stay on this screen.
        return;
      }
      final svc = ref.read(storageLocationServiceProvider);
      await svc.setPath(path);
      if (!mounted) return;
      _openEditor();
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _useAppStorage() async {
    final svc = ref.read(storageLocationServiceProvider);
    await svc.useAppStorage();
    if (!mounted) return;
    _openEditor();
  }

  void _openEditor() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const EditorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return PopScope(
      // Back gesture / system back while no choice has been saved → use app
      // storage so the user is never stuck without an app to open.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final svc = ref.read(storageLocationServiceProvider);
        if (svc.isFirstLaunch) {
          await svc.useAppStorage();
          if (!mounted) return;
          _openEditor();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Where should QuKis be saved?',
                  style: tt.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose once. You can change this later in Settings.',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                _OptionCard(
                  title: 'Choose a folder',
                  subtitle:
                      'Your QuKis are saved as plain files you can access anytime. '
                      'They survive uninstall.',
                  icon: Icons.folder_open_outlined,
                  loading: _picking,
                  onTap: _picking ? null : _pickFolder,
                ),
                const SizedBox(height: 16),
                _OptionCard(
                  title: 'Use app storage',
                  subtitle: 'QuKis are kept private to this app. '
                      'They will be removed if you uninstall.',
                  icon: Icons.lock_outline,
                  onTap: _picking ? null : _useAppStorage,
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    loading
                        ? Row(
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(width: 12),
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ],
                          )
                        : Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
