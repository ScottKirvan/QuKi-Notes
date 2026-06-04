import 'package:super_editor/super_editor.dart';

/// Applies bold attribution when the user completes `**text**`.
class BoldInlineMarkdownReaction extends EditReaction {
  const BoldInlineMarkdownReaction();

  @override
  void react(EditContext editorContext, RequestDispatcher requestDispatcher,
      List<EditEvent> changeList) {
    _applyInlineAttribution(
      editContext: editorContext,
      requestDispatcher: requestDispatcher,
      changeList: changeList,
      triggerChar: '*',
      delimiter: '**',
      attribution: boldAttribution,
    );
  }
}

/// Applies italic attribution when the user completes `_text_`.
class ItalicInlineMarkdownReaction extends EditReaction {
  const ItalicInlineMarkdownReaction();

  @override
  void react(EditContext editorContext, RequestDispatcher requestDispatcher,
      List<EditEvent> changeList) {
    _applyInlineAttribution(
      editContext: editorContext,
      requestDispatcher: requestDispatcher,
      changeList: changeList,
      triggerChar: '_',
      delimiter: '_',
      attribution: italicsAttribution,
    );
  }
}

/// Applies inline-code attribution when the user completes `` `text` ``.
class CodeInlineMarkdownReaction extends EditReaction {
  const CodeInlineMarkdownReaction();

  @override
  void react(EditContext editorContext, RequestDispatcher requestDispatcher,
      List<EditEvent> changeList) {
    _applyInlineAttribution(
      editContext: editorContext,
      requestDispatcher: requestDispatcher,
      changeList: changeList,
      triggerChar: '`',
      delimiter: '`',
      attribution: codeAttribution,
    );
  }
}

/// Converts `- [ ] ` typed at the start of a line to a [TaskNode].
///
/// The unordered-list reaction fires first on `- ` and converts the paragraph
/// to a [ListItemNode] (stripping the `- ` prefix). This reaction then watches
/// for a [ListItemNode] whose content is exactly `[ ] ` and replaces it with
/// an empty [TaskNode].
class TaskListMarkdownReaction extends EditReaction {
  const TaskListMarkdownReaction();

  @override
  void react(
    EditContext editorContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    final document = editorContext.document;

    final typedText = EditInspector.findLastTextUserTyped(document, changeList);
    if (typedText == null) return;

    final node = document.getNodeById(typedText.nodeId);
    if (node is! ListItemNode) return;
    if (node.type != ListItemType.unordered) return;
    if (node.text.toPlainText() != '[ ] ') return;

    requestDispatcher.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode:
            TaskNode(id: node.id, text: AttributedText(), isComplete: false),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.contentChange,
      ),
    ]);
  }
}

/// Shared logic: find a complete inline delimiter pair ending at the caret,
/// strip both delimiters, and apply [attribution] to the content between them.
void _applyInlineAttribution({
  required EditContext editContext,
  required RequestDispatcher requestDispatcher,
  required List<EditEvent> changeList,
  required String triggerChar,
  required String delimiter,
  required Attribution attribution,
}) {
  final document = editContext.document;

  final textInsertion = _findLastTextInsertion(changeList);
  if (textInsertion == null) return;
  if (textInsertion.text.toPlainText() != triggerChar) return;

  final node = document.getNodeById(textInsertion.nodeId);
  if (node is! TextNode) return;

  final text = node.text.toPlainText();
  final insertionEnd = textInsertion.offset + triggerChar.length;

  // Verify the just-inserted characters complete the closing delimiter.
  if (insertionEnd < delimiter.length) return;
  if (text.substring(insertionEnd - delimiter.length, insertionEnd) !=
      delimiter) {
    return;
  }

  final closingStart = insertionEnd - delimiter.length;

  // Find the matching opening delimiter before the closing one.
  final openingStart = text.lastIndexOf(delimiter, closingStart - 1);
  if (openingStart < 0) return;

  final contentStart = openingStart + delimiter.length;
  final contentEnd = closingStart; // exclusive
  if (contentStart >= contentEnd) return; // nothing between delimiters

  final contentLength = contentEnd - contentStart;

  // Delete closing delimiter first (rightmost) so opening positions are stable,
  // then delete opening delimiter, then apply attribution to the remaining content.
  requestDispatcher.execute([
    DeleteContentRequest(
      documentRange: DocumentRange(
        start: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: closingStart),
        ),
        end: DocumentPosition(
          nodeId: node.id,
          nodePosition:
              TextNodePosition(offset: closingStart + delimiter.length),
        ),
      ),
    ),
    DeleteContentRequest(
      documentRange: DocumentRange(
        start: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: openingStart),
        ),
        end: DocumentPosition(
          nodeId: node.id,
          nodePosition:
              TextNodePosition(offset: openingStart + delimiter.length),
        ),
      ),
    ),
    // After both deletions, content sits at [openingStart, openingStart + contentLength).
    AddTextAttributionsRequest(
      documentRange: DocumentRange(
        start: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: openingStart),
        ),
        end: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: openingStart + contentLength),
        ),
      ),
      attributions: {attribution},
    ),
    ChangeSelectionRequest(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: openingStart + contentLength),
        ),
      ),
      SelectionChangeType.placeCaret,
      SelectionReason.contentChange,
    ),
  ]);
}

TextInsertionEvent? _findLastTextInsertion(List<EditEvent> changeList) {
  for (final event in changeList.reversed) {
    if (event is DocumentEdit && event.change is TextInsertionEvent) {
      return event.change as TextInsertionEvent;
    }
  }
  return null;
}
