import 'dart:io' show File, Platform;

import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app.dart';
import '../../core/storage/quki_index.dart';
import '../../core/transports/registry_provider.dart';
import '../../core/transports/transport_plugin.dart';

import 'auto_save_controller.dart';
import 'transport_picker_sheet.dart';
import '../settings/help_dialog.dart';
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
    _editorController.onFocusChanged = () {
      if (mounted) setState(() {});
    };

    _autoSave = AutoSaveController(
      onSave: _writeQuKi,
      getBody: () => _editorController.currentValue,
    );
    _autoSave.start();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      if (prefs.getBool('plainTextMode') ?? false) {
        setState(() => _editorController.togglePlainTextMode());
      }
    });
  }

  @override
  void dispose() {
    _editorController.onFocusChanged = null;
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
  }

  /// Write callback for [AutoSaveController]. Creates or updates the file and
  /// keeps [quKiIndexProvider] in sync. Returns the QuKi ID (new or existing).
  Future<String> _writeQuKi(String? currentId, String body) async {
    final storage = ref.read(quKiStorageProvider);
    if (currentId != null) {
      final modifiedAt = await storage.update(currentId, body);
      ref.read(quKiIndexProvider.notifier).updateMeta(currentId, modifiedAt);
      return currentId;
    } else {
      final meta = await storage.create(body);
      ref.read(quKiIndexProvider.notifier).addMeta(meta);
      return meta.id;
    }
  }

  /// Resolves an image path from markdown source to raw bytes.
  ///
  /// [rawPath] is the string extracted from `![alt](rawPath)` — typically a
  /// relative path like `../images/foo.jpg`.  It is resolved relative to the
  /// QuKi storage root (the directory that holds the `.md` files), so
  /// `../images/foo.jpg` from a QuKi file resolves to `<storageRoot>/../images/`
  /// which matches the ADR-4 images directory at `<storageRoot>/images/`.
  ///
  /// Returns null on any error (file not found, permission denied, etc.) so
  /// the editor shows a gray placeholder instead of crashing.
  Future<Uint8List?> _loadImage(String rawPath) async {
    try {
      final storagePath = ref.read(quKiStorageProvider).basePath;
      final resolved = p.normalize(p.join(storagePath, rawPath));
      final file = File(resolved);
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Toggles the checkbox marker at [sourceOffset] in the current editor value.
  ///
  /// Reads the 6-char marker starting at [sourceOffset] and swaps
  /// '- [ ] ' ↔ '- [x] ' (uppercase '- [X] ' is also treated as checked).
  /// Calls [_editorController.setValue] to update the editor, then notifies
  /// [_autoSave] so the change is persisted.
  void _onCheckboxToggle(int sourceOffset) {
    final current = _editorController.currentValue;
    if (sourceOffset < 0 || sourceOffset + 6 > current.length) return;
    final marker = current.substring(sourceOffset, sourceOffset + 6);
    final String replacement;
    if (marker == '- [ ] ') {
      replacement = '- [x] ';
    } else if (marker == '- [x] ' || marker == '- [X] ') {
      replacement = '- [ ] ';
    } else {
      return;
    }
    final newText =
        current.replaceRange(sourceOffset, sourceOffset + 6, replacement);
    _editorController.setValue(newText);
    _autoSave.notifyChanged();
  }

  /// Opens [url] in the platform's default browser.
  ///
  /// Errors from [Uri.parse] (malformed URL) or [launchUrl] (no handler found)
  /// are swallowed silently — no crash, no snackbar.  A snackbar for failed
  /// launches can be added in a future polish pass.
  Future<void> _onLinkTap(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently ignore — bad URL or no app available to handle it.
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

    _autoSave.resetForQuki(id: qukiId, initialBody: body);
    if (qukiId == null) {
      _editorController.requestFocus();
    } else {
      _editorController.unfocus();
    }
  }

  Future<void> _newQuKi() async {
    if (ref.read(activeQukiIdProvider) == null) {
      await _autoSave.flush();
      if (!mounted) return;
      _editorController.setValue('');
      _autoSave.resetForQuki(id: null);
      _editorController.requestFocus();
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

  Future<void> _onTransport() async {
    final body = _editorController.currentValue;
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to send — write something first.'),
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
            duration: Duration(seconds: 2)),
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
        builder: (_) => TransportPickerSheet(plugins: enabled),
      );
    }
    if (plugin == null || !mounted) return;

    await _autoSave.flush();
    if (!mounted) return;

    final now = DateTime.now();
    final ctx = TransportContext(
      firedAt: now,
      quki: QukiMetadata(
          id: _autoSave.savedId ?? 'unsaved', createdAt: now, modifiedAt: now),
    );

    TransportResult result;
    try {
      result =
          await plugin.transport(markdown: body, images: const [], ctx: ctx);
    } catch (e, st) {
      _log.severe('plugin.transport threw unexpectedly', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Send failed — unexpected error.'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: 'Retry', onPressed: _onTransport),
        ),
      );
      return;
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(result.message ?? (result.success ? 'Sent!' : 'Send failed.')),
        duration: result.success
            ? const Duration(seconds: 2)
            : const Duration(seconds: 4),
        action: (!result.success && result.retryable)
            ? SnackBarAction(label: 'Retry', onPressed: _onTransport)
            : null,
      ),
    );
  }

  Widget _tButtonWidget() {
    if (_editorController.plainTextMode) return const Icon(LucideIcons.codeXml);
    if (_editorController.hasActiveBlock) return const _MarkdownMarkIcon();
    return const Icon(LucideIcons.bookOpen);
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
    final hasQukis = ref
        .watch(quKiIndexProvider)
        .maybeWhen(data: (list) => list.isNotEmpty, orElse: () => false);

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
            icon: _tButtonWidget(),
            tooltip: _editorController.plainTextMode
                ? 'Rendered mode'
                : 'Plain text',
            onPressed: () async {
              setState(() => _editorController.togglePlainTextMode());
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(
                  'plainTextMode', _editorController.plainTextMode);
            },
          ),
          IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: 'New QuKi',
              onPressed: _newQuKi),
          IconButton(
            icon: const Icon(LucideIcons.circleHelp),
            tooltip: 'Help',
            onPressed: () => showHelpDialog(context),
          ),
          IconButton(
            icon: const Icon(LucideIcons.send),
            tooltip: 'Send',
            onPressed: _onTransport,
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
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
                config: MarkdownEditorConfig(
                  textStyle: TextStyle(
                      color: scheme.onSurface, fontSize: 16, height: 1.4),
                  contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
                ),
                imageLoader: _loadImage,
                onLinkTap: _onLinkTap,
                onCheckboxToggle: _onCheckboxToggle,
              ),
            ),
            if (_editorController.hasActiveBlock)
              FormattingToolbar(controller: _editorController),
          ],
        ),
      ),
    );

    if (Platform.isWindows || Platform.isLinux) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
            _onTransport();
          },
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
            _newQuKi();
          },
        },
        child: Focus(skipTraversal: true, child: scaffold),
      );
    }
    return scaffold;
  }
}

