import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:super_editor/super_editor.dart';

import '../../app.dart';
import '../../core/database/database_provider.dart';
import '../../core/transports/registry_provider.dart';
import '../../core/transports/transport_plugin.dart';

import 'auto_save_controller.dart';
import 'formatting_toolbar.dart';
import 'markdown_inline_reactions.dart';
import 'toss_picker_sheet.dart';
import '../settings/settings_screen.dart';
import '../stream/stream_screen.dart';

/// Builds an [Editor] with the default reaction pipeline plus custom inline
/// markdown reactions (bold, italic, code, task list).
Editor _createEditor({
  required MutableDocument document,
  required MutableDocumentComposer composer,
}) {
  return Editor(
    editables: {
      Editor.documentKey: document,
      Editor.composerKey: composer,
    },
    requestHandlers: List.from(defaultRequestHandlers),
    reactionPipeline: [
      ...defaultEditorReactions,
      const BoldInlineMarkdownReaction(),
      const ItalicInlineMarkdownReaction(),
      const CodeInlineMarkdownReaction(),
      const TaskListMarkdownReaction(),
    ],
  );
}

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
  late MutableDocument _document;
  late MutableDocumentComposer _composer;
  late Editor _editor;
  late final SuperEditorAndroidControlsController _androidController;
  late final AutoSaveController _autoSave;
  final _docLayoutKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _document = MutableDocument.empty();
    _composer = MutableDocumentComposer();
    _editor = _createEditor(document: _document, composer: _composer);
    _androidController = SuperEditorAndroidControlsController(
      controlsColor: Colors.white,
    );

    final db = ref.read(appDatabaseProvider);
    _autoSave = AutoSaveController(
      dao: db.qukisDao,
      getBody: _extractBody,
    );
    _autoSave.start();

    _document.addListener(_onDocumentChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  MutableDocument _parseBody(String body) {
    if (body.trim().isEmpty) return MutableDocument.empty();
    return deserializeMarkdownToDocument(
      body,
      syntax: MarkdownSyntax.normal,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _document.removeListener(_onDocumentChanged);
    _autoSave.dispose();
    _androidController.dispose();
    _editor.dispose();
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

  void _onDocumentChanged(DocumentChangeLog _) => _autoSave.notifyChanged();

  Future<void> _onActiveQukiChanged(String? qukiId) async {
    await _autoSave.flush();
    if (!mounted) return;

    String body = '';
    if (qukiId != null) {
      final db = ref.read(appDatabaseProvider);
      final quki = await db.qukisDao.getById(qukiId);
      if (!mounted) return;
      body = quki?.body ?? '';
    }

    _switchDocument(body);
    _autoSave.resetForQuki(id: qukiId);
  }

  void _switchDocument(String body) {
    _document.removeListener(_onDocumentChanged);
    _editor.dispose();

    final newDoc = _parseBody(body);
    final newComposer = MutableDocumentComposer();
    final newEditor = _createEditor(document: newDoc, composer: newComposer);

    setState(() {
      _document = newDoc;
      _composer = newComposer;
      _editor = newEditor;
    });

    _document.addListener(_onDocumentChanged);
  }

  Future<void> _newQuKi() async {
    if (ref.read(activeQukiIdProvider) == null) {
      // Provider already null — listener won't fire, handle inline.
      await _autoSave.flush();
      if (!mounted) return;
      _switchDocument('');
      _autoSave.resetForQuki(id: null);
    } else {
      // _onActiveQukiChanged(null) will handle flush + switch.
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
    final body = _extractBody();
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

    final plugin = await showModalBottomSheet<TransportPlugin>(
      context: context,
      builder: (_) => TossPickerSheet(plugins: enabled),
    );
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

    final result = await plugin.toss(
      markdown: body,
      images: const [],
      ctx: ctx,
    );
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

  String _extractBody() {
    return serializeDocumentToMarkdown(
      _document,
      syntax: MarkdownSyntax.normal,
    ).trim();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    ref.listen<String?>(activeQukiIdProvider, (previous, next) {
      if (previous == next) return;
      _onActiveQukiChanged(next);
    });

    final Widget scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(LucideIcons.fileStack),
          tooltip: 'QuKis',
          onPressed: _openQuKisList,
        ),
        actions: [
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
              child: SuperEditorAndroidControlsScope(
                controller: _androidController,
                child: SuperEditor(
                  editor: _editor,
                  documentLayoutKey: _docLayoutKey,
                  stylesheet: defaultStylesheet.copyWith(
                    addRulesAfter: [
                      StyleRule(
                        BlockSelector.all,
                        (doc, node) => {
                          Styles.maxWidth: double.infinity,
                          Styles.padding: const CascadingPadding.symmetric(
                            horizontal: 16,
                            vertical: 0,
                          ),
                          Styles.textStyle: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 16,
                            height: 1.4,
                          ),
                        },
                      ),
                      StyleRule(
                        const BlockSelector('header1'),
                        (doc, node) => {
                          Styles.textStyle: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        },
                      ),
                      StyleRule(
                        const BlockSelector('header2'),
                        (doc, node) => {
                          Styles.textStyle: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        },
                      ),
                      StyleRule(
                        const BlockSelector('header3'),
                        (doc, node) => {
                          Styles.textStyle: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            FormattingToolbar(
              editor: _editor,
              document: _document,
              composer: _composer,
              documentLayoutResolver: () =>
                  _docLayoutKey.currentState as DocumentLayout,
            ),
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
