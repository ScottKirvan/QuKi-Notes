import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Interactive Indent/Dedent — ADR-34 Stage 4 (#77), block_indentation.md.
//
// Pure (text, selection) -> (text, selection) transforms so the toolbar
// buttons (FormattingToolbar) and the Tab/Shift+Tab keys (QuikiEditorState)
// can share exactly one implementation and are guaranteed to produce
// identical results for identical starting state.
//
// The core operation is a line-START whitespace prepend/strip, not a
// cursor-position insert (that is the pre-existing Tab behaviour, kept only
// as the deliberate fallback for headings/blockquotes below). What "line
// start" means differs by what is already on the line:
//
//  - List items (ul/ol/checkboxUnchecked/checkboxChecked, any depth): the
//    whitespace goes before the existing marker, which is exactly what
//    MdParser's leading-whitespace depth computation (see
//    MdParser._listIndent, duplicated locally below since Dart privacy is
//    per-file) already reads to derive indentLevel — so this is a real depth
//    change, and the existing parser recomputes rendering/ol-numbering
//    correctly on the next parse pass with no further work here.
//  - Plain paragraph lines (no recognized block marker at all): a literal
//    tab character is inserted/removed at the absolute line start. Known,
//    deliberate divergence from strict CommonMark — see block_indentation.md
//    Stage 4 and issue #305.
//  - Headings and blockquotes: prepending whitespace before their marker
//    ('#', '>') would break recognition entirely (a real regression, not a
//    style choice), so these fall back to the pre-existing behaviour
//    unchanged: Indent inserts a literal tab AT THE CURSOR (or replaces an
//    active selection, same semantics the old Tab-only implementation had);
//    Dedent is a no-op.
//  - Block images: same reasoning as headings/blockquotes above (recognized
//    via a line prefix `![` and suffix `)`, not the whole line) — a tab
//    inserted elsewhere in the line is harmless, so Indent keeps the
//    at-cursor fallback; Dedent is a no-op.
//  - Horizontal rules: also column-0-anchored, but MdParser's _isHrLine
//    requires the ENTIRE line to be only the hr character or plain spaces,
//    so a tab inserted ANYWHERE (start, middle, or end) always breaks
//    recognition — there is no safe at-cursor insertion point the way there
//    is for headings/blockquotes/images. Confirmed by test:
//    MdParser.parse('-\t--') returns zero elements. So Indent is also a
//    no-op here, matching Dedent, rather than attempting the at-cursor
//    fallback used for the other excluded kinds. See _LineKind.excludedHr.
// ---------------------------------------------------------------------------

/// Result of an [applyIndent] / [applyDedent] call: the new full source text
/// and the new selection, already remapped into that new text's coordinates.
class IndentResult {
  const IndentResult(this.text, this.selection);

  final String text;
  final TextSelection selection;
}

/// Increases indentation for the line(s) touched by [selection] in [text].
/// See the file header for the full per-line-kind rule set.
IndentResult applyIndent(String text, TextSelection selection) {
  if (!selection.isValid) return IndentResult(text, selection);
  if (selection.isCollapsed) return _indentCollapsed(text, selection);
  return _indentOrDedentSelection(text, selection, indent: true);
}

/// Decreases indentation for the line(s) touched by [selection] in [text].
/// See the file header for the full per-line-kind rule set.
IndentResult applyDedent(String text, TextSelection selection) {
  if (!selection.isValid) return IndentResult(text, selection);
  if (selection.isCollapsed) return _dedentCollapsed(text, selection);
  return _indentOrDedentSelection(text, selection, indent: false);
}

// ---------------------------------------------------------------------------
// Collapsed-cursor cases.
// ---------------------------------------------------------------------------

IndentResult _indentCollapsed(String text, TextSelection selection) {
  final offset = selection.baseOffset;
  final (lineStart, lineEnd) = _lineBoundsAt(text, offset);
  final line = text.substring(lineStart, lineEnd);
  final kind = _classifyLine(line);

  if (kind == _LineKind.excludedHr) {
    // No cursor position preserves hr recognition (the whole line must be
    // only the hr character or spaces) — no-op, matching Dedent.
    return IndentResult(text, selection);
  }

  if (kind == _LineKind.excluded) {
    // Fallback: pre-existing at-cursor tab insert (no selection to replace
    // since this is the collapsed case).
    final newText = text.replaceRange(offset, offset, '\t');
    return IndentResult(
      newText,
      TextSelection.collapsed(offset: offset + 1),
    );
  }

  final newText = text.replaceRange(lineStart, lineStart, '\t');
  return IndentResult(
    newText,
    TextSelection.collapsed(offset: offset + 1),
  );
}

IndentResult _dedentCollapsed(String text, TextSelection selection) {
  final offset = selection.baseOffset;
  final (lineStart, lineEnd) = _lineBoundsAt(text, offset);
  final line = text.substring(lineStart, lineEnd);
  final kind = _classifyLine(line);

  if (kind == _LineKind.excluded || kind == _LineKind.excludedHr) {
    return IndentResult(text, selection); // no-op
  }

  final removedLen = _removedLenForDedent(line, kind);
  if (removedLen == 0) {
    return IndentResult(text, selection); // no-op — already at level 0
  }

  final newText = text.replaceRange(lineStart, lineStart + removedLen, '');
  final shifted = offset - removedLen;
  final newOffset = shifted < lineStart ? lineStart : shifted;
  return IndentResult(newText, TextSelection.collapsed(offset: newOffset));
}

// ---------------------------------------------------------------------------
// Active-selection case — every line the selection touches, independently.
// ---------------------------------------------------------------------------

IndentResult _indentOrDedentSelection(
  String text,
  TextSelection selection, {
  required bool indent,
}) {
  final start = selection.start;
  final end = selection.end;

  // A selection ending exactly at the start of a line does not "touch" that
  // line — nothing on it is actually selected (matches common multi-line
  // selection editing conventions, e.g. VS Code).
  final anchorEnd = end > start ? end - 1 : end;

  final lineStarts = <int>[];
  var pos = _lineBoundsAt(text, start).$1;
  while (true) {
    lineStarts.add(pos);
    final lineEnd = _lineBoundsAt(text, pos).$2;
    if (lineEnd >= anchorEnd || lineEnd >= text.length) break;
    pos = lineEnd + 1;
  }

  final eligibleLines = <int>[];
  for (final ls in lineStarts) {
    final lineEnd = _lineBoundsAt(text, ls).$2;
    final line = text.substring(ls, lineEnd);
    final lineKind = _classifyLine(line);
    if (lineKind != _LineKind.excluded && lineKind != _LineKind.excludedHr) {
      eligibleLines.add(ls);
    }
  }

  if (eligibleLines.isEmpty) {
    // Fallback: the pre-existing selection-replace-with-tab behaviour.
    // Dedent has no meaningful analogue (nothing to remove) — no-op.
    if (!indent) return IndentResult(text, selection);
    final newText = text.replaceRange(start, end, '\t');
    return IndentResult(newText, TextSelection.collapsed(offset: start + 1));
  }

  // Apply each eligible line's edit from last to first so earlier lines'
  // offsets stay valid absolute positions in the mutating text — no edit
  // ever touches anything before its own line's start.
  var newText = text;
  final deltas = <int, int>{};
  for (final ls in eligibleLines.reversed) {
    final lineEnd = _lineBoundsAt(newText, ls).$2;
    final line = newText.substring(ls, lineEnd);
    if (indent) {
      newText = newText.replaceRange(ls, ls, '\t');
      deltas[ls] = 1;
    } else {
      final removedLen = _removedLenForDedent(line, _classifyLine(line));
      if (removedLen > 0) {
        newText = newText.replaceRange(ls, ls + removedLen, '');
      }
      deltas[ls] = -removedLen;
    }
  }

  // Remap the selection endpoints: each eligible line's edit sits at that
  // line's start, so it shifts any offset at or after it. Processed in
  // ascending line-start order so the accumulated shift is correct
  // regardless of how many lines the selection spans.
  int remap(int offset) {
    var shift = 0;
    for (final ls in eligibleLines) {
      final delta = deltas[ls]!;
      if (delta > 0) {
        if (offset >= ls) shift += delta;
      } else if (delta < 0) {
        final removedLen = -delta;
        if (offset >= ls + removedLen) {
          shift += delta;
        } else if (offset > ls) {
          // Offset fell inside the removed span — clamp to the line's new
          // (post-edit) start.
          shift -= (offset - ls);
        }
      }
    }
    return offset + shift;
  }

  final newSelection = TextSelection(
    baseOffset: remap(selection.baseOffset),
    extentOffset: remap(selection.extentOffset),
  );
  return IndentResult(newText, newSelection);
}

// ---------------------------------------------------------------------------
// Line classification.
//
// Mirrors MdParser.parse()'s block-detection precedence closely enough to
// decide, for indent/dedent purposes, which of three treatments a line
// gets. Duplicated rather than shared because MdParser's helpers are
// library-private to md_parser.dart (Dart privacy is per-file) and the
// brief leaves this mechanism to the implementer's judgement; if
// MdParser's line-classification rules change, this must be kept in sync.
// ---------------------------------------------------------------------------

enum _LineKind {
  /// ul / ol / checkboxUnchecked / checkboxChecked, at any existing depth.
  /// Indent/Dedent change real nesting depth.
  list,

  /// No recognized block marker. Indent/Dedent insert/remove a literal tab
  /// at the absolute line start.
  paragraph,

  /// Heading, blockquote, or block image — a column-0-anchored marker
  /// recognized via a line prefix/suffix, not the whole line. Indent falls
  /// back to the pre-existing at-cursor tab insert (safe: a tab elsewhere in
  /// the line doesn't touch the prefix/suffix MdParser actually checks).
  /// Dedent is a no-op.
  excluded,

  /// Horizontal rule. Also column-0-anchored, but unlike [excluded] above,
  /// MdParser's _isHrLine requires the ENTIRE line to consist of only the hr
  /// character or plain spaces — a tab inserted anywhere (start, middle, or
  /// end) always breaks recognition; there is no safe at-cursor insertion
  /// point the way there is for headings/blockquotes/images. Confirmed by
  /// test: `MdParser.parse('-\t--')` returns zero elements. So Indent is
  /// also a no-op here, matching Dedent, rather than attempting the
  /// at-cursor fallback used for the other excluded kinds.
  excludedHr,
}

_LineKind _classifyLine(String line) {
  final (_, wsLen) = _lineIndent(line);
  final remainder = wsLen > 0 ? line.substring(wsLen) : line;

  if (wsLen > 0) {
    // Indented list markers (ADR-34 Stage 2+3) — mirrors MdParser's
    // wsLen > 0 branch chain exactly, including the hr guard on ul.
    if (remainder.startsWith('- [ ] ') ||
        remainder.startsWith('- [x] ') ||
        remainder.startsWith('- [X] ')) {
      return _LineKind.list;
    }
    if (!_isHrLine(remainder) &&
        (remainder.startsWith('- ') ||
            remainder.startsWith('* ') ||
            remainder.startsWith('+ '))) {
      return _LineKind.list;
    }
    if (_isOlLine(remainder)) return _LineKind.list;
    // Everything else with leading whitespace is already unrecognized by
    // MdParser (headings/blockquotes/hr/image all require column 0) — so
    // it is already "just a paragraph" today; classifying it as such here
    // does not break anything new.
    return _LineKind.paragraph;
  }

  // wsLen == 0 — column-0-anchored markers.
  if (line.startsWith('- [ ] ') ||
      line.startsWith('- [x] ') ||
      line.startsWith('- [X] ')) {
    return _LineKind.list;
  }
  if (_isHrLine(line)) return _LineKind.excludedHr;
  if (line.startsWith('>')) return _LineKind.excluded;
  if (line.startsWith('- ') || line.startsWith('* ') || line.startsWith('+ ')) {
    return _LineKind.list;
  }
  if (_isBlockImageLine(line)) return _LineKind.excluded;
  if (_isOlLine(line)) return _LineKind.list;
  if (_isHeadingLine(line)) return _LineKind.excluded;
  return _LineKind.paragraph;
}

/// Number of characters to strip from a line's leading whitespace to reduce
/// its indent depth by exactly one level (2 columns; see [_lineIndent]).
/// Only meaningful for a [_LineKind.list] line whose depth is >= 1.
int _removedLenForDedent(String line, _LineKind kind) {
  switch (kind) {
    case _LineKind.list:
      final (depth, _) = _lineIndent(line);
      if (depth == 0) return 0;
      return _dedentWidthLen(line);
    case _LineKind.paragraph:
      return line.startsWith('\t') ? 1 : 0;
    case _LineKind.excluded:
    case _LineKind.excludedHr:
      return 0;
  }
}

/// Greedily consumes leading whitespace characters until their combined
/// column width (space = 1, tab = 2 — matching [_lineIndent]) reaches at
/// least 2, i.e. one full indent level. Returns the character count
/// consumed. Only called when the line's depth is already known to be >= 1,
/// so the leading-whitespace prefix always has enough width available.
int _dedentWidthLen(String line) {
  var removedWidth = 0;
  var i = 0;
  while (i < line.length &&
      (line[i] == ' ' || line[i] == '\t') &&
      removedWidth < 2) {
    removedWidth += line[i] == '\t' ? 2 : 1;
    i++;
  }
  return i;
}

/// Duplicate of MdParser._listIndent (see md_parser.dart for full rationale
/// and examples): leading-whitespace column width (space = 1, tab = 2),
/// divided by 2 for depth.
(int, int) _lineIndent(String line) {
  var width = 0;
  var i = 0;
  while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
    width += line[i] == '\t' ? 2 : 1;
    i++;
  }
  return (width ~/ 2, i);
}

