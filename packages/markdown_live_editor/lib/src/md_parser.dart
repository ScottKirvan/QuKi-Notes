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

  /// A backslash escape of a single ASCII-punctuation character (`\*`, `\[`,
  /// etc.). The backslash is the (hidden) opening delimiter; the escaped
  /// punctuation character is content rendered literally in the surrounding
  /// style. Inline-only; never produced for a non-punctuation escape (`\A`),
  /// where both characters stay literal with no element (ADR-33).
  escape,
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
    int srcMarkerLen = 0,
    this.imagePath = '',
    this.url = '',
    this.indentLevel = 0,
  }) : _srcMarkerLen = srcMarkerLen;

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

  /// The number of source characters in a variable-length block marker.
  ///
  /// For [MdElKind.ol]: the ordered-list marker length (e.g. '1. ' = 3,
  /// '12. ' = 4). Stored separately because the source digits may differ from
  /// [seqNum].
  ///
  /// For [MdElKind.blockquote]: the marker length, which is variable per
  /// CommonMark and now also depth-dependent — however many source
  /// characters the depth-counting loop consumed peeling off `>` prefixes
  /// (each `>`, optionally followed by one space, consumes one level). 2 for
  /// a single-level `> `, 1 for a single bare `>`, and more for deeper
  /// nesting (`>>`, `> > `, etc. — see [indentLevel]). See [openDelimLen].
  ///
  /// 0 (unused) for every other kind, whose marker length is fixed.
  final int _srcMarkerLen;

  /// For [MdElKind.image]: the raw path string extracted from `![alt](path)`.
  /// The content between the last `(` and the final `)` on the line.
  /// Empty string for all non-image kinds.
  final String imagePath;

  /// For [MdElKind.link]: the URL string extracted from `[text](url)`.
  /// The content between `](` and the final `)`.
  /// Empty string for all non-link kinds.
  final String url;

  /// Block indent depth (ADR-34 / block_indentation.md), 0 for a top-level
  /// block. General mechanism, not blockquote-specific: any block kind whose
  /// content should be laid out in its own narrower, offset region can set
  /// this. Currently only [MdElKind.blockquote] sets a non-zero value — the
  /// nesting depth computed by peeling `>` prefixes (a bare `>` or `> `
  /// consumes one level each). [RenderModel] groups consecutive rendered
  /// lines sharing the same [indentLevel] into layout runs; list-item
  /// indentation (a later stage) reuses this same field.
  final int indentLevel;

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
        MdElKind.ol => _srcMarkerLen, // '{digits}. ' — variable
        MdElKind.checkboxUnchecked => 6, // '- [ ] '
        MdElKind.checkboxChecked => 6, // '- [x] ' or '- [X] '
        // Image: the full source line is the delimiter; no content chars emitted.
        MdElKind.image => end - start,
        // Link: opening '[' is the only opening delimiter (1 char).
        // The closing delimiter is '](url)' — handled by closeDelimLen.
        MdElKind.link => 1,
        // Autolink: URL is the content itself — no delimiter characters.
        MdElKind.autolink => 0,
        // Blockquote: the marker is `>` optionally followed by one space, so
        // the delimiter length is variable — 2 for `> `, 1 for a bare `>`.
        MdElKind.blockquote => _srcMarkerLen,
        // Hr: the entire source line is the delimiter; no content chars emitted.
        MdElKind.hr => end - start,
        // Escape: the leading backslash is the (hidden) opening delimiter.
        MdElKind.escape => 1,
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
        MdElKind.hr ||
        // Escape: only the leading backslash is a delimiter; the escaped
        // character is content, so there is no closing delimiter.
        MdElKind.escape =>
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
  /// For checkbox elements, this returns five blank characters reserving the
  /// horizontal space for a glyph plus a gap before the content — the render
  /// object (QuikiRenderEditor) paints the actual box/checkmark itself via
  /// Canvas rather than relying on a Unicode glyph, because Android's
  /// font-fallback shaping picks between a monochrome symbol font and Noto
  /// Color Emoji per text run (not per character), causing checked-box
  /// glyphs to inconsistently render as large colour emoji depending on
  /// document order. See #267. The box is painted at a fixed size (a
  /// fraction of line height) rather than shrunk to fit whatever width is
  /// reserved here — a fixed, comfortable tap target matters more than a
  /// tight gap — so five characters is a deliberately generous reservation
  /// to keep the box clear of the following content text.
  ///
  /// For [MdElKind.blockquote]: returns `''` (no substitution glyph) — see the
  /// switch below and [indentLevel].
  ///
  /// For [MdElKind.image]: returns `''` — the image is not a text substitution;
  /// the render object (QuikiRenderEditor) handles painting the image or
  /// placeholder rect in the paint pass.
  String get collapsedMarker => switch (kind) {
        MdElKind.ul => '• ',
        MdElKind.checkboxUnchecked || MdElKind.checkboxChecked => '     ',
        MdElKind.ol => '$seqNum. ',
        // Heading, blockquote, inline (incl. escape), image, link, and autolink
        // elements: no text substitution glyph.
        //
        // Blockquote content used to reserve horizontal indentation here as
        // blank characters (ADR-33 Stage 4) — the same trick proven for list/
        // checkbox markers. Device testing showed that trick only indents a
        // line's first visual row: Flutter's word-wrap has no way to re-apply a
        // leading-character indent after breaking a line, so wrapped
        // continuation rows snapped back to the margin. ADR-34 replaces it with
        // real layout indentation — QuikiRenderEditor lays out each run of
        // lines sharing an [indentLevel] as its own narrower, offset region,
        // which survives wrapping. Reserving blank characters here too would
        // double-indent a blockquote's first row relative to its own wrapped
        // continuation rows, so the reservation is removed rather than kept
        // alongside the fix.
        _ => '',
      };

  /// True for block-level element kinds (one per line, non-overlapping):
  /// headings, list markers, checkboxes, blockquote, block image, and hr.
  /// False for inline kinds (bold, italic, strikethrough, inline code, link,
  /// autolink, escape), which may nest and combine within a line.
  bool get isBlock => switch (kind) {
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
        MdElKind.blockquote ||
        MdElKind.image ||
        MdElKind.hr =>
          true,
        MdElKind.bold ||
        MdElKind.italic ||
        MdElKind.strikethrough ||
        MdElKind.inlineCode ||
        MdElKind.link ||
        MdElKind.autolink ||
        MdElKind.escape =>
          false,
      };

  /// True for inline element kinds. Complement of [isBlock].
  bool get isInline => !isBlock;

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
        result.addAll(_scanInline(source, lineStart + 7, lineEnd));
      } else if (line.startsWith('##### ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h5, start: lineStart, end: lineEnd));
        result.addAll(_scanInline(source, lineStart + 6, lineEnd));
      } else if (line.startsWith('#### ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h4, start: lineStart, end: lineEnd));
        result.addAll(_scanInline(source, lineStart + 5, lineEnd));
      } else if (line.startsWith('### ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h3, start: lineStart, end: lineEnd));
        result.addAll(_scanInline(source, lineStart + 4, lineEnd));
      } else if (line.startsWith('## ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h2, start: lineStart, end: lineEnd));
        result.addAll(_scanInline(source, lineStart + 3, lineEnd));
      } else if (line.startsWith('# ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.h1, start: lineStart, end: lineEnd));
        result.addAll(_scanInline(source, lineStart + 2, lineEnd));

        // Step 2 — Checkbox detection (must run before ul, both start with '- ').
      } else if (line.startsWith('- [ ] ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result.add(MdElement(
          kind: MdElKind.checkboxUnchecked,
          start: lineStart,
          end: lineEnd,
        ));
        // '- [ ] ' prefix is 6 chars — scan the remainder inline (ADR-33).
        result.addAll(_scanInline(source, lineStart + 6, lineEnd));
      } else if (line.startsWith('- [x] ') || line.startsWith('- [X] ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result.add(MdElement(
          kind: MdElKind.checkboxChecked,
          start: lineStart,
          end: lineEnd,
        ));
        // '- [x] ' / '- [X] ' prefix is 6 chars — scan the remainder inline.
        result.addAll(_scanInline(source, lineStart + 6, lineEnd));

        // Step 2b — Horizontal rule: a line of 3+ '-', '*', or '_' (with
        // optional spaces between them, no other characters).
        // Must be checked BEFORE the ul step because '- - -' starts with '- '.
      } else if (_isHrLine(line)) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.hr, start: lineStart, end: lineEnd));

        // Step 2c — Blockquote. Per CommonMark, the marker is `>` optionally
        // followed by a single space, so every line beginning with `>` is a
        // blockquote: `> content` (marker '> ', 2 chars), and `>content` or a
        // bare `>` alone (marker '>', 1 char — no space to consume). Nesting
        // (ADR-34) generalizes this: the marker is peeled recursively — each
        // `>`, optionally followed by one space, consumes one level, so
        // `>> text` / `> > text` are depth 2, `>>> text` is depth 3, and so on.
        // The marker length is however many characters the depth-counting loop
        // consumed, stored in srcMarkerLen so openDelimLen / isDelimiter report
        // it correctly; the depth itself is stored in indentLevel.
      } else if (line.startsWith('>')) {
        olBlockStart = 0;
        olRunCount = 0;
        final (depth, markerLen) = _blockquoteDepth(line);
        result.add(MdElement(
          kind: MdElKind.blockquote,
          start: lineStart,
          end: lineEnd,
          srcMarkerLen: markerLen,
          indentLevel: depth,
        ));
        // Scan the content after the marker inline (ADR-33 Stage 4). For an
        // empty blockquote ('>' or '> ' alone) start == end, so _scanInline
        // returns an empty list and no inline elements are produced.
        result.addAll(_scanInline(source, lineStart + markerLen, lineEnd));

        // Step 3 — Unordered list ('- ', '* ', '+ ').
      } else if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          line.startsWith('+ ')) {
        olBlockStart = 0;
        olRunCount = 0;
        result
            .add(MdElement(kind: MdElKind.ul, start: lineStart, end: lineEnd));
        // '- ' / '* ' / '+ ' prefix is 2 chars — scan the remainder inline.
        result.addAll(_scanInline(source, lineStart + 2, lineEnd));

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
          srcMarkerLen: srcDelimLen,
        ));
        // '{digits}. ' marker is srcDelimLen chars — scan the remainder inline.
        result.addAll(_scanInline(source, lineStart + srcDelimLen, lineEnd));

        // Step 4b — HTML-only line (ADR-33 Stage 3). A line consisting entirely
        // of one or more complete HTML tags/comments (plus optional surrounding
        // whitespace) is excluded from inline scanning and passed through raw —
        // markdown-special characters inside a tag/attribute are not misparsed.
        // No element is emitted; the render layer shows the line as typed. A
        // tag that does not close on the same line disqualifies the line, which
        // then falls through to normal paragraph handling (multi-line HTML
        // blocks are not attempted this stage).
      } else if (_isHtmlOnlyLine(line)) {
        olBlockStart = 0;
        olRunCount = 0;
      } else {
        olBlockStart = 0;
        olRunCount = 0;
        // Step 5 — Recursive inline scan (paragraph lines). The same scanner is
        // used for heading, list, checkbox, and blockquote content above; an
        // inline HTML tag mid-paragraph is skipped inside the scanner (ADR-33
        // Stage 3); image / hr lines stay opaque.
        result.addAll(_scanInline(source, lineStart, lineEnd));
      }

      // Advance lineStart past line text + the '\n' separator.
      // For the last line there is no '\n', but lineStart won't be used again.
      lineStart += line.length + 1;
    }

    // Sort so that a containing element always precedes the elements nested
    // inside it: primary key start ascending, secondary key end descending
    // (outer — larger range — before inner at the same start). RenderModel
    // relies on this ordering to resolve the outermost element under the
    // cursor and to combine ancestor styles.
    result
        .sort((a, b) => a.start != b.start ? a.start - b.start : b.end - a.end);
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

  /// Computes blockquote nesting depth and total marker length for [line]
  /// (ADR-34), which must start with `>`.
  ///
  /// Peels `>` prefixes left to right: each `>`, optionally followed by
  /// exactly one space (before the next `>` or the content), consumes one
  /// level. Returns `(depth, markerLen)` where `markerLen` is the number of
  /// source characters consumed — i.e. where the quoted content begins.
  ///
  /// Examples: `'> x'` → (1, 2); `'>x'` → (1, 1); `'>> x'` → (2, 3);
  /// `'> > x'` → (2, 4); `'>>>x'` → (3, 3).
  static (int, int) _blockquoteDepth(String line) {
    var depth = 0;
    var i = 0;
    while (i < line.length && line[i] == '>') {
      depth++;
      i++;
      if (i < line.length && line[i] == ' ') {
        i++;
      }
    }
    return (depth, i);
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

  /// Permissive single-line HTML tag/comment detector (ADR-33 Stage 3).
  ///
  /// If a tag/comment begins at [i] — `source[i]` is `<`, optionally followed
  /// by `/`, then an ASCII letter or `!`, with a closing `>` on the same line
  /// (within [end]) — returns the exclusive offset just past that `>`.
  /// Otherwise returns -1.
  ///
  /// This is deliberately not real HTML grammar validation: it is only good
  /// enough to catch `<div>`, `<span ...>`, `</span>`, `<!-- comment -->`, and
  /// `<!DOCTYPE ...>` so their interiors are excluded from markdown scanning.
  /// A tag whose `>` is not on this line is not matched (multi-line HTML blocks
  /// are not attempted).
  static int _htmlTagEnd(String source, int i, int end) {
    if (i >= end || source[i] != '<') return -1;
    var j = i + 1;
    if (j < end && source[j] == '/') j++; // optional closing-tag slash
    if (j >= end) return -1;
    final ch = source[j];
    if (!(_isAsciiLetter(ch) || ch == '!')) return -1;
    final close = source.indexOf('>', j);
    if (close == -1 || close >= end) return -1;
    return close + 1;
  }

  /// Returns true if [line] consists entirely of one or more complete HTML
  /// tags/comments, separated or surrounded only by ASCII whitespace, using the
  /// same permissive heuristic as [_htmlTagEnd]. Such a line is excluded from
  /// inline markdown scanning (ADR-33 Stage 3). A `<` that does not begin a
  /// complete same-line tag, or any non-whitespace content between/outside the
  /// tags, disqualifies the line — it then falls through to normal paragraph
  /// handling.
  static bool _isHtmlOnlyLine(String line) {
    final n = line.length;
    var i = 0;
    while (i < n && (line[i] == ' ' || line[i] == '\t')) {
      i++;
    }
    if (i >= n || line[i] != '<') return false; // must start with a tag
    var sawTag = false;
    while (i < n) {
      final ch = line[i];
      if (ch == '<') {
        final tagEnd = _htmlTagEnd(line, i, n);
        if (tagEnd == -1) return false; // not a complete same-line tag
        sawTag = true;
        i = tagEnd;
      } else if (ch == ' ' || ch == '\t') {
        i++;
      } else {
        return false; // non-tag, non-whitespace content → not HTML-only
      }
    }
    return sawTag;
  }

  /// True for a single ASCII letter (A–Z or a–z). Used by the HTML tag
  /// heuristic to decide whether a `<`/`</` begins a tag name.
  static bool _isAsciiLetter(String ch) {
    if (ch.length != 1) return false;
    final code = ch.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }

  // ---------------------------------------------------------------------------
  // Recursive inline scanner (ADR-33).
  //
  // Implements the CommonMark delimiter-run + flanking-rule algorithm for the
  // QuKi-Notes inline subset: emphasis (`*`/`_`), strong (`**`/`__`),
  // strikethrough (`~~`), inline code, links, bare-URL autolinks, and backslash
  // escapes. Operates on the half-open source range [start, end) — a single
  // line's content — treating both boundaries as whitespace for flanking.
  //
  // Precedence (per CommonMark): backslash escapes and inline code spans are
  // resolved first and are fully literal inside; links/autolinks are
  // bracket/word matched; emphasis is resolved last, over the delimiter runs
  // left behind by everything above. Emphasis nests arbitrarily.
  //
  // Returned elements may nest (overlapping source ranges); they are unsorted
  // here — MdParser.parse() sorts the combined result.
  // ---------------------------------------------------------------------------
  static List<MdElement> _scanInline(
    String source,
    int start,
    int end, {
    bool scanLinks = true,
  }) {
    if (start >= end) return const [];

    final out = <MdElement>[];
    final delims = <_Delim>[];
    var i = start;

    while (i < end) {
      final c = source[i];

      // Backslash escape: `\` before an ASCII-punctuation char renders that
      // char literally (the backslash is hidden). A backslash before anything
      // else (letter, digit, whitespace, end of line) is a literal backslash —
      // no element, nothing dropped (ADR-33).
      if (c == '\\') {
        if (i + 1 < end && _isAsciiPunct(source[i + 1])) {
          out.add(MdElement(kind: MdElKind.escape, start: i, end: i + 2));
          i += 2;
          continue;
        }
        i += 1;
        continue;
      }

      // Inline HTML tag/comment (ADR-33 Stage 3). A permissive single-line
      // heuristic — `<` or `</` followed by an ASCII letter or `!`, ending at
      // the next same-line `>` — marks an HTML span. The whole span is skipped,
      // exactly as an inline code span is: no element is emitted and no
      // delimiters are recorded inside it, so markdown-special characters that
      // appear in a tag/attribute (e.g. the `*gray*` in
      // `<div style="border: 1px solid *gray*">`) stay literal rather than
      // being misread as emphasis. Detection only — nothing HTML is rendered.
      // A `<` that is not a complete same-line tag falls through to ordinary
      // handling (multi-line HTML blocks are explicitly not attempted).
      if (c == '<') {
        final tagEnd = _htmlTagEnd(source, i, end);
        if (tagEnd != -1) {
          i = tagEnd;
          continue;
        }
        // Not a tag — fall through to ordinary-character handling below.
      }

      // Inline code span (single backtick). Content is fully literal — no
      // emphasis, links, or escapes inside. Resolved before emphasis.
      if (c == '`') {
        final closeIdx = source.indexOf('`', i + 1);
        if (closeIdx != -1 && closeIdx < end && closeIdx > i + 1) {
          out.add(MdElement(
            kind: MdElKind.inlineCode,
            start: i,
            end: closeIdx + 1,
          ));
          i = closeIdx + 1;
          continue;
        }
        // No matching close on this line: literal backtick.
        i += 1;
        continue;
      }

      // Link `[text](url)`. A `[` immediately preceded by `!` is image syntax —
      // inline images stay literal in Stage 1 (no inline-image render path).
      // The link text is recursively scanned for nested emphasis/strikethrough/
      // code/escapes (ADR-33), but not for a nested link — a link cannot contain
      // another link — so the recursive scan runs with scanLinks: false. The
      // scan is bounded to the text span [i+1, textClose), so an opener inside
      // link text can never match a delimiter outside it.
      if (scanLinks && c == '[' && (i == start || source[i - 1] != '!')) {
        final textClose = source.indexOf(']', i + 1);
        if (textClose != -1 &&
            textClose < end &&
            textClose + 1 < end &&
            source[textClose + 1] == '(') {
          final urlClose = source.indexOf(')', textClose + 2);
          if (urlClose != -1 && urlClose < end) {
            out.add(MdElement(
              kind: MdElKind.link,
              start: i,
              end: urlClose + 1,
              url: source.substring(textClose + 2, urlClose),
            ));
            out.addAll(
              _scanInline(source, i + 1, textClose, scanLinks: false),
            );
            i = urlClose + 1;
            continue;
          }
        }
        i += 1;
        continue;
      }

      // Bare URL autolink (`https://` / `http://`). Word-boundary guard: only
      // at content start or after whitespace. Suppressed inside link text
      // (scanLinks: false) — an autolink counts as a link and links do not nest.
      if (scanLinks &&
          c == 'h' &&
          (i == start || source[i - 1] == ' ' || source[i - 1] == '\t') &&
          (source.startsWith('https://', i) ||
              source.startsWith('http://', i))) {
        var urlEnd = i + 1;
        while (
            urlEnd < end && source[urlEnd] != ' ' && source[urlEnd] != '\t') {
          urlEnd++;
        }
        out.add(MdElement(
          kind: MdElKind.autolink,
          start: i,
          end: urlEnd,
          url: source.substring(i, urlEnd),
        ));
        i = urlEnd;
        continue;
      }

      // Emphasis / strong / strikethrough delimiter run.
      if (c == '*' || c == '_' || c == '~') {
        final runLen = _runLength(source, i, end, c);
        // QuKi-Notes supports strikethrough only as exactly `~~`. Any other
        // tilde run length is literal (matches prior behaviour: `~~~~` → none).
        if (c == '~' && runLen != 2) {
          i += runLen;
          continue;
        }
        final before = i > start ? source[i - 1] : ' ';
        final after = i + runLen < end ? source[i + runLen] : ' ';
        final leftFlank = _leftFlanking(before, after);
        final rightFlank = _rightFlanking(before, after);
        bool canOpen;
        bool canClose;
        if (c == '_') {
          // Intraword `_` is disallowed: `_` may open/close only next to
          // whitespace or punctuation, never between two word characters.
          canOpen = leftFlank && (!rightFlank || _isAsciiPunct(before));
          canClose = rightFlank && (!leftFlank || _isAsciiPunct(after));
        } else {
          canOpen = leftFlank;
          canClose = rightFlank;
        }
        delims.add(_Delim(
          char: c,
          start: i,
          end: i + runLen,
          count: runLen,
          origCount: runLen,
          canOpen: canOpen,
          canClose: canClose,
        ));
        i += runLen;
        continue;
      }

      // Ordinary character.
      i += 1;
    }

    _processEmphasis(delims, out);
    return out;
  }

  /// Resolves emphasis/strong/strikethrough spans from the recorded delimiter
  /// runs, appending resulting [MdElement]s to [out]. Faithful to CommonMark's
  /// "process emphasis" procedure over the supported subset: nearest valid
  /// opener wins, the rule-of-three suppresses spurious matches, and `*`/`_`
  /// runs are consumed one or two delimiters at a time (allowing strong to
  /// contain emphasis, e.g. `***x***`). `~~` is consumed as a full pair.
  static void _processEmphasis(List<_Delim> delims, List<MdElement> out) {
    for (var ci = 0; ci < delims.length; ci++) {
      final closer = delims[ci];
      if (closer.removed || !closer.canClose || closer.count == 0) continue;
      final ch = closer.char;

      // Scan left for the nearest usable opener of the same delimiter char.
      var oi = ci - 1;
      var found = false;
      while (oi >= 0) {
        final opener = delims[oi];
        if (!opener.removed &&
            opener.count > 0 &&
            opener.canOpen &&
            opener.char == ch) {
          // Rule of three: if either side can be both opener and closer, a
          // match whose combined original length is a multiple of three is
          // rejected — unless both lengths are themselves multiples of three.
          final oddMatch = (closer.canOpen || opener.canClose) &&
              (opener.origCount + closer.origCount) % 3 == 0 &&
              !(opener.origCount % 3 == 0 && closer.origCount % 3 == 0);
          if (!oddMatch) {
            found = true;
            break;
          }
        }
        oi--;
      }
      if (!found) continue;

      final opener = delims[oi];
      final use =
          ch == '~' ? 2 : ((opener.count >= 2 && closer.count >= 2) ? 2 : 1);
      final kind = use == 2
          ? (ch == '~' ? MdElKind.strikethrough : MdElKind.bold)
          : MdElKind.italic;

      // Opening delimiters are consumed from the inner (content) side of the
      // opener run; closing delimiters from the inner side of the closer run.
      out.add(MdElement(
        kind: kind,
        start: opener.end - use,
        end: closer.start + use,
      ));

      // Delimiters strictly between opener and closer can no longer match
      // anything outside this span.
      for (var k = oi + 1; k < ci; k++) {
        delims[k].removed = true;
      }

      opener.end -= use;
      opener.count -= use;
      closer.start += use;
      closer.count -= use;
      if (opener.count == 0) opener.removed = true;
      if (closer.count > 0) {
        ci--; // Re-run this closer for any remaining delimiters.
      } else {
        closer.removed = true;
      }
    }
  }

  /// Length of the run of identical character [ch] starting at [i], bounded by
  /// [end].
  static int _runLength(String source, int i, int end, String ch) {
    var j = i;
    while (j < end && source[j] == ch) {
      j++;
    }
    return j - i;
  }

  /// A delimiter run is left-flanking if it is not followed by whitespace and
  /// either not followed by punctuation, or preceded by whitespace/punctuation.
  static bool _leftFlanking(String before, String after) {
    if (_isInlineWs(after)) return false;
    if (!_isAsciiPunct(after)) return true;
    return _isInlineWs(before) || _isAsciiPunct(before);
  }

  /// A delimiter run is right-flanking if it is not preceded by whitespace and
  /// either not preceded by punctuation, or followed by whitespace/punctuation.
  static bool _rightFlanking(String before, String after) {
    if (_isInlineWs(before)) return false;
    if (!_isAsciiPunct(before)) return true;
    return _isInlineWs(after) || _isAsciiPunct(after);
  }

  static bool _isInlineWs(String ch) => ch == ' ' || ch == '\t' || ch == '\n';

  /// True for the ASCII punctuation characters CommonMark recognizes as
  /// escapable and as flanking punctuation.
  static bool _isAsciiPunct(String ch) {
    if (ch.length != 1) return false;
    final code = ch.codeUnitAt(0);
    return (code >= 0x21 && code <= 0x2F) || // ! " # $ % & ' ( ) * + , - . /
        (code >= 0x3A && code <= 0x40) || //   : ; < = > ? @
        (code >= 0x5B && code <= 0x60) || //   [ \ ] ^ _ `
        (code >= 0x7B && code <= 0x7E); //     { | } ~
  }
}

// ---------------------------------------------------------------------------
// _Delim — a mutable delimiter run used while resolving emphasis. `start`/`end`
// and `count` shrink as delimiters are consumed from a run's inner side.
// ---------------------------------------------------------------------------

class _Delim {
  _Delim({
    required this.char,
    required this.start,
    required this.end,
    required this.count,
    required this.origCount,
    required this.canOpen,
    required this.canClose,
  });

  final String char;
  int start;
  int end;
  int count;
  final int origCount;
  final bool canOpen;
  final bool canClose;
  bool removed = false;
}
