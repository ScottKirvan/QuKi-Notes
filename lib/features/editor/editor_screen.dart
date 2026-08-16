import 'dart:async';
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
import '../share_in/share_handler.dart' show isMobileProvider;
import '../stream/stream_screen.dart';

final _log = Logger('EditorScreen');

// TEMP DEBUG (notes/dev/keyboard_focus_state.md verification round, Round 3)
// — see keyboard_focus_debug.dart's header comment for the full removal
// list. Must match MainActivity.kt's channel name exactly.
const _lifecycleDebugChannelName = 'com.quki.quki_notes/lifecycle_debug';

// Tightens the default Material IconButton footprint (48x48 on mobile via
// its invisible tap-target padding, 40x40 on desktop) down to a smaller,
// still-comfortably-tappable size, so the AppBar's action buttons read as
// one dense group instead of having a large visible gap between them.
// `tapTargetSize: shrinkWrap` removes the mobile-only invisible minimum
// (Android/iOS default to `padded`, which otherwise wins over the smaller
// content-driven size); `minimumSize`/`padding` then set the actual visible
// footprint uniformly across all platforms.
const _tightIconButtonStyle = ButtonStyle(
  padding: WidgetStatePropertyAll(EdgeInsets.all(6)),
  minimumSize: WidgetStatePropertyAll(Size(36, 36)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

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
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _editorController = MarkdownEditorController();
    _editorController.onFocusChanged = () {
      // TEMP DEBUG (notes/dev/keyboard_focus_state.md verification round) —
      // remove this one line (see keyboard_focus_debug.dart's header
      // comment for the full removal list). Records a focus gained/lost
      // transition as a proxy for requestFocus()/unfocus() taking effect —
      // see KeyboardFocusDebugCounters' own doc comment for why a proxy is
      // used instead of instrumenting every call site.
      KeyboardFocusDebugCounters.instance
          .recordFocusChange(hasFocus: _editorController.hasActiveBlock);
      if (mounted) setState(() {});
    };

    _autoSave = AutoSaveController(
      onSave: _writeQuKi,
      getBody: () => _editorController.currentValue,
    );
    _autoSave.start();

    WidgetsBinding.instance.addObserver(this);

    // TEMP DEBUG (notes/dev/keyboard_focus_state.md verification round,
    // Round 3) — see keyboard_focus_debug.dart's header comment for the full
    // removal list, and MainActivity.kt for the native side of this channel.
    // Records Activity.onNewIntent() firing, to test the hypothesis that
    // launchMode="singleTask" (set for #188) is implicated in the
    // keyboard-dismissed-on-resume bug. Harmless on platforms where the
    // native side never calls it (nothing ever invokes this handler).
    const MethodChannel(_lifecycleDebugChannelName)
        .setMethodCallHandler((call) async {
      if (call.method == 'onNewIntent') {
        KeyboardFocusDebugCounters.instance.recordOnNewIntent();
      }
    });

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
    _dismissTimer?.cancel();
    _editorController.onFocusChanged = null;
    WidgetsBinding.instance.removeObserver(this);
    // TEMP DEBUG (notes/dev/keyboard_focus_state.md verification round,
    // Round 3) — remove alongside the handler registration in initState().
    const MethodChannel(_lifecycleDebugChannelName).setMethodCallHandler(null);
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
  /// [sourceOffset] is the checkbox element's own source offset as resolved
  /// by `checkboxSourceOffsetForTap()` — which is always the LINE's absolute
  /// start (`MdElement.start` / `lineStart` in md_parser.dart, for both the
  /// non-nested and the indented/nested checkbox branches). For a non-nested
  /// checkbox that happens to be the marker's own start ('-'), but for a
  /// nested checkbox it is BEFORE the leading indentation whitespace — the
  /// real marker begins `wsLen` characters later. Skipping any leading
  /// space/tab characters first (mirroring `MdParser._listIndent`'s own
  /// whitespace consumption) finds the marker's actual start regardless of
  /// nesting depth; for a non-nested checkbox this is a zero-iteration no-op,
  /// so that path is unchanged (#354).
  ///
  /// Reads the 6-char marker starting at the resolved marker start and swaps
  /// '- [ ] ' ↔ '- [x] ' (uppercase '- [X] ' is also treated as checked).
  /// Calls [_editorController.setValuePreservingSelection] — NOT [setValue]
  /// — to update the editor, then notifies [_autoSave] so the change is
  /// persisted. A checkbox toggle is an in-place content edit, not a
  /// document switch: [setValue] resets the selection to the top on purpose
  /// for opening a different QuKi, which is wrong here (#335, #266) — it
  /// would jump the cursor away from wherever it actually was, and if reset
  /// to offset 0 happened to land inside a still-collapsed markdown element,
  /// reveal that line as raw source too.
  ///
  /// Passes `scrollToCaret: false` — a checkbox tap never moves the
  /// selection, so scrolling to keep the (unmoved) caret in view had no
  /// connection to the checkbox that was actually tapped and only produced
  /// an unwanted viewport jump.
  void _onCheckboxToggle(int sourceOffset) {
    final current = _editorController.currentValue;
    if (sourceOffset < 0 || sourceOffset > current.length) return;
    var markerStart = sourceOffset;
    while (markerStart < current.length &&
        (current[markerStart] == ' ' || current[markerStart] == '\t')) {
      markerStart++;
    }
    if (markerStart + 6 > current.length) return;
    final marker = current.substring(markerStart, markerStart + 6);
    final String replacement;
    if (marker == '- [ ] ') {
      replacement = '- [x] ';
    } else if (marker == '- [x] ' || marker == '- [X] ') {
      replacement = '- [ ] ';
    } else {
      return;
    }
    final newText =
        current.replaceRange(markerStart, markerStart + 6, replacement);
    _editorController.setValuePreservingSelection(newText,
        scrollToCaret: false);
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
    // AppBar state that reads _autoSave.savedId directly (e.g. the Trash
    // button's enabled/disabled gate) otherwise has no reliable rebuild
    // trigger here: unfocus()/requestFocus() below only rebuilds via
    // onFocusChanged when they actually change the focus state, and
    // switching to an existing QuKi is a no-op call to unfocus() whenever
    // the editor was already unfocused (e.g. immediately after returning
    // from the QuKis list, which already unfocuses the underlying editor
    // route on push) — silently leaving that AppBar state stale until some
    // unrelated rebuild happens to occur.
    if (mounted) setState(() {});
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

  /// Soft-deletes the currently-open QuKi (no confirmation — matches the
  /// QuKis list screen's own swipe-to-delete) and resets the editor to a
  /// blank new note, the same end state as tapping "+New" (see [_newQuKi]).
  ///
  /// Only reachable when [AutoSaveController.savedId] is non-null — the
  /// Trash button is disabled (`onPressed: null`) on a brand-new, never-
  /// saved note, since there is nothing on disk yet to delete.
  ///
  /// The editor content and [_autoSave]'s id tracking are both cleared
  /// *before* the filesystem delete, and before any `await` — not after.
  /// [AutoSaveController] has an independent 2s debounce and 30s periodic
  /// timer (ADR-6) that could otherwise fire mid-delete and write the
  /// still-displayed (now-stale) body back under this QuKi's id, recreating
  /// the very file [QuKiStorage.softDelete] just moved to `.trash/`.
  /// Clearing the body to '' makes any such write a no-op regardless of
  /// timing, since [AutoSaveController.save] already skips empty bodies.
  Future<void> _deleteCurrentQuki() async {
    final id = _autoSave.savedId;
    if (id == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final storage = ref.read(quKiStorageProvider);

    _editorController.setValue('');
    _autoSave.resetForQuki(id: null);

    await storage.softDelete(id);
    if (!mounted) return;

    ref.read(quKiIndexProvider.notifier).removeMeta(id);

    if (ref.read(activeQukiIdProvider) == id) {
      // activeQukiIdProvider was pointing at this QuKi (it was opened via
      // the QuKis list) — setting it to null triggers the existing
      // ref.listen -> _onActiveQukiChanged(null) reset path, the same one
      // StreamScreen's own delete already relies on when the deleted QuKi
      // is the one currently open. Safe to let its flush() run: the editor
      // and _autoSave were already cleared above, so it's a no-op.
      ref.read(activeQukiIdProvider.notifier).setId(null);
    } else {
      // activeQukiIdProvider never pointed at this QuKi in the first place
      // — e.g. a brand-new note that autosaved once but was never opened
      // via the QuKis list, so nothing ever routed its id into that
      // provider (the identical asymmetry _newQuKi's `id == null` branch
      // already handles). setId(null) would be a no-op here (already
      // null), so the listener above won't fire — land on the same "+New"
      // end state directly instead.
      _editorController.requestFocus();
    }

    if (!mounted) return;
    _dismissTimer?.cancel();
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      const SnackBar(
        content: Text('QuKi moved to Trash.'),
        duration: Duration(milliseconds: 1500),
      ),
    );
    // See stream_screen.dart's _delete() for why this app drives dismissal
    // with an explicit Timer alongside SnackBar's own duration.
    _dismissTimer = Timer(const Duration(milliseconds: 1500), () {
      _dismissTimer = null;
      controller.close();
    });
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

  Widget _tButtonWidget(bool keyboardVisible) {
    if (_editorController.plainTextMode) return const Icon(LucideIcons.codeXml);
    if (keyboardVisible) return const _MarkdownMarkIcon();
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

    // Ground truth for FormattingToolbar visibility and the T-button's
    // edit-vs-reading-mode icon variant (notes/dev/keyboard_focus_state.md's
    // Round 2 pivot). On mobile this follows the OS's own live keyboard-
    // visible signal (MediaQuery.viewInsets.bottom > 0), not
    // FocusNode.hasFocus — Round 1's on-device diagnostics proved focus
    // stays true even after the Android keyboard visibly disappears. Desktop
    // has no software keyboard (viewInsets.bottom is always 0 there), so it
    // keeps the pre-pivot FocusNode.hasFocus-driven behavior via
    // hasActiveBlock — this whole investigation was scoped to Android/mobile
    // only (notes/dev/keyboard_state_testing.md), and unconditionally
    // switching to viewInsets would make the toolbar/T-button permanently
    // read as "reading mode" on Windows/Linux.
    final isMobile = ref.watch(isMobileProvider);
    final keyboardVisible = isMobile
        ? MediaQuery.viewInsetsOf(context).bottom > 0
        : _editorController.hasActiveBlock;

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
            style: _tightIconButtonStyle,
            icon: _tButtonWidget(keyboardVisible),
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
              style: _tightIconButtonStyle,
              icon: const Icon(LucideIcons.plus),
              tooltip: 'New QuKi',
              onPressed: _newQuKi),
          IconButton(
            style: _tightIconButtonStyle,
            icon: const Icon(LucideIcons.circleHelp),
            tooltip: 'Help',
            onPressed: () => showHelpDialog(context),
          ),
          IconButton(
            style: _tightIconButtonStyle,
            icon: const Icon(LucideIcons.send),
            tooltip: 'Send',
            onPressed: _onTransport,
          ),
          IconButton(
            style: _tightIconButtonStyle,
            icon: const Icon(LucideIcons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          IconButton(
            style: _tightIconButtonStyle,
            icon: const Icon(LucideIcons.trash2),
            tooltip: 'Delete',
            // Deliberately last and separated from Send by every other
            // action — a mistaken tap should not be able to land on this
            // destructive action instead of the primary one.
            onPressed: _autoSave.savedId != null ? _deleteCurrentQuki : null,
          ),
        ],
      ),
      body: SafeArea(
        // TEMP DEBUG (notes/dev/keyboard_focus_state.md verification round)
        // — the Stack + KeyboardFocusDebugOverlay() below is the whole
        // wiring point for the on-screen counter badge. Remove the Stack
        // wrapper (restoring the plain Column as SafeArea's direct child)
        // once that doc's device-verification checklist is done — see
        // keyboard_focus_debug.dart's header comment for the full removal
        // list.
        child: Stack(
          children: [
            Column(
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
                if (keyboardVisible)
                  FormattingToolbar(controller: _editorController),
              ],
            ),
            const KeyboardFocusDebugOverlay(),
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