/// Duplicate of MdParser._isHrLine.
bool _isHrLine(String line) {
  if (line.isEmpty) return false;
  final hrChar =
      line[0] == '-' || line[0] == '*' || line[0] == '_' ? line[0] : null;
  if (hrChar == null) return false;
  var count = 0;
  for (var ci = 0; ci < line.length; ci++) {
    final c = line[ci];
    if (c == hrChar) {
      count++;
    } else if (c == ' ') {
      // allowed between hr characters
    } else {
      return false;
    }
  }
  return count >= 3;
}

/// Duplicate of MdParser's ordered-list line pattern check.
bool _isOlLine(String line) {
  var i = 0;
  while (i < line.length && _isDigit(line[i])) {
    i++;
  }
  if (i == 0) return false;
  return i + 1 < line.length && line[i] == '.' && line[i + 1] == ' ';
}

bool _isDigit(String ch) {
  final code = ch.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// Duplicate of MdParser._isBlockImageLine.
bool _isBlockImageLine(String line) {
  if (!line.startsWith('![')) return false;
  if (!line.endsWith(')')) return false;
  final lastOpen = line.lastIndexOf('(');
  if (lastOpen < 2) return false;
  return true;
}

/// True if [line] starts with a recognized heading prefix ('#' through
/// '######', each followed by a space) — mirrors MdParser's column-0
/// heading checks, order-independent since only "is this a heading" matters
/// here (not which level).
bool _isHeadingLine(String line) =>
    line.startsWith('# ') ||
    line.startsWith('## ') ||
    line.startsWith('### ') ||
    line.startsWith('#### ') ||
    line.startsWith('##### ') ||
    line.startsWith('###### ');

/// Line boundaries containing [offset]: `(lineStart, lineEnd)`, `lineEnd`
/// exclusive of the '\n' separator (or text.length for the last line).
/// Mirrors the line-bound calculation already used by
/// MarkdownEditorController.toggleLinePrefix / toggleUnorderedList /
/// toggleOrderedList in markdown_editor.dart.
(int, int) _lineBoundsAt(String text, int offset) {
  final lineStart = offset > 0 ? text.lastIndexOf('\n', offset - 1) + 1 : 0;
  final rawEnd = text.indexOf('\n', offset);
  final lineEnd = rawEnd == -1 ? text.length : rawEnd;
  return (lineStart, lineEnd);
}
