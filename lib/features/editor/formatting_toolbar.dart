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
    required this.keyboardVisible,
    required this.onToggleKeyboard,
  });

  final Editor editor;
  final MutableDocument document;
  final MutableDocumentComposer composer;
  final DocumentLayoutResolver documentLayoutResolver;

  /// Whether the IME keyboard is currently visible. Tracked as a separate
  /// boolean in [_EditorScreenState] rather than inferred from [FocusNode.hasFocus]
  /// because focus and keyboard visibility can diverge (known #72 issue at cold
  /// launch). (#post-96)
  final bool keyboardVisible;

  /// Called when the user taps the keyboard toggle button. The caller is
  /// responsible for requesting / releasing focus and updating [keyboardVisible].
  final VoidCallback onToggleKeyboard;

  CommonEditorOperations get _ops => CommonEditorOperations(
        document: document,
        editor: editor,
        composer: composer,
        documentLayoutResolver: documentLayoutResolver,
      );

  @override
  Widget build(BuildContext context) {
    // Rebuild when selection changes so format buttons can be enabled/disabled
    // based on whether the user has placed a cursor (#post-96, Bug 4).
    return ListenableBuilder(
      listenable: composer,
      builder: (context, _) {
        final hasSelection = composer.selection != null;
        return Material(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                _ToolbarButton(
                  icon: LucideIcons.bold,
                  tooltip: 'Bold',
                  onPressed: hasSelection
                      ? () => _ops
                          .toggleAttributionsOnSelection({boldAttribution})
                      : null,
                ),
                _ToolbarButton(
                  icon: LucideIcons.italic,
                  tooltip: 'Italic',
                  onPressed: hasSelection
                      ? () => _ops.toggleAttributionsOnSelection(
                          {italicsAttribution})
                      : null,
                ),
                _ToolbarButton(
                  icon: LucideIcons.strikethrough,
                  tooltip: 'Strikethrough',
                  onPressed: hasSelection
                      ? () => _ops.toggleAttributionsOnSelection(
                          {strikethroughAttribution})
                      : null,
                ),
                _ToolbarButton(
                  icon: LucideIcons.list,
                  tooltip: 'Bullet list',
                  onPressed: hasSelection
                      ? () => _convertToList(ListItemType.unordered)
                      : null,
                ),
                _ToolbarButton(
                  icon: LucideIcons.listOrdered,
                  tooltip: 'Numbered list',
                  onPressed: hasSelection
                      ? () => _convertToList(ListItemType.ordered)
                      : null,
                ),
                _ToolbarButton(
                  icon: LucideIcons.listChecks,
                  tooltip: 'Task list item',
                  onPressed: hasSelection ? () => _insertTaskListItem() : null,
                ),
                _ToolbarButton(
                  icon: LucideIcons.link,
                  tooltip: 'Link',
                  onPressed: () => _showLinkStub(context),
                ),
                const Spacer(),
                // Keyboard toggle: shows keyboardOff when keyboard is visible,
                // keyboard icon when it is not. Driven by [keyboardVisible]
                // rather than FocusNode.hasFocus because focus and keyboard
                // visibility can diverge at cold launch (#72, #post-96).
                _ToolbarButton(
                  icon: keyboardVisible
                      ? LucideIcons.keyboardOff
                      : LucideIcons.keyboard,
                  tooltip: keyboardVisible ? 'Dismiss keyboard' : 'Show keyboard',
                  onPressed: onToggleKeyboard,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _convertToList(ListItemType type) {
    final selection = composer.selection;
    if (selection == null) return;
    final node = document.getNodeById(selection.extent.nodeId);
    if (node is! TextNode) return;
    _ops.convertToListItem(type, node.text);
  }

  /// Converts the current paragraph node to a [TaskNode] (unchecked task list
  /// item). Uses [ReplaceNodeRequest] directly rather than inserting `- [ ] `
  /// text and relying on [TaskListMarkdownReaction] — the reaction uses
  /// [EditInspector.findLastTextUserTyped] which does not fire for programmatic
  /// batch insertions, causing the space inside `[ ]` to be lost (#82, #post-96
  /// Bug 5).
  void _insertTaskListItem() {
    final selection = composer.selection;
    if (selection == null) return; // button is disabled when no selection
    final nodeId = selection.extent.nodeId;
    final node = document.getNodeById(nodeId);
    if (node is! TextNode) return;
    editor.execute([
      ReplaceNodeRequest(
        existingNodeId: nodeId,
        newNode: TaskNode(
          id: nodeId,
          text: node.text,
          isComplete: false,
        ),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: nodeId,
            nodePosition: TextNodePosition(offset: node.text.length),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
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
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}
