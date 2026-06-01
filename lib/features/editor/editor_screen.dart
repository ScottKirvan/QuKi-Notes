import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';

import 'formatting_toolbar.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  final _docLayoutKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _document = MutableDocument.empty();
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SuperEditor(
          editor: _editor,
          documentLayoutKey: _docLayoutKey,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: FormattingToolbar(
          editor: _editor,
          document: _document,
          composer: _composer,
          documentLayoutResolver: () =>
              _docLayoutKey.currentState as DocumentLayout,
        ),
      ),
    );
  }
}
