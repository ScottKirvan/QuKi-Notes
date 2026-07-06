// ---------------------------------------------------------------------------
// Markdown element kinds supported through Stage 4.
// ---------------------------------------------------------------------------

enum MdElKind {
  h1,
  h2,
  h3,
  bold,
  italic,
  ul,
  ol,
  checkboxUnchecked,
  checkboxChecked
}

// ---------------------------------------------------------------------------
// MdElement — a parsed markdown element anchored to source offsets.
// ---------------------------------------------------------------------------

class MdElement {
  const MdElement({
    required this.kind,
    required this.start,
    required this.end,
    this.seqNum = 0,
    int srcOlDelimLen = 0,
  }) : _srcOlDelimLen = srcOlDelimLen;

  /// Kind of markdown element.
  final MdElKind kind;

  /// Source offset of the first character of this element (inclusive).
  final int start;

  /// Source offset just past the last character of this element (exclusive).
  final int end;

  /// For [MdElKind.ol]: the sequence number as written in the source
  /// (e.g. '5. item' → seqNum = 5). For all other kinds this is 0 and
  /// should not be read.
  final int seqNum;

  /// For [MdElKind.ol]: the number of source characters in the marker
  /// (e.g. '1. ' = 3, '12. ' = 4). Stored separately because the source
  /// digits may differ from [seqNum].
  final int _srcOlDelimLen;

  /// True if [offset] falls within this element's source range.
  bool containsOffset(int offset) => offset >= start && offset < end;

  /// Length of the opening delimiter in source characters.
  int get openDelimLen => switch (kind) {
        MdElKind.h1 => 2, // '# '
        MdElKind.h2 => 3, // '## '
        MdElKind.h3 => 4, // '### '
        MdElKind.bold => 2, // '**' or '__'
        MdElKind.italic => 1, // '*' or '_'
        MdElKind.ul => 2, // '- ' / '* ' / '+ '
        MdElKind.ol => _srcOlDelimLen, // '{digits}. ' — variable
        MdElKind.checkboxUnchecked => 6, // '- [ ] '
        MdElKind.checkboxChecked => 6, // '- [x] ' or '- [X] '
      };

  /// Length of the closing delimiter (0 for block-level elements).
  int get closeDelimLen => switch (kind) {
        MdElKind.h1 ||
        MdElKind.h2 ||
        MdElKind.h3 ||
        MdElKind.ul ||
        MdElKind.ol ||
        MdElKind.checkboxUnchecked ||
        MdElKind.checkboxChecked =>
          0,
        MdElKind.bold => 2,
        MdElKind.italic => 1,
      };

  /// The string that replaces the source marker in collapsed (rendered) mode.
  ///
  /// For inline elements (bold, italic) and headings, the marker is simply
  /// hidden (delimiter chars omitted), so [collapsedMarker] returns the empty
  /// string — the render model handles those by skipping delimiter source
  /// characters rather than emitting a substitution glyph.
  ///
  /// For block list elements, this returns the visual glyph + space.
  String get collapsedMarker => switch (kind) {
        MdElKind.ul => '• ',
        MdElKind.checkboxUnchecked => '☐ ',
        MdElKind.checkboxChecked => '☑ ',
        MdElKind.ol => '$seqNum. ',
        // Heading and inline elements: no substitution glyph.
        _ => '',
      };

  /// Whether source offset [si] (which must be within [start, end)) is a
  /// delimiter character.
  bool isDelimiter(int si) {
    if (si < start || si >= end) return false;
    if (si < start + openDelimLen) return true;
    if (closeDelimLen > 0 && si >= end - closeDelimLen) return true;
    return false;
  }
}

// ---------------------------------------------------------------------------
// MdParser — walks source string and produces a flat list of MdElements.
// ---------------------------------------------------------------------------

class MdParser {
  MdParser._();

