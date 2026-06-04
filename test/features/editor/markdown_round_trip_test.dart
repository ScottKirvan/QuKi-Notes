import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

// Round-trip tests for the markdown serialization fix.
//
// Before the fix, _parseBody split on \n\n and created plain ParagraphNodes,
// stripping all formatting. _extractBody called toPlainText(), losing inline
// attributions. These tests verify that formatting survives a
// deserialize → serialize cycle using the super_editor functions now wired
// into EditorScreen.
void main() {
  group('markdown round-trip (deserialize → serialize)', () {
    String roundTrip(String md) {
      final doc = deserializeMarkdownToDocument(
        md,
        syntax: MarkdownSyntax.normal,
      );
      return serializeDocumentToMarkdown(
        doc,
        syntax: MarkdownSyntax.normal,
      ).trim();
    }

    test('plain paragraph preserved', () {
      expect(roundTrip('Hello world'), 'Hello world');
    });

    test('multiple paragraphs preserved', () {
      expect(roundTrip('First\n\nSecond'), 'First\n\nSecond');
    });

    test('heading H1 preserved', () {
      expect(roundTrip('# My heading'), '# My heading');
    });

    test('heading H2 preserved', () {
      expect(roundTrip('## Sub heading'), '## Sub heading');
    });

    test('bold inline preserved', () {
      expect(roundTrip('Some **bold** text'), 'Some **bold** text');
    });

    test('italic inline preserved', () {
      expect(roundTrip('Some _italic_ text'), 'Some _italic_ text');
    });

    test('unordered list preserved', () {
      expect(roundTrip('- Item one\n- Item two'), '- Item one\n- Item two');
    });

    test('ordered list preserved', () {
      expect(roundTrip('1. First\n1. Second'), '1. First\n1. Second');
    });

    test('mixed heading and paragraph preserved', () {
      const md = '# Title\n\nSome body text.';
      expect(roundTrip(md), md);
    });

    test('bold in heading preserved', () {
      expect(roundTrip('# **Bold** heading'), '# **Bold** heading');
    });

    test('empty string returns empty', () {
      expect(roundTrip(''), '');
    });

    test('whitespace-only body treated as empty', () {
      final doc = deserializeMarkdownToDocument(
        '   ',
        syntax: MarkdownSyntax.normal,
      );
      final result = serializeDocumentToMarkdown(
        doc,
        syntax: MarkdownSyntax.normal,
      ).trim();
      expect(result, '');
    });
  });
}
