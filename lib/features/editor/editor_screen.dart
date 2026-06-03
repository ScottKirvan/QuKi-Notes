import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';

import '../../core/database/database_provider.dart';
import '../../core/transports/registry_provider.dart';
import '../../core/transports/transport_plugin.dart';

import 'auto_save_controller.dart';
import 'formatting_toolbar.dart';
import 'toss_picker_sheet.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final String? qukiId;
  final String? initialBody;
  // Used when the editor is the root (can't pop). Called after save.
  final Future<void> Function(BuildContext)? onLeave;

  const EditorScreen({super.key, this.qukiId, this.initialBody, this.onLeave});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with WidgetsBindingObserver {
  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  late final SuperEditorAndroidControlsController _androidController;
  late final AutoSaveController _autoSave;
  final _docLayoutKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _document = _parseInitialBody(widget.initialBody ?? '');
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
    _androidController = SuperEditorAndroidControlsController(
      controlsColor: Colors.white,
    );

    final db = ref.read(appDatabaseProvider);
    _autoSave = AutoSaveController(
      dao: db.qukisDao,
      getBody: _extractBody,
      initialId: widget.qukiId,
    );
    _autoSave.start();

    _document.addListener(_onDocumentChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  // Plain-text loading; full markdown round-trip lands in Phase 3 (OQ-1).
  // Splits on double-newline so paragraph breaks survive the save/reload cycle.
  MutableDocument _parseInitialBody(String body) {
    if (body.isEmpty) return MutableDocument.empty();
    final paras = body
        .split('\n\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paras.isEmpty) return MutableDocument.empty();
    return MutableDocument(nodes: [
      for (int i = 0; i < paras.length; i++)
        ParagraphNode(id: 'p$i', text: AttributedText(paras[i])),
    ]);
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

  Future<void> _onToss() async {
    final body = _extractBody();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to toss — write something first.'),
        ),
      );
      return;
    }

    final enabled = ref.read(enabledTransportsProvider);
    if (enabled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No transports enabled.')),
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
          result.message ?? (result.success ? 'Tossed!' : 'Toss failed.'),
        ),
        action: (!result.success && result.retryable)
            ? SnackBarAction(label: 'Retry', onPressed: _onToss)
            : null,
      ),
    );
  }

  Future<void> _onLeave() async {
    await _autoSave.flush();
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      await widget.onLeave?.call(context);
    }
  }

  String _extractBody() {
    final parts = <String>[];
    for (int i = 0; i < _document.nodeCount; i++) {
      final node = _document.getNodeAt(i);
      if (node is ListItemNode) {
        final text = node.text.toPlainText().trim();
        if (text.isNotEmpty) {
          parts.add(
            node.type == ListItemType.unordered ? '- $text' : '1. $text',
          );
        }
      } else if (node is ParagraphNode) {
        final text = node.text.toPlainText().trim();
        if (text.isNotEmpty) parts.add(text);
      }
    }
    return parts.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 110,
        leading: TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.only(left: 4),
            foregroundColor: scheme.onSurface,
          ),
          onPressed: _onLeave,
          icon: const Icon(Icons.arrow_back_ios, size: 16),
          label: const Text('Stream'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: OutlinedButton.icon(
              onPressed: _onToss,
              icon: const Icon(Icons.send_outlined, size: 14),
              label: const Text('Toss ▼'),
            ),
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
                          Styles.padding:
                              const CascadingPadding.symmetric(horizontal: 16),
                          Styles.textStyle: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 16,
                            height: 1.4,
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
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _onLeave();
          },
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
            _onToss();
          },
        },
        child: Focus(autofocus: true, skipTraversal: true, child: scaffold),
      );
    }
    return scaffold;
  }
}
