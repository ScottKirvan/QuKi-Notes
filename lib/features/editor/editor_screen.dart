import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import 'formatting_toolbar.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final String? qukiId;
  final String? initialBody;
  // Used when the editor is the root (can't pop). Called after save.
  final Future<void> Function(BuildContext)? onLeave;

  const EditorScreen({super.key, this.qukiId, this.initialBody, this.onLeave});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  late final SuperEditorAndroidControlsController _androidController;
  final _docLayoutKey = GlobalKey();
  // Tracks the DB id after a new QuKi is first saved, so repeat
  // presses of ← Stream update rather than insert a second row.
  String? _savedQukiId;

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
    _androidController.dispose();
    _editor.dispose();
    super.dispose();
  }

  Future<void> _onLeave() async {
    await _saveIfNeeded();
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      await widget.onLeave?.call(context);
    }
  }

  // Minimal save-on-navigate-away. Phase 1.5 replaces this with full
  // debounced auto-save + lifecycle hooks (ADR-6).
  Future<void> _saveIfNeeded() async {
    final body = _extractBody();
    if (body.isEmpty) return;
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    final effectiveId = widget.qukiId ?? _savedQukiId;
    if (effectiveId != null) {
      await db.qukisDao.updateQuki(QukisCompanion(
        id: Value(effectiveId),
        body: Value(body),
        modifiedAt: Value(now),
      ));
    } else {
      final id = const Uuid().v4();
      setState(() => _savedQukiId = id);
      await db.qukisDao.insertQuki(QukisCompanion(
        id: Value(id),
        body: Value(body),
        createdAt: Value(now),
        modifiedAt: Value(now),
      ));
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
    return Scaffold(
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
              onPressed: null, // Phase 2
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
  }
}