// Markdown mark icon — standard markdown logo (M + ↓ inside a rounded rect).
// Drawn as a CustomPainter so no external SVG dependency is needed.
// Inherits color from the ambient IconTheme.
class _MarkdownMarkIcon extends StatelessWidget {
  const _MarkdownMarkIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.white;
    return CustomPaint(
      size: const Size(24, 15),
      painter: _MarkdownMarkPainter(color: color),
    );
  }
}

class _MarkdownMarkPainter extends CustomPainter {
  const _MarkdownMarkPainter({required this.color});
  final Color color;

  // SVG viewBox is 0 0 208 128; scale uniformly to painter size.
  static const double _vw = 208;
  static const double _vh = 128;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _vw;
    final sy = size.height / _vh;
    canvas.scale(sx, sy);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromLTRBR(5, 5, 203, 123, const Radius.circular(10)),
      stroke,
    );

    // "M" glyph
    canvas.drawPath(
      Path()
        ..moveTo(30, 98)
        ..lineTo(30, 30)
        ..lineTo(50, 30)
        ..lineTo(70, 55)
        ..lineTo(90, 30)
        ..lineTo(110, 30)
        ..lineTo(110, 98)
        ..lineTo(90, 98)
        ..lineTo(90, 59)
        ..lineTo(70, 84)
        ..lineTo(50, 59)
        ..lineTo(50, 98)
        ..close(),
      fill,
    );

    // Down-arrow "↓" glyph
    canvas.drawPath(
      Path()
        ..moveTo(155, 98)
        ..lineTo(125, 65)
        ..lineTo(145, 65)
        ..lineTo(145, 30)
        ..lineTo(165, 30)
        ..lineTo(165, 65)
        ..lineTo(185, 65)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(_MarkdownMarkPainter old) => old.color != color;
}
