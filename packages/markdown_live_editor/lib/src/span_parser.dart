import 'package:flutter/material.dart';

/// Converts a single line of markdown text into a list of [InlineSpan]s
/// suitable for use in a [TextSpan] tree returned by
/// [TextEditingController.buildTextSpan].
///
/// The parser operates in one of two modes per line:
///
/// - **Cursor line**: the line the user is currently editing. Syntax characters
///   are rendered in [syntaxColor] (visible but muted); content is rendered in
///   the base [textStyle]. No block or inline transformations are applied — the
///   user sees exactly what they are typing.
///
/// - **Non-cursor lines**: block-level transforms (headings, lists) are applied;
///   syntax prefix characters are hidden via [Colors.transparent]; inline
///   spans (bold, italic, code, strikethrough) are parsed and styled.
///
/// Character count invariant: the total number of characters in the returned
/// spans always equals [line].length. Hiding is done by setting
/// [TextStyle.color] to [Colors.transparent] — the characters remain in the
/// buffer and are navigable by the cursor.
class MarkdownSpanParser {
  const MarkdownSpanParser({
    required this.textStyle,
    required this.syntaxColor,
    required this.headingStyle,
    required this.boldStyle,
    required this.italicStyle,
    required this.codeStyle,
    required this.strikethroughStyle,
    required this.listPrefixStyle,
    required this.checkboxStyle,
  });

  final TextStyle textStyle;

  /// Color for syntax characters on the cursor line (visible but muted).
  final Color syntaxColor;

  final TextStyle headingStyle;
  final TextStyle boldStyle;
  final TextStyle italicStyle;
  final TextStyle codeStyle;
  final TextStyle strikethroughStyle;
  final TextStyle listPrefixStyle;

  /// Style for checkbox markers `[ ]` / `[x]` on non-cursor lines.
  final TextStyle checkboxStyle;

  static final _h1Re = RegExp(r'^(# )(.*)$');
  static final _h2Re = RegExp(r'^(## )(.*)$');
  static final _h3Re = RegExp(r'^(### )(.*)$');
  static final _taskUncheckedRe = RegExp(r'^(- \[ \] )(.*)$');
  static final _taskCheckedRe = RegExp(r'^(- \[x\] )(.*)$', caseSensitive: false);
  static final _unorderedRe = RegExp(r'^([-*] )(.*)$');
  static final _orderedRe = RegExp(r'^(\d+\. )(.*)$');
  static final _blockquoteRe = RegExp(r'^(> )');
  static final _codeFenceRe = RegExp(r'^```');

  /// Parse [line] into a list of [InlineSpan]s.
  ///
  /// [isCursorLine] — true when the cursor is on this line.
  List<InlineSpan> parseLine(String line, {required bool isCursorLine}) {
    if (isCursorLine) {
      return _parseCursorLine(line);
    }
    return _parseRenderedLine(line);
  }

  // ---------------------------------------------------------------------------
  // Cursor-line rendering: syntax chars visible in syntaxColor, content normal.
  // ---------------------------------------------------------------------------

  List<InlineSpan> _parseCursorLine(String line) {
    if (line.isEmpty) {
      return [TextSpan(text: '', style: textStyle)];
    }

    final syntaxStyle = textStyle.copyWith(color: syntaxColor);

    // Heading lines: dim the prefix, normal content.
    for (final re in [_h3Re, _h2Re, _h1Re]) {
      final m = re.firstMatch(line);
      if (m != null) {
        return [
          TextSpan(text: m.group(1), style: syntaxStyle),
          TextSpan(text: m.group(2), style: textStyle),
        ];
      }
    }

    // Task list (unchecked).
    final taskU = _taskUncheckedRe.firstMatch(line);
    if (taskU != null) {
      return [
        TextSpan(text: taskU.group(1), style: syntaxStyle),
        TextSpan(text: taskU.group(2), style: textStyle),
      ];
    }

    // Task list (checked).
    final taskC = _taskCheckedRe.firstMatch(line);
    if (taskC != null) {
      return [
        TextSpan(text: taskC.group(1), style: syntaxStyle),
        TextSpan(text: taskC.group(2), style: textStyle),
      ];
    }

    // Unordered list.
    final unordered = _unorderedRe.firstMatch(line);
    if (unordered != null) {
      return [
        TextSpan(text: unordered.group(1), style: syntaxStyle),
        TextSpan(text: unordered.group(2), style: textStyle),
      ];
    }

    // Ordered list.
    final ordered = _orderedRe.firstMatch(line);
    if (ordered != null) {
      return [
        TextSpan(text: ordered.group(1), style: syntaxStyle),
        TextSpan(text: ordered.group(2), style: textStyle),
      ];
    }

    // Blockquote or code fence: show raw with syntax prefix dimmed.
    if (_blockquoteRe.hasMatch(line)) {
      return [
        TextSpan(text: '> ', style: syntaxStyle),
        TextSpan(text: line.substring(2), style: textStyle),
      ];
    }
    if (_codeFenceRe.hasMatch(line)) {
      return [TextSpan(text: line, style: syntaxStyle)];
    }

    // Plain paragraph: show raw with inline delimiters dimmed.
    return _parseCursorLineParagraph(line);
  }