  /// Parse [source] and return a flat, sorted list of [MdElement]s.
  ///
  /// The list is naturally sorted by [MdElement.start] because the scan
  /// proceeds left-to-right, top-to-bottom.
  static List<MdElement> parse(String source) {
    if (source.isEmpty) return const [];

    final result = <MdElement>[];
    final lines = source.split('\n');
    var lineStart = 0;

    for (final line in lines) {
      final lineEnd = lineStart + line.length; // exclusive, excluding '\n'

      // Step 1 — Heading check (longest prefix first).
      if (line.startsWith('### ')) {
        result
            .add(MdElement(kind: MdElKind.h3, start: lineStart, end: lineEnd));
      } else if (line.startsWith('## ')) {
        result
            .add(MdElement(kind: MdElKind.h2, start: lineStart, end: lineEnd));
      } else if (line.startsWith('# ')) {
        result
            .add(MdElement(kind: MdElKind.h1, start: lineStart, end: lineEnd));

        // Step 2 — Checkbox detection (must run before ul, both start with '- ').
      } else if (line.startsWith('- [ ] ')) {
        result.add(MdElement(
          kind: MdElKind.checkboxUnchecked,
          start: lineStart,
          end: lineEnd,
        ));
      } else if (line.startsWith('- [x] ') || line.startsWith('- [X] ')) {
        result.add(MdElement(
          kind: MdElKind.checkboxChecked,
          start: lineStart,
          end: lineEnd,
        ));

        // Step 3 — Unordered list ('- ', '* ', '+ ').
      } else if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          line.startsWith('+ ')) {
        result
            .add(MdElement(kind: MdElKind.ul, start: lineStart, end: lineEnd));

        // Step 4 — Ordered list ('{digits}. ').
        // seqNum is the actual source digit, not a position-computed counter.
        // This preserves open-data fidelity: '5. item' renders as '5. item'.
      } else if (_isOlLine(line)) {
        final dotIdx = line.indexOf('. ');
        final srcDelimLen = dotIdx + 2; // digits + '. '
        final srcDigit = int.parse(line.substring(0, dotIdx));
        result.add(MdElement(
          kind: MdElKind.ol,
          start: lineStart,
          end: lineEnd,
          seqNum: srcDigit,
          srcOlDelimLen: srcDelimLen,
        ));
      } else {
        // Step 5 — Inline scan (non-list, non-heading lines only).
        var i = lineStart;
        while (i < lineEnd) {
          // Check bold: '**' or '__'
          if (i + 1 < lineEnd) {
            final c0 = source[i];
            final c1 = source[i + 1];
            if ((c0 == '*' && c1 == '*') || (c0 == '_' && c1 == '_')) {
              final closeStart = i + 2;
              final closeIdx = _findClose(source, closeStart, lineEnd, c0 + c1);
              if (closeIdx != -1 && closeIdx > closeStart) {
                result.add(MdElement(
                  kind: MdElKind.bold,
                  start: i,
                  end: closeIdx + 2,
                ));
                i = closeIdx + 2;
                continue;
              }
            }
          }

          // Check italic: '*' or '_' (single char, not followed by same char)
          {
            final c0 = source[i];
            if (c0 == '*' || c0 == '_') {
              // Must not be the start of a bold sequence (next char is NOT same).
              final nextIsSame = i + 1 < lineEnd && source[i + 1] == c0;
              if (!nextIsSame) {
                final closeStart = i + 1;
                final closeIdx =
                    _findCloseSingle(source, closeStart, lineEnd, c0);
                if (closeIdx != -1 && closeIdx > closeStart) {
                  result.add(MdElement(
                    kind: MdElKind.italic,
                    start: i,
                    end: closeIdx + 1,
                  ));
                  i = closeIdx + 1;
                  continue;
                }
              }
            }
          }

          i++;
        }
      }

      // Advance lineStart past line text + the '\n' separator.
      // For the last line there is no '\n', but lineStart won't be used again.
      lineStart += line.length + 1;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Private helpers.
  // ---------------------------------------------------------------------------

  /// Returns true if [line] matches the GFM ordered-list pattern: one or more
  /// ASCII digits followed by '. ' (period + space).
  static bool _isOlLine(String line) {
    var i = 0;
    while (i < line.length && _isDigit(line[i])) {
      i++;
    }
    if (i == 0) return false; // no leading digit
    return i + 1 < line.length && line[i] == '.' && line[i + 1] == ' ';
  }

  static bool _isDigit(String ch) {
    final code = ch.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  // Find the first occurrence of the two-char sequence [delim] in
  // source[start .. end). Returns the index of the first char of the
  // sequence, or -1 if not found.
  static int _findClose(String source, int start, int end, String delim) {
    for (var i = start; i + 1 < end; i++) {
      if (source[i] == delim[0] && source[i + 1] == delim[1]) {
        return i;
      }
    }
    return -1;
  }

  // Find the first occurrence of the single char [delim] in source[start .. end).
  // Returns the index, or -1 if not found.
  static int _findCloseSingle(String source, int start, int end, String delim) {
    for (var i = start; i < end; i++) {
      if (source[i] == delim) return i;
    }
    return -1;
  }
}
