import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

import '../../app.dart';
import '../../core/storage/quki_index.dart';
import '../../core/transports/registry_provider.dart';
import '../../core/transports/transport_plugin.dart';

import 'auto_save_controller.dart';
import 'toss_picker_sheet.dart';
import '../settings/settings_screen.dart';
import '../stream/stream_screen.dart';

final _log = Logger('EditorScreen');

PageRouteBuilder<void> _slideFromLeft(Widget screen) {
  return PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => screen,
    transitionsBuilder: (_, animation, __, child) {
      final tween = Tween(
        begin: const Offset(-1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeInOut));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

PageRouteBuilder<void> _slideFromRight(Widget screen) {
  return PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => screen,
    transitionsBuilder: (_, animation, __, child) {
      final tween = Tween(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeInOut));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  late final MarkdownEditorController _editorController;
  late final AutoSaveController _autoSave;

  @override
  void initState() {
    super.initState();
    _editorController = MarkdownEditorController();

    _autoSave = AutoSaveController(
      onSave: _writeQuKi,
      getBody: () => _editorController.currentValue,
    );
    _autoSave.start();

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSave.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autoSave.save();
    }
    if (state == AppLifecycleState.resumed) {
      ref.read(quKiIndexProvider.notifier).refresh();
    }
  }

  /// Write callback for [AutoSaveController]. Creates or updates the file and
  /// keeps [quKiIndexProvider] in sync. Returns the QuKi ID (new or existing).
  Future<String> _writeQuKi(String? currentId, String body) async {
    final storage = ref.read(quKiStorageProvider);
    if (currentId != null) {
      await storage.update(currentId, body);
      ref
          .read(quKiIndexProvider.notifier)
          .updateMeta(currentId, DateTime.now());
      return currentId;
    } else {
      final meta = await storage.create(body);
      ref.read(quKiIndexProvider.notifier).addMeta(meta);
      return meta.id;
    }
  }

  Future<void> _onActiveQukiChanged(String? qukiId) async {
    await _autoSave.flush();
    if (!mounted) return;

    String body = '';
    if (qukiId != null) {
      body = await ref.read(quKiStorageProvider).read(qukiId);
      if (!mounted) return;
    }

    _editorController.setValue(body);
    if (qukiId == null) _editorController.requestFocus();
    _autoSave.resetForQuki(id: qukiId, initialBody: body);
  }

  Future<void> _newQuKi() async {
    if (ref.read(activeQukiIdProvider) == null) {
      await _autoSave.flush();
      if (!mounted) return;
      _editorController.setValue('');
      _editorController.requestFocus();
      _autoSave.resetForQuki(id: null);
    } else {
      ref.read(activeQukiIdProvider.notifier).setId(null);
    }
  }

  Future<void> _openQuKisList() async {
    await _autoSave.flush();
    if (!mounted) return;
    await Navigator.push<void>(context, _slideFromLeft(const StreamScreen()));
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
        context, _slideFromRight(const SettingsScreen()));
  }

  Future<void> _onToss() async {
    final body = _editorController.currentValue;
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to toss — write something first.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final enabled = ref.read(enabledTransportsProvider);
    if (enabled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No transports enabled.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Smart send: skip the picker sheet when exactly one transport is enabled
    // (#85). The sheet is still shown for 2+ transports.
    final TransportPlugin? plugin;
    if (enabled.length == 1) {
      plugin = enabled.first;
    } else {
      plugin = await showModalBottomSheet<TransportPlugin>(
        context: context,
        builder: (_) => TossPickerSheet(plugins: enabled),
      );
    }
    if (plugin == null || !mounted) return;

    await _autoSave.flush();
    if (!mounted) return;

    final now = DateTime.now();
    final ctx = TossContext(
      firedAt: now,
      quki: QukiMetadata(
        id: _autoSave.savedId ?? 'unsaved',
        createdAt: now,
        modifiedAt: now,
      ),
    );

    TossResult result;
    try {
      result = await plugin.toss(
        markdown: body,
        images: const [],
        ctx: ctx,
      );
    } catch (e, st) {
      _log.severe('plugin.toss threw unexpectedly', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Send failed — unexpected error.'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: 'Retry', onPressed: _onToss),
        ),
      );
      return;
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message ?? (result.success ? 'Sent!' : 'Send failed.'),
        ),
        duration: result.success
            ? const Duration(seconds: 2)
            : const Duration(seconds: 4),
        action: (!result.success && result.retryable)
            ? SnackBarAction(label: 'Retry', onPressed: _onToss)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    ref.listen<String?>(activeQukiIdProvider, (previous, next) {
      if (previous == next) return;
      _onActiveQukiChanged(next);
    });

    // Pre-subscribe so SharedPreferences has loaded by the time the user taps
    // Send — prevents the loading-state [] from triggering "No transports".
    ref.watch(enabledTransportsProvider);

    // Disable the QuKis icon when there are no saved QuKis (#86).
    final hasQukis = ref.watch(quKiIndexProvider).maybeWhen(
          data: (list) => list.isNotEmpty,
          orElse: () => false,
        );

    final Widget scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(LucideIcons.fileStack),
          tooltip: 'QuKis',
          onPressed: hasQukis ? _openQuKisList : null,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.type),
            tooltip:
                _editorController.plainTextMode ? 'Block mode' : 'Plain text',
            onPressed: () =>
                setState(() => _editorController.togglePlainTextMode()),
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'New QuKi',
            onPressed: _newQuKi,
          ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.menu),
            tooltip: 'Menu',
            onSelected: (value) {
              switch (value) {
                case 'send':
                  _onToss();
                  break;
                case 'qukis':
                  _openQuKisList();
                  break;
                case 'settings':
                  _openSettings();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'send', child: Text('Send...')),
              PopupMenuItem(value: 'qukis', child: Text('QuKis')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MarkdownEditor(
                initialValue: '',
                onChanged: (_) => _autoSave.notifyChanged(),
                controller: _editorController,
                autofocus: true,
                config: MarkdownEditorConfig(
                  textStyle: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            FormattingToolbar(controller: _editorController),
          ],
        ),
      ),
    );

    if (Platform.isWindows || Platform.isLinux) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
            _onToss();
          },
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
            _newQuKi();
          },
        },
        child: Focus(autofocus: true, skipTraversal: true, child: scaffold),
      );
    }
    return scaffold;
  }
}
