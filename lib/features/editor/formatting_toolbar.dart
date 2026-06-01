import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class FormattingToolbar extends StatelessWidget {
  const FormattingToolbar({
    super.key,
    required this.editor,
    required this.document,
    required this.composer,
    required this.documentLayoutResolver,
  });

  final Editor editor;
  final MutableDocument document;
  final MutableDocumentComposer composer;
  final DocumentLayoutResolver documentLayoutResolver;

  CommonEditorOperations get _ops => CommonEditorOperations(
        document: document,
        editor: editor,
        composer: composer,
        documentLayoutResolver: documentLayoutResolver,
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            _ToolbarButton(
              icon: Icons.format_bold,
              tooltip: 'Bold',
              onPressed: () =>
                  _ops.toggleAttributionsOnSelection({boldAttribution}),
            ),
            _ToolbarButton(
              icon: Icons.format_italic,
              tooltip: 'Italic',
              onPressed: () =>
                  _ops.toggleAttributionsOnSelection({italicsAttribution}),
            ),
            _ToolbarButton(
              icon: Icons.format_strikethrough,
              tooltip: 'Strikethrough',
              onPressed: () => _ops
                  .toggleAttributionsOnSelection({strikethroughAttribution}),
            ),
            _ToolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Bullet list',
              onPressed: () => _convertToList(ListItemType.unordered),
            ),
            _ToolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: 'Numbered list',
              onPressed: () => _convertToList(ListItemType.ordered),
            ),
            _ToolbarButton(
              icon: Icons.code,
              tooltip: 'Code',
              onPressed: () =>
                  _ops.toggleAttributionsOnSelection({codeAttribution}),
            ),
            _ToolbarButton(
              icon: Icons.link,
              tooltip: 'Link',
              onPressed: () => _showLinkStub(context),
            ),
          ],
        ),
      ),
    );
  }

  void _convertToList(ListItemType type) {
    final selection = composer.selection;
    if (selection == null) return;
    final node = document.getNodeById(selection.extent.nodeId);
    if (node is! TextNode) return;
    _ops.convertToListItem(type, node.text);
  }

  // Link insertion deferred to Phase 3 polish (requires URL dialog + LinkAttribution).
  void _showLinkStub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link formatting coming soon.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
