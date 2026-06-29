import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/android_storage_channel.dart';
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

/// Callbacks that wrap [AndroidStorageChannel] calls and other side effects
/// so they can be replaced in tests without needing real I/O or a MethodChannel.
class AndroidStorageCallbacks {
  const AndroidStorageCallbacks({
    Future<bool> Function()? isExternalStorageManager,
    Future<String> Function()? getExternalDocumentsPath,
    Future<void> Function()? requestAllFilesAccess,
    Future<void> Function(String path)? createDirectory,
  })  : _isExternalStorageManager = isExternalStorageManager,
        _getExternalDocumentsPath = getExternalDocumentsPath,
        _requestAllFilesAccess = requestAllFilesAccess,
        _createDirectory = createDirectory;

  final Future<bool> Function()? _isExternalStorageManager;
  final Future<String> Function()? _getExternalDocumentsPath;
  final Future<void> Function()? _requestAllFilesAccess;
  final Future<void> Function(String path)? _createDirectory;

  Future<bool> isExternalStorageManager() => _isExternalStorageManager != null
      ? _isExternalStorageManager()
      : AndroidStorageChannel.isExternalStorageManager();

  Future<String> getExternalDocumentsPath() => _getExternalDocumentsPath != null
      ? _getExternalDocumentsPath()
      : AndroidStorageChannel.getExternalDocumentsPath();

  Future<void> requestAllFilesAccess() => _requestAllFilesAccess != null
      ? _requestAllFilesAccess()
      : AndroidStorageChannel.requestAllFilesAccess();

  Future<void> createDirectory(String path) => _createDirectory != null
      ? _createDirectory(path)
      : Directory(path).create(recursive: true);
}

/// One-time setup screen shown on first launch.
///
/// The user chooses between filesystem storage (accessible via file manager,
/// survives uninstall) and app storage (private, removed on uninstall).
/// After a choice is saved the screen navigates to [EditorScreen] and never
/// appears again.
///
/// When [isChangingLocation] is true (navigated to from Settings), the back
/// button pops without calling [StorageLocationService.useAppStorage].
class StorageSetupScreen extends ConsumerStatefulWidget {
  const StorageSetupScreen({
    super.key,
    this.isChangingLocation = false,
    this.androidCallbacks = const AndroidStorageCallbacks(),
    bool? useAndroidFlow,
  }) : _useAndroidFlow = useAndroidFlow;

  /// When true, the user arrived here from Settings to change their choice.
  /// Back / cancel returns to Settings without altering the saved choice.
  final bool isChangingLocation;

  /// Injectable callbacks for Android storage channel calls. Production code
  /// uses the default [AndroidStorageCallbacks] which delegates to
  /// [AndroidStorageChannel]. Tests supply fakes here.
  final AndroidStorageCallbacks androidCallbacks;

  /// Override for [Platform.isAndroid]. When null (default) the real
  /// Platform.isAndroid is used. Set to true in tests to exercise the Android
  /// permission flow without needing to run on a device.
  // ignore: unused_field
  final bool? _useAndroidFlow;

  @override
  ConsumerState<StorageSetupScreen> createState() => _StorageSetupScreenState();
}

class _StorageSetupScreenState extends ConsumerState<StorageSetupScreen>
    with WidgetsBindingObserver {
  bool _busy = false;

  /// True while waiting for the user to return from the system permission
  /// settings screen after tapping "Filesystem storage" on Android.
  bool _waitingForPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Called when the app lifecycle state changes. Used to detect when the user
  /// returns from the Android system permission settings screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForPermission) {
      _onReturnFromPermissionSettings();
    }
  }

  /// Re-checks the permission after returning from Android system settings.
  Future<void> _onReturnFromPermissionSettings() async {
    final granted = await widget.androidCallbacks.isExternalStorageManager();
    if (!mounted) return;
    if (granted) {
      await _completeFilesystemStorage();
    } else {
      // Permission still denied — return to the setup screen.
      setState(() {
        _waitingForPermission = false;
        _busy = false;
      });
    }
  }

  /// Resolves the external documents path, saves it, and navigates to editor.
  Future<void> _completeFilesystemStorage() async {
    final path = await widget.androidCallbacks.getExternalDocumentsPath();
    if (!mounted) return;
    await widget.androidCallbacks.createDirectory(path);
    if (!mounted) return;
    final svc = ref.read(storageLocationServiceProvider);
    await svc.setPath(path);
    if (!mounted) return;
    _openEditor();
  }

  bool get _isAndroid => widget._useAndroidFlow ?? Platform.isAndroid;

  /// Android: request MANAGE_EXTERNAL_STORAGE, or proceed if already granted.
  /// Desktop: use file_picker to let the user choose a directory.
  Future<void> _requestFilesystemStorage() async {
    setState(() => _busy = true);
    try {
      if (_isAndroid) {
        final granted =
            await widget.androidCallbacks.isExternalStorageManager();
        if (!mounted) return;
        if (granted) {
          await _completeFilesystemStorage();
        } else {
          setState(() => _waitingForPermission = true);
          await widget.androidCallbacks.requestAllFilesAccess();
          // Remainder handled in didChangeAppLifecycleState on resume.
        }
      } else {
        // Desktop: native directory picker.
        final path = await FilePicker.platform.getDirectoryPath();
        if (!mounted) return;
        if (path == null) {
          // User cancelled — stay on this screen.
          setState(() => _busy = false);
          return;
        }
        final svc = ref.read(storageLocationServiceProvider);
        await svc.setPath(path);
        if (!mounted) return;
        _openEditor();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _waitingForPermission = false;
        });
      }
      rethrow;
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

    final filesystemTitle = _isAndroid
        ? 'Filesystem storage — Documents/QuKi_Notes'
        : 'Choose a folder';
    final filesystemSubtitle = _isAndroid
        ? 'Your QuKis are saved as plain files in your Documents folder. '
            'They survive uninstall and are accessible with any file manager.'
        : 'Your QuKis are saved as plain files you can access anytime. '
            'They survive uninstall.';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (widget.isChangingLocation) {
          // Back from Settings — cancel with no change.
          Navigator.of(context).pop();
          return;
        }
        // First-launch back: fall back to app storage so the user is never
        // stuck without an app to open.
        final svc = ref.read(storageLocationServiceProvider);
        if (svc.isFirstLaunch) {
          await svc.useAppStorage();
          if (!mounted) return;
          _openEditor();
        }
      },
      child: Scaffold(
        appBar: widget.isChangingLocation
            ? AppBar(title: const Text('Storage location'))
            : null,
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
                  title: filesystemTitle,
                  subtitle: filesystemSubtitle,
                  icon: Icons.folder_open_outlined,
                  loading: _busy,
                  onTap: _busy ? null : _requestFilesystemStorage,
                ),
                const SizedBox(height: 16),
                _OptionCard(
                  title: 'Use app storage',
                  subtitle: 'QuKis are kept private to this app. '
                      'They will be removed if you uninstall.',
                  icon: Icons.lock_outline,
                  onTap: _busy ? null : _useAppStorage,
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
                              Flexible(
                                child: Text(
                                  title,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
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