  List<InlineSpan> _parseCursorLineParagraph(String line) {
    final syntaxStyle = textStyle.copyWith(color: syntaxColor);
    final spans = <InlineSpan>[];
    int i = 0;

    while (i < line.length) {
      // Bold (**) or (__)
      if (i + 1 < line.length &&
          ((line[i] == '*' && line[i + 1] == '*') ||
              (line[i] == '_' && line[i + 1] == '_'))) {
        final delim = line.substring(i, i + 2);
        final closeIdx = line.indexOf(delim, i + 2);
        if (closeIdx != -1) {
          spans.add(TextSpan(text: delim, style: syntaxStyle));
          spans.add(
              TextSpan(text: line.substring(i + 2, closeIdx), style: textStyle));
          spans.add(TextSpan(text: delim, style: syntaxStyle));
          i = closeIdx + 2;
          continue;
        }
      }

      // Strikethrough (~~)
      if (i + 1 < line.length && line[i] == '~' && line[i + 1] == '~') {
        final closeIdx = line.indexOf('~~', i + 2);
        if (closeIdx != -1) {
          spans.add(TextSpan(text: '~~', style: syntaxStyle));
          spans.add(
              TextSpan(text: line.substring(i + 2, closeIdx), style: textStyle));
          spans.add(TextSpan(text: '~~', style: syntaxStyle));
          i = closeIdx + 2;
          continue;
        }
      }

      // Italic (*) or (_) — single char, not preceded by same char
      if (line[i] == '*' || line[i] == '_') {
        final char = line[i];
        final closeIdx = line.indexOf(char, i + 1);
        if (closeIdx != -1) {
          spans.add(TextSpan(text: char, style: syntaxStyle));
          spans.add(TextSpan(
              text: line.substring(i + 1, closeIdx), style: textStyle));
          spans.add(TextSpan(text: char, style: syntaxStyle));
          i = closeIdx + 1;
          continue;
        }
      }

      // Inline code (`)
      if (line[i] == '`') {
        final closeIdx = line.indexOf('`', i + 1);
        if (closeIdx != -1) {
          spans.add(TextSpan(text: '`', style: syntaxStyle));
          spans.add(TextSpan(
              text: line.substring(i + 1, closeIdx), style: textStyle));
          spans.add(TextSpan(text: '`', style: syntaxStyle));
          i = closeIdx + 1;
          continue;
        }
      }

      // Regular character — accumulate into a run.
      int j = i + 1;
      while (j < line.length) {
        final c = line[j];
        if (c == '*' || c == '_' || c == '~' || c == '`') break;
        j++;
      }
      spans.add(TextSpan(text: line.substring(i, j), style: textStyle));
      i = j;
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: '', style: textStyle));
    }
    return spans;
  }

  // ---------------------------------------------------------------------------
  // Non-cursor (rendered) line: apply block + inline transforms.
  // ---------------------------------------------------------------------------

  List<InlineSpan> _parseRenderedLine(String line) {
    if (line.isEmpty) {
      return [TextSpan(text: '', style: textStyle)];
    }

    final transparent = textStyle.copyWith(color: Colors.transparent);

    // Headings — check longest prefix first to avoid h1 stealing h2/h3.
    final h3 = _h3Re.firstMatch(line);
    if (h3 != null) {
      return [
        TextSpan(text: h3.group(1), style: transparent),
        ..._parseInline(h3.group(2)!, baseStyle: headingStyle),
      ];
    }
    final h2 = _h2Re.firstMatch(line);
    if (h2 != null) {
      return [
        TextSpan(text: h2.group(1), style: transparent),
        ..._parseInline(h2.group(2)!, baseStyle: headingStyle),
      ];
    }
    final h1 = _h1Re.firstMatch(line);
    if (h1 != null) {
      return [
        TextSpan(text: h1.group(1), style: transparent),
        ..._parseInline(h1.group(2)!, baseStyle: headingStyle),
      ];
    }

    // Task list (unchecked): `- [ ] content`
    final taskU = _taskUncheckedRe.firstMatch(line);
    if (taskU != null) {
      // "- " transparent, "[ ] " in checkboxStyle, content normal.
      // prefix is "- [ ] " (6 chars). Split: "- " (2) + "[ ] " (4).
      final dashSpace = line.substring(0, 2);
      final bracket = line.substring(2, 6);
      final content = taskU.group(2)!;
      return [
        TextSpan(text: dashSpace, style: transparent),
        TextSpan(text: bracket, style: checkboxStyle),
        ..._parseInline(content, baseStyle: textStyle),
      ];
    }

    // Task list (checked): `- [x] content`
    final taskC = _taskCheckedRe.firstMatch(line);
    if (taskC != null) {
      final dashSpace = line.substring(0, 2);
      final bracket = line.substring(2, 6);
      final content = taskC.group(2)!;
      return [
        TextSpan(text: dashSpace, style: transparent),
        TextSpan(
            text: bracket,
            style: checkboxStyle.copyWith(
                decoration: TextDecoration.lineThrough)),
        ..._parseInline(content,
            baseStyle: textStyle.copyWith(
                decoration: TextDecoration.lineThrough,
                color: textStyle.color?.withValues(alpha: 0.5))),
      ];
    }

    // Unordered list
    final unordered = _unorderedRe.firstMatch(line);
    if (unordered != null) {
      return [
        TextSpan(text: unordered.group(1), style: transparent),
        ..._parseInline(unordered.group(2)!, baseStyle: textStyle),
      ];
    }

    // Ordered list
    final ordered = _orderedRe.firstMatch(line);
    if (ordered != null) {
      return [
        TextSpan(text: ordered.group(1), style: transparent),
        ..._parseInline(ordered.group(2)!, baseStyle: textStyle),
      ];
    }

    // Blockquote: v1 — show raw.
    if (_blockquoteRe.hasMatch(line)) {
      return [TextSpan(text: line, style: textStyle)];
    }

    // Code fence: v1 — show raw in monospace.
    if (_codeFenceRe.hasMatch(line)) {
      return [TextSpan(text: line, style: codeStyle)];
    }

    // Paragraph
    return _parseInline(line, baseStyle: textStyle);
  }

  // ---------------------------------------------------------------------------
  // Inline span parser — used on non-cursor lines for paragraphs and
  // the content portion of headings/lists.
  //
  // Patterns may not nest in v1. left-to-right scan, first match wins.
  // ---------------------------------------------------------------------------

  List<InlineSpan> _parseInline(String text, {required TextStyle baseStyle}) {
    if (text.isEmpty) return [TextSpan(text: '', style: baseStyle)];

    final transparent = baseStyle.copyWith(color: Colors.transparent);
    final spans = <InlineSpan>[];
    int i = 0;

    while (i < text.length) {
      // Bold: **text** or __text__
      if (i + 1 < text.length &&
          ((text[i] == '*' && text[i + 1] == '*') ||
              (text[i] == '_' && text[i + 1] == '_'))) {
        final delim = text.substring(i, i + 2);
        final closeIdx = text.indexOf(delim, i + 2);
        if (closeIdx != -1) {
          spans.add(TextSpan(text: delim, style: transparent));
          spans.add(TextSpan(
              text: text.substring(i + 2, closeIdx),
              style: boldStyle.copyWith(
                  color: baseStyle.color,
                  fontSize: baseStyle.fontSize,
                  height: baseStyle.height)));
          spans.add(TextSpan(text: delim, style: transparent));
          i = closeIdx + 2;
          continue;
        }
      }

      // Strikethrough: ~~text~~
      if (i + 1 < text.length && text[i] == '~' && text[i + 1] == '~') {
        final closeIdx = text.indexOf('~~', i + 2);
        if (closeIdx != -1) {
          spans.add(TextSpan(text: '~~', style: transparent));
          spans.add(TextSpan(
              text: text.substring(i + 2, closeIdx),
              style: strikethroughStyle.copyWith(
                  color: baseStyle.color,
                  fontSize: baseStyle.fontSize,
                  height: baseStyle.height)));
          spans.add(TextSpan(text: '~~', style: transparent));
          i = closeIdx + 2;
          continue;
        }
      }

      // Italic: *text* or _text_ (single delimiter)
      if (text[i] == '*' || text[i] == '_') {
        final char = text[i];
        // Only treat as italic if it's not a double-delimiter (already handled).
        final closeIdx = text.indexOf(char, i + 1);
        if (closeIdx != -1) {
          spans.add(TextSpan(text: char, style: transparent));
          spans.add(TextSpan(
              text: text.substring(i + 1, closeIdx),
              style: italicStyle.copyWith(
                  color: baseStyle.color,
                  fontSize: baseStyle.fontSize,
                  height: baseStyle.height)));
          spans.add(TextSpan(text: char, style: transparent));
          i = closeIdx + 1;
          continue;
        }
      }

      // Inline code: `code`
      if (text[i] == '`') {
        final closeIdx = text.indexOf('`', i + 1);
        if (closeIdx != -1) {
          spans.add(TextSpan(text: '`', style: transparent));
          spans.add(TextSpan(
              text: text.substring(i + 1, closeIdx),
              style: codeStyle.copyWith(
                  fontSize: baseStyle.fontSize,
                  height: baseStyle.height)));
          spans.add(TextSpan(text: '`', style: transparent));
          i = closeIdx + 1;
          continue;
        }
      }

      // Link [text](url) and image ![alt](url): v1 — show raw.
      // Both are left as plain text (fall through to accumulator below).

      // Accumulate regular characters into a run.
      int j = i + 1;
      while (j < text.length) {
        final c = text[j];
        if (c == '*' || c == '_' || c == '~' || c == '`') break;
        j++;
      }
      spans.add(TextSpan(text: text.substring(i, j), style: baseStyle));
      i = j;
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: '', style: baseStyle));
    }
    return spans;
  }
}
