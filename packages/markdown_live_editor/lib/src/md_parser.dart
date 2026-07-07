// ---------------------------------------------------------------------------
// Markdown element kinds supported through Stage 6.
// ---------------------------------------------------------------------------

enum MdElKind {
  h1,
  h2,
  h3,
  h4,
  h5,
  h6,
  bold,
  italic,
  strikethrough,
  inlineCode,
  ul,
  ol,
  checkboxUnchecked,
  checkboxChecked,
  image,
  link,
  autolink,
  blockquote,
  hr,
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
    this.imagePath = '',
    this.url = '',
  }) : _srcOlDelimLen = srcOlDelimLen;

  /// Kind of markdown element.
  final MdElKind kind;

  /// Source offset of the first character of this element (inclusive).
  final int start;

  /// Source offset just past the last character of this element (exclusive).
  final int end;

  /// For [MdElKind.ol]: the GFM-compatible rendered sequence number.
  /// The first line of a consecutive ol block uses its source digit; each
  /// subsequent line in the block increments by 1 regardless of source digit.
  /// For all other kinds this is 0 and should not be read.
  final int seqNum;

  /// For [MdElKind.ol]: the number of source characters in the marker
  /// (e.g. '1. ' = 3, '12. ' = 4). Stored separately because the source
  /// digits may differ from [seqNum].
  final int _srcOlDelimLen;

  /// For [MdElKind.image]: the raw path string extracted from `![alt](path)`.
  /// The content between the last `(` and the final `)` on the line.
  /// Empty string for all non-image kinds.
  final String imagePath;

  /// For [MdElKind.link]: the URL string extracted from `[text](url)`.
  /// The content between `](` and the final `)`.
  /// Empty string for all non-link kinds.
  final String url;

  /// True if [offset] falls within this element's source range.
  bool containsOffset(int offset) => offset >= start && offset < end;

  /// Length of the opening delimiter in source characters.
  ///
  /// For [MdElKind.image]: the full line length — the entire `![alt](path)` is
  /// treated as the "delimiter" so that in revealed mode the user sees and edits
  /// the raw source directly. The render layer handles painting.
  ///
  /// For [MdElKind.link]: 1 — just the `[` opening bracket. The closing
  /// delimiter `](url)` is handled by [closeDelimLen].
  int get openDelimLen => switch (kind) {
        MdElKind.h1 => 2, // '# '
        MdElKind.h2 => 3, // '## '
        MdElKind.h3 => 4, // '### '
        MdElKind.h4 => 5, // '#### '
        MdElKind.h5 => 6, // '##### '
        MdElKind.h6 => 7, // '###### '
        MdElKind.bold => 2, // '**' or '__'
        MdElKind.italic => 1, // '*' or '_'
        MdElKind.strikethrough => 2, // '~~'
        MdElKind.inlineCode => 1, // '`'
        MdElKind.ul => 2, // '- ' / '* ' / '+ '
        MdElKind.ol => _srcOlDelimLen, // '{digits}. ' — variable
        MdElKind.checkboxUnchecked => 6, // '- [ ] '
        MdElKind.checkboxChecked => 6, // '- [x] ' or '- [X] '
        // Image: the full source line is the delimiter; no content chars emitted.
        MdElKind.image => end - start,
        // Link: opening '[' is the only opening delimiter (1 char).
        // The closing delimiter is '](url)' — handled by closeDelimLen.
        MdElKind.link => 1,
        // Autolink: URL is the content itself — no delimiter characters.
        MdElKind.autolink => 0,
        // Blockquote: '> ' is the opening delimiter (2 chars).
        MdElKind.blockquote => 2,
        // Hr: the entire source line is the delimiter; no content chars emitted.
        MdElKind.hr => end - start,
      };

  /// For [MdElKind.link]: the length of the closing delimiter `](url)`.
  /// = 2 (for `](`) + url.length + 1 (for `)`).
  int get _linkCloseDelimLen => 2 + url.length + 1;

  /// Length of the closing delimiter (0 for block-level elements).
  int get closeDelimLen => switch (kind) {
        MdElKind.h1 ||
        MdElKind.h2 ||
        MdElKind.h3 ||
        MdElKind.h4 ||
        MdElKind.h5 ||
        MdElKind.h6 ||
        MdElKind.ul ||
        MdElKind.ol ||
        MdElKind.checkboxUnchecked ||
        MdElKind.checkboxChecked ||
        // Image has no separate closing delimiter (the full line is the opener).
        MdElKind.image ||
        // Autolink has no delimiter characters at all.
        MdElKind.autolink ||
        // Blockquote closing delimiter: none (content extends to end of line).
        MdElKind.blockquote ||
        // Hr: no separate closing delimiter (full line is the opener).
        MdElKind.hr =>
          0,
        MdElKind.bold => 2,
        MdElKind.italic => 1,
        MdElKind.strikethrough => 2,
        MdElKind.inlineCode => 1,
        // Link closing delimiter: '](url)' = '](' + url + ')'
        MdElKind.link => _linkCloseDelimLen,
      };

  /// The string that replaces the source marker in collapsed (rendered) mode.
  ///
  /// For inline elements (bold, italic) and headings, the marker is simply
  /// hidden (delimiter chars omitted), so [collapsedMarker] returns the empty
  /// string — the render model handles those by skipping delimiter source
  /// characters rather than emitting a substitution glyph.
  ///
  /// For block list elements, this returns the visual glyph + space.
  ///
  /// For [MdElKind.image]: returns `''` — the image is not a text substitution;
  /// the render object (QuikiRenderEditor) handles painting the image or
  /// placeholder rect in the paint pass.
  String get collapsedMarker => switch (kind) {
        MdElKind.ul => '• ',
        MdElKind.checkboxUnchecked => '☐ ',
        MdElKind.checkboxChecked => '☑ ',
        MdElKind.ol => '$seqNum. ',
        // Heading, inline, image, link, and autolink elements: no text substitution glyph.
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

    // Ordered-list block tracking (GFM-compatible):
    // - olBlockStart: source digit of the first line in the current ol block (0 = no active block)
    // - olRunCount:   how many consecutive ol lines seen so far in this block (0 = no active block)
    // Each subsequent ol line in a block increments by 1 regardless of its source digit.
    // Any non-ol line resets both counters, starting a new block on the next ol line.
    var olBlockStart = 0;
    var olRunCount = 0;

    for (final line in lines) {
      final lineEnd = lineStart + line.length; // exclusive, excluding '\n'

      // Step 1 — Heading check (longest prefix first to avoid prefix collisions).
      if (line.startsWith('###### ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h6, start: lineStart, end: lineEnd));
      } else if (line.startsWith('##### ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h5, start: lineStart, end: lineEnd));
      } else if (line.startsWith('#### ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h4, start: lineStart, end: lineEnd));
      } else if (line.startsWith('### ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h3, start: lineStart, end: lineEnd));
      } else if (line.startsWith('## ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h2, start: lineStart, end: lineEnd));
      } else if (line.startsWith('# ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h1, start: lineStart, end: lineEnd));

        // Step 2 — Checkbox detection (must run before ul, both start with '- ').
      } else if (line.startsWith('- [ ] ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result.add(MdElement(
          kind: MdElKind.checkboxUnchecked,
          start: lineStart,
          end: lineEnd,
        ));
      } else if (line.startsWith('- [x] ') || line.startsWith('- [X] ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result.add(MdElement(
          kind: MdElKind.checkboxChecked,
          start: lineStart,
          end: lineEnd,
        ));

        // Step 2b — Horizontal rule: a line of 3+ '-', '*', or '_' (with
        // optional spaces between them, no other characters).
        // Must be checked BEFORE the ul step because '- - -' starts with '- '.
      } else if (_isHrLine(line)) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.hr, start: lineStart, end: lineEnd));

        // Step 2c — Blockquote: a line starting with '> ' (greater-than + space).
      } else if (line.startsWith('> ') || line == '> ') {
        olBlockStart = 0;
        olRunCount = 0;
        result.add(MdElement(
            kind: MdElKind.blockquote, start: lineStart, end: lineEnd));

        // Step 3 — Unordered list ('- ', '* ', '+ ').
      } else if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          line.startsWith('+ ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.ul, start: lineStart, end: lineEnd));

        // Step 4a — Block image detection: the entire line is `![alt](path)`.
        // A line qualifies as a block image only when it starts with `![` and
        // ends with `)`.  Inline images within mixed-content lines are deferred.
        // The path is the substring between the last `(` and the final `)`.
      } else if (_isBlockImageLine(line)) {
        olBlockStart = 0;
        olRunCount = 0;
        final path = _extractImagePath(line);
        result.add(MdElement(
          kind: MdElKind.image,
          start: lineStart,
          end: lineEnd,
          imagePath: path,
        ));

        // Step 4 — Ordered list ('{digits}. ').
        // seqNum is block-relative: the first line in a consecutive ol block sets
        // olBlockStart from its source digit; each subsequent line increments by 1.
        // This matches GFM: '1. 1. 1.' renders as '1. 2. 3.' and
        // '5. 1. 1.' renders as '5. 6. 7.'.
      } else if (_isOlLine(line)) {
        final dotIdx = line.indexOf('. ');
        final srcDelimLen = dotIdx + 2; // digits + '. '
        final srcDigit = int.parse(line.substring(0, dotIdx));
        if (olRunCount == 0) {
          // Start of a new block: anchor to this line's source digit.
          olBlockStart = srcDigit;
        }
        olRunCount++;
        final seqNum = olBlockStart + (olRunCount - 1);
        result.add(MdElement(
          kind: MdElKind.ol,
          start: lineStart,
          end: lineEnd,
          seqNum: seqNum,
          srcOlDelimLen: srcDelimLen,
        ));
      } else {
        olBlockStart = 0;
        olRunCount = 0;
        // Step 5 — Inline scan (non-list, non-heading lines only).
        var i = lineStart;
        while (i < lineEnd) {
          // Check inline code: '`content`'
          // Must be checked before bold/italic/strikethrough because backtick
          // content is always literal — no nested markup scanning inside.
          if (source[i] == '`') {
            final closeIdx = _findCloseSingle(source, i + 1, lineEnd, '`');
            if (closeIdx != -1 && closeIdx > i + 1) {
              result.add(MdElement(
                kind: MdElKind.inlineCode,
                start: i,
                end: closeIdx + 1,
              ));
              i = closeIdx + 1;
              continue;
            }
            // No matching close: skip the backtick.
            i++;
            continue;
          }

          // Check link: '[text](url)'
          // A '[' immediately preceded by '!' is image syntax — skip.
          if (source[i] == '[' && (i == lineStart || source[i - 1] != '!')) {
            final textClose = _findCloseSingle(source, i + 1, lineEnd, ']');
            if (textClose != -1 &&
                textClose + 1 < lineEnd &&
                source[textClose + 1] == '(') {
              final urlClose =
                  _findCloseSingle(source, textClose + 2, lineEnd, ')');
              if (urlClose != -1) {
                final extractedUrl = source.substring(textClose + 2, urlClose);
                result.add(MdElement(
                  kind: MdElKind.link,
                  start: i,
                  end: urlClose + 1,
                  url: extractedUrl,
                ));
                i = urlClose + 1;
                continue;
              }
            }
          }

          // Check bare URL autolinks: 'https://' or 'http://'
          // Word-boundary guard: only match at the start of a line or when
          // the immediately preceding character is whitespace (space or tab).
          // Any other preceding character (letter, digit, punctuation) suppresses
          // the match to avoid false positives like 'texthttps://...'.
          if (source[i] == 'h' &&
              (i == lineStart ||
                  source[i - 1] == ' ' ||
                  source[i - 1] == '\t') &&
              (source.startsWith('https://', i) ||
                  source.startsWith('http://', i))) {
            // Find the end of the URL: first whitespace char or end of line.
            var urlEnd = i + 1;
            while (urlEnd < lineEnd &&
                source[urlEnd] != ' ' &&
                source[urlEnd] != '\t') {
              urlEnd++;
            }
            final rawUrl = source.substring(i, urlEnd);
            result.add(MdElement(
              kind: MdElKind.autolink,
              start: i,
              end: urlEnd,
              url: rawUrl,
            ));
            i = urlEnd;
            continue;
          }

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
              // No matching close: skip both delimiter chars so the second
              // char is not re-examined as an italic opener.
              i += 2;
              continue;
            }
          }

          // Check strikethrough: '~~content~~'
          if (i + 1 < lineEnd && source[i] == '~' && source[i + 1] == '~') {
            final closeStart = i + 2;
            final closeIdx = _findClose(source, closeStart, lineEnd, '~~');
            if (closeIdx != -1 && closeIdx > closeStart) {
              result.add(MdElement(
                kind: MdElKind.strikethrough,
                start: i,
                end: closeIdx + 2,
              ));
              i = closeIdx + 2;
              continue;
            }
            // No matching close: skip both tilde chars.
            i += 2;
            continue;
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

  /// Returns true if [line] is a block-level image: starts with `![` and ends
  /// with `)`.  The line must also contain `(` after `]` so the path can be
  /// extracted.  Lines with surrounding text (e.g. `text ![alt](path) more`)
  /// do NOT qualify — scope is block-only for Stage 5.
  static bool _isBlockImageLine(String line) {
    if (!line.startsWith('![')) return false;
    if (!line.endsWith(')')) return false;
    // Must have a `(` somewhere after the `![` opening and before `)`.
    final lastOpen = line.lastIndexOf('(');
    if (lastOpen < 2) return false; // no `(` or it's at the very start
    return true;
  }

  /// Extracts the path from a block image line `![alt](path)`.
  /// Returns the content between the last `(` and the final `)`.
  static String _extractImagePath(String line) {
    final lastOpen = line.lastIndexOf('(');
    // line ends with ')' (guaranteed by _isBlockImageLine).
    return line.substring(lastOpen + 1, line.length - 1);
  }

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

  /// Returns true if [line] is a GFM horizontal rule.
  ///
  /// A horizontal rule is a line consisting entirely of 3 or more '-', '*', or
  /// '_' characters with optional spaces between them and no other characters.
  /// The three characters must all be the same type.
  static bool _isHrLine(String line) {
    if (line.isEmpty) return false;
    // The hr character must be '-', '*', or '_'.
    final hrChar =
        line[0] == '-' || line[0] == '*' || line[0] == '_' ? line[0] : null;
    if (hrChar == null) return false;
    var count = 0;
    for (var ci = 0; ci < line.length; ci++) {
      final c = line[ci];
      if (c == hrChar) {
        count++;
      } else if (c == ' ') {
        // Spaces are allowed between hr characters.
      } else {
        // Any other character disqualifies the line.
        return false;
      }
    }
    return count >= 3;
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
