import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

// Helpers to extract text and color from a flat list of InlineSpans.
String _spanText(List<InlineSpan> spans) =>
    spans.map((s) => (s as TextSpan).toPlainText()).join();

Color? _colorAt(List<InlineSpan> spans, int index) =>
    (spans[index] as TextSpan).style?.color;

bool _isTransparent(Color? color) => color == Colors.transparent;

MarkdownSpanParser _makeParser({Color? syntaxColor}) {
  const base = TextStyle(fontSize: 16, color: Colors.black);
  return MarkdownSpanParser(
    textStyle: base,
    syntaxColor: syntaxColor ?? Colors.grey,
    headingStyle: base.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
    boldStyle: base.copyWith(fontWeight: FontWeight.bold),
    italicStyle: base.copyWith(fontStyle: FontStyle.italic),
    codeStyle: base.copyWith(fontFamily: 'monospace'),
    strikethroughStyle: base.copyWith(decoration: TextDecoration.lineThrough),
    listPrefixStyle: base,
    checkboxStyle: base.copyWith(fontFamily: 'monospace', color: Colors.black),
  );
}

void main() {
  final parser = _makeParser();

  group('MarkdownSpanParser — non-cursor heading lines', () {
    test('h1 prefix is transparent on non-cursor line', () {
      final spans = parser.parseLine('# Hello', isCursorLine: false);
      // First span is the "# " prefix.
      expect(_isTransparent(_colorAt(spans, 0)), isTrue);
    });

    test('h1 content is in heading style on non-cursor line', () {
      final spans = parser.parseLine('# Hello', isCursorLine: false);
      final contentSpan = spans[1] as TextSpan;
      expect(contentSpan.style?.fontWeight, FontWeight.bold);
    });

    test('h2 prefix is transparent on non-cursor line', () {
      final spans = parser.parseLine('## World', isCursorLine: false);
      expect(_isTransparent(_colorAt(spans, 0)), isTrue);
    });

    test('h3 prefix is transparent on non-cursor line', () {
      final spans = parser.parseLine('### Title', isCursorLine: false);
      expect(_isTransparent(_colorAt(spans, 0)), isTrue);
    });

    test('total character count equals line length — heading', () {
      const line = '# My Heading';
      final spans = parser.parseLine(line, isCursorLine: false);
      expect(_spanText(spans).length, line.length);
    });
  });

  group('MarkdownSpanParser — non-cursor list lines', () {
    test(
        'unordered list "- item": first span text is "• " (bullet) — regression: list bullet invisible',
        () {
      final spans = parser.parseLine('- item', isCursorLine: false);
      final firstSpan = spans[0] as TextSpan;
      expect(firstSpan.toPlainText(), '• ',
          reason: '"- " should be replaced by "• " in rendered mode');
    });

    test(
        'unordered list "- item": first span is in listPrefixStyle — regression: list bullet invisible',
        () {
      // listPrefixStyle in _makeParser is `base` (Colors.black, no special attrs).
      final spans = parser.parseLine('- item', isCursorLine: false);
      final firstSpan = spans[0] as TextSpan;
      // Must NOT be transparent.
      expect(_isTransparent(firstSpan.style?.color), isFalse,
          reason: 'bullet span must not be transparent');
    });

    test(
        'unordered list "* item": first span text is "• " — regression: list bullet invisible',
        () {
      final spans = parser.parseLine('* item', isCursorLine: false);
      final firstSpan = spans[0] as TextSpan;
      expect(firstSpan.toPlainText(), '• ');
    });

    test('unordered list content is in normal style', () {
      final spans = parser.parseLine('- item', isCursorLine: false);
      final contentSpan = spans[1] as TextSpan;
      expect(contentSpan.style?.color, Colors.black);
    });

    test(
        'ordered list prefix "1. " is visible in listPrefixStyle — regression: list prefix transparent',
        () {
      final spans = parser.parseLine('1. first', isCursorLine: false);
      final firstSpan = spans[0] as TextSpan;
      expect(_isTransparent(firstSpan.style?.color), isFalse,
          reason: 'ordered list prefix must not be transparent');
    });

    test('ordered list prefix text is preserved', () {
      final spans = parser.parseLine('1. first', isCursorLine: false);
      final firstSpan = spans[0] as TextSpan;
      expect(firstSpan.toPlainText(), '1. ');
    });

    test(
        'cursor line "- item": first span text is "- " (raw syntax, not bullet)',
        () {
      final spans = parser.parseLine('- item', isCursorLine: true);
      final firstSpan = spans[0] as TextSpan;
      expect(firstSpan.toPlainText(), '- ',
          reason: 'cursor line shows raw syntax, not the rendered bullet');
    });

    test('total character count equals line length — unordered list', () {
      const line = '- list item text';
      final spans = parser.parseLine(line, isCursorLine: false);
      expect(_spanText(spans).length, line.length);
    });

    test('total character count equals line length — ordered list', () {
      const line = '1. list item text';
      final spans = parser.parseLine(line, isCursorLine: false);
      expect(_spanText(spans).length, line.length);
    });
  });

  group('MarkdownSpanParser — non-cursor inline spans', () {
    test('bold delimiters are transparent, content is bold', () {
      final spans = parser.parseLine('**bold**', isCursorLine: false);
      // spans: [** transparent], [bold bold], [** transparent]
      expect(spans.length, 3);
      expect(_isTransparent(_colorAt(spans, 0)), isTrue);
      final bold = spans[1] as TextSpan;
      expect(bold.style?.fontWeight, FontWeight.bold);
      expect(_isTransparent(_colorAt(spans, 2)), isTrue);
    });

    test('italic delimiters are transparent, content is italic', () {
      final spans = parser.parseLine('_italic_', isCursorLine: false);
      expect(spans.length, 3);
      expect(_isTransparent(_colorAt(spans, 0)), isTrue);
      final italic = spans[1] as TextSpan;
      expect(italic.style?.fontStyle, FontStyle.italic);
      expect(_isTransparent(_colorAt(spans, 2)), isTrue);
    });

    test('inline code backticks are transparent, content is monospace', () {
      final spans = parser.parseLine('`code`', isCursorLine: false);
      expect(spans.length, 3);
      expect(_isTransparent(_colorAt(spans, 0)), isTrue);
      final code = spans[1] as TextSpan;
      expect(code.style?.fontFamily, 'monospace');
      expect(_isTransparent(_colorAt(spans, 2)), isTrue);
    });

    test('strikethrough delimiters are transparent, content has lineThrough',
        () {
      final spans = parser.parseLine('~~strike~~', isCursorLine: false);
      expect(spans.length, 3);
      expect(_isTransparent(_colorAt(spans, 0)), isTrue);
      final strike = spans[1] as TextSpan;
      expect(strike.style?.decoration, TextDecoration.lineThrough);
      expect(_isTransparent(_colorAt(spans, 2)), isTrue);
    });

    test('total character count equals line length — inline bold', () {
      const line = 'hello **world** end';
      final spans = parser.parseLine(line, isCursorLine: false);
      expect(_spanText(spans).length, line.length);
    });

    test('total character count equals line length — mixed inline', () {
      const line = '**bold** and _italic_ and `code`';
      final spans = parser.parseLine(line, isCursorLine: false);
      expect(_spanText(spans).length, line.length);
    });
  });

  group('MarkdownSpanParser — cursor line', () {
    test(
        'cursor line returns text in syntax color for prefix, normal for content',
        () {
      const syntaxC = Color(0xFF888888);
      final p = _makeParser(syntaxColor: syntaxC);
      final spans = p.parseLine('# Heading', isCursorLine: true);
      // First span "# " should be in syntaxColor.
      expect(_colorAt(spans, 0), syntaxC);
      // Second span "Heading" should be normal (black).
      expect(_colorAt(spans, 1), Colors.black);
    });

    test('cursor line total character count equals line length — heading', () {
      const line = '# Heading text';
      final spans = parser.parseLine(line, isCursorLine: true);
      expect(_spanText(spans).length, line.length);
    });

    test('cursor line total character count equals line length — paragraph',
        () {
      const line = 'Hello **world** with _italic_';
      final spans = parser.parseLine(line, isCursorLine: true);
      expect(_spanText(spans).length, line.length);
    });

    test('cursor line: bold markers shown in syntaxColor, not hidden', () {
      const syntaxC = Color(0xFF888888);
      final p = _makeParser(syntaxColor: syntaxC);
      final spans = p.parseLine('**bold**', isCursorLine: true);
      // On cursor line, ** is shown dimmed (syntaxColor), not transparent.
      final allColors = spans.map((s) => (s as TextSpan).style?.color).toList();
      expect(allColors.any((c) => c == Colors.transparent), isFalse,
          reason: 'cursor line should not hide any chars with transparent');
    });
  });

  group('MarkdownSpanParser — edge cases', () {
    test('empty line does not crash', () {
      final spans = parser.parseLine('', isCursorLine: false);
      expect(spans, isNotEmpty);
      expect(_spanText(spans), '');
    });

    test('empty line on cursor does not crash', () {
      final spans = parser.parseLine('', isCursorLine: true);
      expect(spans, isNotEmpty);
    });

    test('line with only heading marker "# " does not crash', () {
      final spans = parser.parseLine('# ', isCursorLine: false);
      expect(spans, isNotEmpty);
      expect(_spanText(spans).length, 2);
    });

    test('line with only list marker "- " does not crash', () {
      final spans = parser.parseLine('- ', isCursorLine: false);
      expect(spans, isNotEmpty);
      expect(_spanText(spans).length, 2);
    });

    test('plain paragraph with no syntax passes through unchanged', () {
      const line = 'Just plain text here.';
      final spans = parser.parseLine(line, isCursorLine: false);
      expect(_spanText(spans), line);
    });

    test('unclosed bold delimiter passes through as literal text', () {
      const line = '**not closed';
      final spans = parser.parseLine(line, isCursorLine: false);
      // No crash; full text preserved.
      expect(_spanText(spans).length, line.length);
    });

    test(
        'task unchecked prefix "- [ ] " on non-cursor: dash transparent, brackets in checkboxStyle',
        () {
      final spans = parser.parseLine('- [ ] task', isCursorLine: false);
      // First span: "- " transparent
      expect(_isTransparent(_colorAt(spans, 0)), isTrue);
      // Second span: "[ ] " in checkboxStyle
      final bracket = spans[1] as TextSpan;
      expect(bracket.style?.fontFamily, 'monospace');
    });

    test(
        'checkbox bracket "[ ] " is NOT transparent — regression: checkbox nearly invisible',
        () {
      // checkboxStyle must use baseColor (full opacity), not syntaxColor (35%).
      final spans = parser.parseLine('- [ ] task', isCursorLine: false);
      // Second span: "[ ] " bracket
      expect(_isTransparent(_colorAt(spans, 1)), isFalse,
          reason: 'checkbox brackets must not be transparent');
      // Color should be full-opacity black (baseColor from _makeParser).
      expect(_colorAt(spans, 1), Colors.black,
          reason: 'checkboxStyle must use baseColor at full opacity');
    });

    test(
        'checkbox bracket "[x] " is NOT transparent — regression: checkbox nearly invisible',
        () {
      final spans = parser.parseLine('- [x] done', isCursorLine: false);
      expect(_isTransparent(_colorAt(spans, 1)), isFalse,
          reason: 'checked checkbox brackets must not be transparent');
    });

    test('task checked "- [x] " renders without crash', () {
      final spans = parser.parseLine('- [x] done', isCursorLine: false);
      expect(spans, isNotEmpty);
      expect(_spanText(spans).length, '- [x] done'.length);
    });
  });

  group('MarkdownSpanParser — character count invariant', () {
    final testLines = [
      '',
      '# ',
      '- ',
      '* ',
      '1. ',
      '> blockquote',
      '```code fence',
      'plain text',
      '**bold**',
      '_italic_',
      '`code`',
      '~~strike~~',
      '# Heading **with bold**',
      '- list with _italic_',
      '* list with **bold**',
      '1. ordered with _italic_',
      '- [ ] task item',
      '- [x] done item',
    ];

    for (final line in testLines) {
      test('char count preserved: "${line.replaceAll('\n', '\\n')}"', () {
        final nonCursor = parser.parseLine(line, isCursorLine: false);
        expect(
          _spanText(nonCursor).length,
          line.length,
          reason: 'non-cursor: char count mismatch for "$line"',
        );
        final cursor = parser.parseLine(line, isCursorLine: true);
        expect(
          _spanText(cursor).length,
          line.length,
          reason: 'cursor: char count mismatch for "$line"',
        );
      });
    }
  });
}
