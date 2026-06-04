import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:quki_notes/features/editor/markdown_inline_reactions.dart';

// Builds an Editor with the custom inline reactions registered.
Editor _createEditor(MutableDocument document) {
  return Editor(
    editables: {
      Editor.documentKey: document,
      Editor.composerKey: MutableDocumentComposer(),
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

// Inserts [char] at [offset] in the node identified by [nodeId].
void _typeChar(Editor editor, String nodeId, int offset, String char) {
  editor.execute([
    InsertTextRequest(
      documentPosition: DocumentPosition(
        nodeId: nodeId,
        nodePosition: TextNodePosition(offset: offset),
      ),
      textToInsert: char,
      attributions: const {},
    ),
  ]);
}

void main() {
  group('inline markdown reactions', () {
    group('bold (**text**)', () {
      test('typing closing ** applies bold and strips delimiters', () {
        final document = MutableDocument(nodes: [
          ParagraphNode(id: 'p1', text: AttributedText('**bold*')),
        ]);
        final editor = _createEditor(document);

        _typeChar(editor, 'p1', 7, '*');

        final para = document.getNodeById('p1') as ParagraphNode;
        expect(para.text.toPlainText(), 'bold');
        final attributions =
            para.text.getAllAttributionsThroughout(SpanRange(0, 3));
        expect(attributions, contains(boldAttribution));
      });

      test('single * does not trigger bold', () {
        final document = MutableDocument(nodes: [
          ParagraphNode(id: 'p1', text: AttributedText('*notbold')),
        ]);
        final editor = _createEditor(document);

        _typeChar(editor, 'p1', 8, '*');

        final para = document.getNodeById('p1') as ParagraphNode;
        // No delimiters stripped, text unchanged.
        expect(para.text.toPlainText(), '*notbold*');
      });

      test('bold with surrounding text', () {
        final document = MutableDocument(nodes: [
          ParagraphNode(id: 'p1', text: AttributedText('Hello **world*')),
        ]);
        final editor = _createEditor(document);

        _typeChar(editor, 'p1', 14, '*');

        final para = document.getNodeById('p1') as ParagraphNode;
        expect(para.text.toPlainText(), 'Hello world');
        // 'world' starts at offset 6, length 5 → span [6, 10]
        final attributions =
            para.text.getAllAttributionsThroughout(SpanRange(6, 10));
        expect(attributions, contains(boldAttribution));
      });
    });

    group('italic (_text_)', () {
      test('typing closing _ applies italic and strips delimiters', () {
        final document = MutableDocument(nodes: [
          ParagraphNode(id: 'p1', text: AttributedText('_italic')),
        ]);
        final editor = _createEditor(document);

        _typeChar(editor, 'p1', 7, '_');

        final para = document.getNodeById('p1') as ParagraphNode;
        expect(para.text.toPlainText(), 'italic');
        final attributions =
            para.text.getAllAttributionsThroughout(SpanRange(0, 5));
        expect(attributions, contains(italicsAttribution));
      });

      test('italic with surrounding text', () {
        final document = MutableDocument(nodes: [
          ParagraphNode(id: 'p1', text: AttributedText('Say _hi')),
        ]);
        final editor = _createEditor(document);

        _typeChar(editor, 'p1', 7, '_');

        final para = document.getNodeById('p1') as ParagraphNode;
        expect(para.text.toPlainText(), 'Say hi');
        // 'hi' at offset 4, length 2 → span [4, 5]
        final attributions =
            para.text.getAllAttributionsThroughout(SpanRange(4, 5));
        expect(attributions, contains(italicsAttribution));
      });
    });

    group('inline code (`text`)', () {
      test('typing closing ` applies code and strips delimiters', () {
        final document = MutableDocument(nodes: [
          ParagraphNode(id: 'p1', text: AttributedText('`code')),
        ]);
        final editor = _createEditor(document);

        _typeChar(editor, 'p1', 5, '`');

        final para = document.getNodeById('p1') as ParagraphNode;
        expect(para.text.toPlainText(), 'code');
        final attributions =
            para.text.getAllAttributionsThroughout(SpanRange(0, 3));
        expect(attributions, contains(codeAttribution));
      });

      test('code with surrounding text', () {
        final document = MutableDocument(nodes: [
          ParagraphNode(id: 'p1', text: AttributedText('Use `foo')),
        ]);
        final editor = _createEditor(document);

        _typeChar(editor, 'p1', 8, '`');

        final para = document.getNodeById('p1') as ParagraphNode;
        expect(para.text.toPlainText(), 'Use foo');
        // 'foo' at offset 4, length 3 → span [4, 6]
        final attributions =
            para.text.getAllAttributionsThroughout(SpanRange(4, 6));
        expect(attributions, contains(codeAttribution));
      });
    });

    group('task list (- [ ] )', () {
      test('typing final space after [ ] in a list item converts to TaskNode',
          () {
        // UnorderedListItemConversionReaction fires on '- ' first, converting
        // the paragraph to a ListItemNode and stripping the '- ' prefix.
        // Our reaction watches for content '[ ] ' inside that ListItemNode.
        // Pre-state: user has typed '- [ ]' → list item holds '[ ]'.
        final document = MutableDocument(nodes: [
          ListItemNode.unordered(id: 'p1', text: AttributedText('[ ]')),
        ]);
        final editor = _createEditor(document);

        // Type the final space — node content becomes '[ ] ', reaction fires.
        _typeChar(editor, 'p1', 3, ' ');

        final node = document.getNodeById('p1');
        expect(node, isA<TaskNode>());
        expect((node as TaskNode).isComplete, isFalse);
        expect(node.text.toPlainText(), isEmpty);
      });
    });

    group('existing round-trip tests still pass', () {
      test('bold round-trips through serialize/deserialize', () {
        final doc = deserializeMarkdownToDocument(
          'Some **bold** text',
          syntax: MarkdownSyntax.normal,
        );
        final result =
            serializeDocumentToMarkdown(doc, syntax: MarkdownSyntax.normal)
                .trim();
        expect(result, 'Some **bold** text');
      });
    });
  });
}
