import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:super_editor/super_editor.dart';

class FormattingToolbar extends StatelessWidget {
  const FormattingToolbar({
    super.key,
    required this.editor,
    required this.document,
    required this.composer,
    required this.documentLayoutResolver,
    required this.focusNode,
  });

  final Editor editor;
  final MutableDocument document;
  final MutableDocumentComposer composer;
  final DocumentLayoutResolver documentLayoutResolver;

  /// The [FocusNode] of the [SuperEditor]. Used to toggle keyboard visibility
  /// (#78).
  final FocusNode focusNode;

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
              icon: LucideIcons.bold,
              tooltip: 'Bold',
              onPressed: () =>
                  _ops.toggleAttributionsOnSelection({boldAttribution}),
            ),
            _ToolbarButton(
              icon: LucideIcons.italic,
              tooltip: 'Italic',
              onPressed: () =>
                  _ops.toggleAttributionsOnSelection({italicsAttribution}),
            ),
            _ToolbarButton(
              icon: LucideIcons.strikethrough,
              tooltip: 'Strikethrough',
              onPressed: () => _ops
                  .toggleAttributionsOnSelection({strikethroughAttribution}),
            ),
            _ToolbarButton(
              icon: LucideIcons.list,
              tooltip: 'Bullet list',
              onPressed: () => _convertToList(ListItemType.unordered),
            ),
            _ToolbarButton(
              icon: LucideIcons.listOrdered,
              tooltip: 'Numbered list',
              onPressed: () => _convertToList(ListItemType.ordered),
            ),
            _ToolbarButton(
              icon: LucideIcons.listChecks,
              tooltip: 'Task list item',
              onPressed: () => _insertTaskListItem(context),
            ),
            _ToolbarButton(
              icon: LucideIcons.link,
              tooltip: 'Link',
              onPressed: () => _showLinkStub(context),
            ),
            const Spacer(),
            // Keyboard toggle: shows keyboardOff when focused (keyboard is up),
            // keyboard icon when unfocused (#78).
            ListenableBuilder(
              listenable: focusNode,
              builder: (context, _) {
                final hasFocus = focusNode.hasFocus;
                return _ToolbarButton(
                  icon:
                      hasFocus ? LucideIcons.keyboardOff : LucideIcons.keyboard,
                  tooltip: hasFocus ? 'Dismiss keyboard' : 'Show keyboard',
                  onPressed: () {
                    if (hasFocus) {
                      FocusScope.of(context).unfocus();
                    } else {
                      focusNode.requestFocus();
                    }
                  },
                );
              },
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

  /// Inserts `- [ ] ` at offset 0 of the current node. The existing
  /// [TaskListMarkdownReaction] picks up the `- [ ] ` prefix and converts the
  /// paragraph to a [TaskNode] automatically.
  void _insertTaskListItem(BuildContext context) {
    final selection = composer.selection;
    if (selection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Place cursor in the editor first.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final nodeId = selection.extent.nodeId;
    editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: nodeId,
          nodePosition: const TextNodePosition(offset: 0),
        ),
        textToInsert: '- [ ] ',
        attributions: const {},
      ),
    ]);
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
