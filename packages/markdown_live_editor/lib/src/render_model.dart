import 'package:flutter/widgets.dart';

import 'md_parser.dart';

// ---------------------------------------------------------------------------
// ImageSlot — carries one collapsed image element and its rendered position.
// ---------------------------------------------------------------------------

/// Describes a collapsed image element that QuikiRenderEditor must paint.
///
/// [element] is the parsed [MdElement] with kind [MdElKind.image].
/// [renderedCharOffset] is the rendered character offset at which the image
/// appears in the TextPainter flow — used to look up the vertical position
/// of the image row via TextPainter.getOffsetForCaret().
///
/// The image line emits no rendered characters, so [renderedCharOffset] is the
/// position of the newline that *follows* the image line (or the end sentinel
/// when the image is the last line).  QuikiRenderEditor uses this offset to
/// determine the Y coordinate of the image row.
class ImageSlot {
  const ImageSlot({required this.element, required this.renderedCharOffset});

  final MdElement element;
  final int renderedCharOffset;
}

// ---------------------------------------------------------------------------
// BlockquoteSlot — carries one collapsed blockquote element and its rendered
// position, so QuikiRenderEditor can paint the left border stripe.
// ---------------------------------------------------------------------------

/// Describes a collapsed blockquote element that QuikiRenderEditor must
/// decorate with a left border stripe.
///
/// [renderedStart] is the rendered character offset of the first content
/// character (after the blockquote marker); [renderedEnd] is the rendered
/// offset just past the last content character of the line (the position of
/// the following newline, or the end sentinel for the final line).
/// QuikiRenderEditor uses both to look up the vertical extent of the line —
/// including any wrapped visual rows — via TextPainter.getOffsetForCaret(), so
/// the stripe spans the full height of the (possibly wrapped) content rather
/// than a single line. For an empty blockquote the two offsets are equal and
/// the stripe falls back to one line height.
class BlockquoteSlot {
  const BlockquoteSlot({
    required this.element,
    required this.renderedStart,
    required this.renderedEnd,
  });

  final MdElement element;

  /// Rendered offset of the first content character of the blockquote.
  final int renderedStart;

  /// Rendered offset just past the last content character of the blockquote
  /// line (the following newline's rendered offset, or the end sentinel).
  final int renderedEnd;
}

/// Groups blockquote stripe slots into runs of consecutive source lines.
///
/// Two slots are consecutive when the next element begins exactly one
/// character — the line-separating `\n` — after the previous element ends
/// (`prev.element.end + 1 == next.element.start`). Consecutive `>` lines form a
/// single quoted block with one continuous border in GFM/GitHub, so each
/// returned run is painted by QuikiRenderEditor as one uninterrupted stripe. A
/// non-blockquote line, or a revealed blockquote line (which carries no slot),
/// breaks the run.
///
/// [slots] must be in document order, which [RenderModel.build] guarantees.
/// Pure and side-effect free so the merging can be unit-tested without a
/// laid-out TextPainter.
List<List<BlockquoteSlot>> groupBlockquoteRuns(List<BlockquoteSlot> slots) {
  final runs = <List<BlockquoteSlot>>[];
  for (final slot in slots) {
    if (runs.isNotEmpty &&
        runs.last.last.element.end + 1 == slot.element.start) {
      runs.last.add(slot);
    } else {
      runs.add([slot]);
    }
  }
  return runs;
}

// ---------------------------------------------------------------------------
// HrSlot — carries one hr element and its rendered position, so
// QuikiRenderEditor can paint the horizontal rule line.
// ---------------------------------------------------------------------------

/// Describes a collapsed horizontal rule element that QuikiRenderEditor must
/// paint as a thin horizontal line.
///
/// [renderedCharOffset] is the rendered character offset at which the hr line
/// sits in the TextPainter flow.  Since the hr emits no rendered characters,
/// this is the position of the newline that follows (or the end sentinel).
class HrSlot {
  const HrSlot({required this.element, required this.renderedCharOffset});

  final MdElement element;
  final int renderedCharOffset;
}

// ---------------------------------------------------------------------------
// CheckboxSlot — carries one collapsed checkbox element for tap-to-toggle.
// ---------------------------------------------------------------------------

/// Describes a collapsed checkbox element (unchecked or checked).
///
/// [element] is the parsed [MdElement] with kind [MdElKind.checkboxUnchecked]
/// or [MdElKind.checkboxChecked]. The box and checkmark are painted directly
/// by QuikiRenderEditor via Canvas — not rendered as a Unicode glyph — because
/// Android's font-fallback shaping picks a font per text run rather than per
/// character, so a checked-box glyph can render as a large colour emoji or a
/// small monochrome symbol depending on what precedes it in the document.
/// See #267.
///
/// [renderedMarkerStart] is the rendered character offset of the first of the
/// two blank characters reserved for the glyph.
/// [renderedMarkerEnd] is the exclusive end of the marker — always
/// [renderedMarkerStart] + 2.
///
/// QuikiRenderEditor uses these to hit-test a tap: if the tap maps to a
/// rendered offset in [renderedMarkerStart, renderedMarkerEnd), the checkbox
/// was tapped and [element.start] is returned as the source offset to toggle.
class CheckboxSlot {
  const CheckboxSlot({
    required this.element,
    required this.renderedMarkerStart,
    required this.renderedMarkerEnd,
    required this.checked,
    required this.color,
  });

  final MdElement element;

  /// Rendered offset of the first of the two blank marker characters.
  final int renderedMarkerStart;

  /// Rendered offset just past the last blank marker character
  /// (= renderedMarkerStart + 2).
  final int renderedMarkerEnd;

  /// Whether this is a checked (vs unchecked) checkbox.
  final bool checked;

  /// The color to paint the box outline / checkmark in — matches the
  /// surrounding text color so it adapts to the active theme.
  final Color color;
}

// ---------------------------------------------------------------------------
// LinkSlot — carries one collapsed link element for tap-to-navigate lookup.
// ---------------------------------------------------------------------------

/// Describes a collapsed inline link element.
///
/// [element] is the parsed [MdElement] with kind [MdElKind.link].
/// [renderedStart] and [renderedEnd] are the rendered character offsets that
/// bound the link text in the TextPainter flow.  QuikiEditorState uses these
/// to determine whether a tap position falls inside a collapsed link.
class LinkSlot {
  const LinkSlot({
    required this.element,
    required this.renderedStart,
    required this.renderedEnd,
  });

  final MdElement element;

  /// Rendered offset of the first character of the link text.
  final int renderedStart;

  /// Rendered offset just past the last character of the link text.
  final int renderedEnd;
}

// ---------------------------------------------------------------------------
// RenderModel — builds a rendered TextSpan tree and bidirectional offset
// mappings from a parsed element list and a cursor position.
// ---------------------------------------------------------------------------

class RenderModel {
  const RenderModel._({
    required this.textSpan,
    required this.renderedLength,
    required this.sourceToRendered,
    required this.renderedToSource,
    this.imageSlots = const [],
    this.linkSlots = const [],
    this.checkboxSlots = const [],
    this.blockquoteSlots = const [],
    this.hrSlots = const [],
  });

  /// The rendered TextSpan to pass to TextPainter.  Contains only visible
  /// characters (delimiters of collapsed elements are absent).
  final TextSpan textSpan;

  /// Number of characters in the rendered text (= renderedToSource.length - 1).
  final int renderedLength;

  /// Maps every source offset in [0 .. source.length] to a rendered offset.
  /// Multiple source offsets may map to the same rendered offset (delimiter
  /// chars of collapsed elements all map to the boundary of their rendered
  /// content).
  final List<int> sourceToRendered;

  /// Maps every rendered offset in [0 .. renderedLength] to a source offset.
  /// Length = renderedLength + 1.
  final List<int> renderedToSource;

  /// Image elements that need to be painted by QuikiRenderEditor in the paint
  /// pass.  Only contains collapsed image elements (revealed ones are already
  /// visible as raw source text via the TextPainter and need no special paint).
  final List<ImageSlot> imageSlots;

  /// Collapsed link elements.  QuikiEditorState uses this list to determine
  /// whether a tap falls inside a collapsed link and, if so, which URL to open.
  /// Only contains collapsed link elements — revealed links behave as plain text
  /// for tap purposes (cursor moves normally, no URL open).
  final List<LinkSlot> linkSlots;

  /// Collapsed checkbox elements.  QuikiEditorState uses this list to determine
  /// whether a tap falls on a collapsed ☐/☑ glyph and, if so, which source
  /// offset to toggle.  Only contains collapsed checkbox elements — revealed
  /// checkboxes (cursor inside) behave as plain text for tap purposes.
  final List<CheckboxSlot> checkboxSlots;

  /// Collapsed blockquote elements.  QuikiRenderEditor uses this list to paint
  /// the left border stripe for each blockquote line.
  final List<BlockquoteSlot> blockquoteSlots;

  /// Collapsed horizontal rule elements.  QuikiRenderEditor uses this list to
  /// paint a thin horizontal line in place of the source text.
  final List<HrSlot> hrSlots;

  int renderedForSource(int srcOff) =>
      sourceToRendered[srcOff.clamp(0, sourceToRendered.length - 1)];

  int sourceForRendered(int rndOff) =>
      renderedToSource[rndOff.clamp(0, renderedToSource.length - 1)];

  static final _empty = RenderModel._(
    textSpan: const TextSpan(text: ''),
    renderedLength: 0,
    sourceToRendered: [0],
    renderedToSource: [0],
    imageSlots: const [],
    linkSlots: const [],
    checkboxSlots: const [],
    blockquoteSlots: const [],
    hrSlots: const [],
  );

  /// Build a [RenderModel] from [source], parsed [elements], and the current
  /// [cursorOffset] (-1 when selection is invalid).
  static RenderModel build({
    required String source,
    required List<MdElement> elements,
    required int cursorOffset,
    required TextStyle baseStyle,
  }) {
    if (source.isEmpty) return _empty;

    final srcToRnd = List<int>.filled(source.length + 1, 0);
    final rndToSrc = <int>[];
    final spans = <TextSpan>[];
    final bufText = StringBuffer();
    TextStyle? bufStyle;
    var ri = 0;
    final slots = <ImageSlot>[];
    final links = <LinkSlot>[];
    final checkboxes = <CheckboxSlot>[];
    final blockquotes = <BlockquoteSlot>[];
    final hrs = <HrSlot>[];

    // Block elements (one per line, non-overlapping) and inline elements
    // (nested/overlapping) are handled separately. Blocks drive marker
    // substitution / image / hr / blockquote handling and supply the per-line
    // content base style; inline elements nest and combine on top (ADR-33).
    final blocks = <MdElement>[];
    final inlines = <MdElement>[];
    for (final e in elements) {
      (e.isBlock ? blocks : inlines).add(e);
    }

    void flushBuf() {
      if (bufText.isNotEmpty) {
        spans.add(TextSpan(text: bufText.toString(), style: bufStyle));
        bufText.clear();
        bufStyle = null;
      }
    }

    // Moving cursors: si only ever increases (including fast-forwards), so a
    // single forward-advancing index into the sorted, non-overlapping block
    // list suffices. Inline elements nest, so an active set is maintained.
    var bi = 0; // index into blocks
    var ii = 0; // index into inlines (added when start <= si)
    final active = <MdElement>[]; // inline elements currently covering si
    final pendingLinks = <_PendingLink>[]; // links awaiting renderedEnd

    for (var si = 0; si < source.length; si++) {
      final char = source[si];

      // Block element covering si (at most one — blocks never overlap).
      while (bi < blocks.length && blocks[bi].end <= si) {
        bi++;
      }
      final MdElement? block =
          (bi < blocks.length && si >= blocks[bi].start) ? blocks[bi] : null;

      // Inline elements covering si. inlines are sorted (start asc, end desc),
      // so insertion order == outermost-first.
      while (ii < inlines.length && inlines[ii].start <= si) {
        active.add(inlines[ii]);
        ii++;
      }
      active.removeWhere((e) => e.end <= si);

      // Reveal unit = the outermost element under the cursor. A block always
      // encloses its line's inline children, so it is the outermost when
      // present; otherwise it is the outermost inline covering si.
      final MdElement? topLevel =
          block ?? (active.isEmpty ? null : active.first);
      final revealed = topLevel != null &&
          cursorOffset >= topLevel.start &&
          cursorOffset <= topLevel.end;

      // -----------------------------------------------------------------------
      // Collapsed block special cases (image / hr / blockquote / list marker).
      // These lines carry no inline children, so block handling is unchanged.
      // -----------------------------------------------------------------------
      if (!revealed && block != null) {
        // Collapsed image: record an ImageSlot, map all chars to the current
        // rendered position, and fast-forward past the whole line (no rendered
        // characters emitted; the following newline lands the row correctly).
        if (block.kind == MdElKind.image && si == block.start) {
          slots.add(ImageSlot(element: block, renderedCharOffset: ri));
          for (var d = block.start; d < block.end; d++) {
            srcToRnd[d] = ri;
          }
          si = block.end - 1;
          continue;
        }

        // Collapsed hr: record an HrSlot and fast-forward (entire line hidden).
        if (block.kind == MdElKind.hr && si == block.start) {
          hrs.add(HrSlot(element: block, renderedCharOffset: ri));
          for (var d = block.start; d < block.end; d++) {
            srcToRnd[d] = ri;
          }
          si = block.end - 1;
          continue;
        }

        // Blockquote stripe slots are recorded in a post-pass after the source
        // → rendered map is complete (see below), not here: recording at the
        // first content char failed for an empty blockquote, whose content
        // position coincides with where the block is retired from this loop, so
        // the slot was never emitted (the off-by-one this fixes).

        // Collapsed list/checkbox marker substitution: emit the collapsedMarker
        // glyph(s) and fast-forward past the source delimiter region.
        if (block.collapsedMarker.isNotEmpty && si == block.start) {
          final marker = block.collapsedMarker;
          final delimEnd = block.start + block.openDelimLen;
          final markerStyle = _contentStyle(block.kind, baseStyle);

          flushBuf();
          if (markerStyle != bufStyle) {
            bufStyle = markerStyle;
          }
          for (final markerChar in marker.split('')) {
            bufText.write(markerChar);
            rndToSrc.add(si);
            ri++;
          }
          flushBuf();

          final markerRenderedStart = ri - marker.length;
          for (var d = si; d < delimEnd; d++) {
            srcToRnd[d] = markerRenderedStart;
          }

          if (block.kind == MdElKind.checkboxUnchecked ||
              block.kind == MdElKind.checkboxChecked) {
            checkboxes.add(CheckboxSlot(
              element: block,
              renderedMarkerStart: markerRenderedStart,
              renderedMarkerEnd: markerRenderedStart + marker.length,
              checked: block.kind == MdElKind.checkboxChecked,
              color: markerStyle.color ?? _foreground,
            ));
          }

          si = delimEnd - 1;
          continue;
        }
      }

      // -----------------------------------------------------------------------
      // Collapsed inline link slot recording (two-phase). Link text may now
      // contain nested emphasis/strikethrough/code (ADR-33), whose delimiters
      // are hidden, so the rendered content length no longer equals the source
      // content length. renderedStart is captured at the first content char;
      // renderedEnd is finalized when si reaches the content end (the current
      // ri = rendered offset just past the last visible label character).
      // Skipped when the link's outermost ancestor is revealed (whole span raw).
      // -----------------------------------------------------------------------
      if (!revealed) {
        for (final e in active) {
          if ((e.kind == MdElKind.link || e.kind == MdElKind.autolink) &&
              si == e.start + e.openDelimLen) {
            pendingLinks.add(_PendingLink(
              element: e,
              renderedStart: ri,
              contentEnd: e.end - e.closeDelimLen,
            ));
          }
        }
      }
      // Finalize any pending links whose content ends at this position. (For an
      // empty link, contentEnd == the just-added contentStart, so it finalizes
      // in the same iteration — renderedEnd == renderedStart.)
      pendingLinks.removeWhere((p) {
        if (p.contentEnd == si) {
          links.add(LinkSlot(
            element: p.element,
            renderedStart: p.renderedStart,
            renderedEnd: ri,
          ));
          return true;
        }
        return false;
      });

      // -----------------------------------------------------------------------
      // Normal per-character processing (headings, paragraphs, and the content
      // of block elements). Style is the combination of the block content style
      // and every covering inline element's modifier; a char is hidden when it
      // is a delimiter of the block or of any covering inline element.
      // -----------------------------------------------------------------------
      bool visible;
      TextStyle charStyle;

      if (revealed) {
        visible = true;
        charStyle = baseStyle;
      } else {
        final isDelim = (block != null && block.isDelimiter(si)) ||
            active.any((e) => e.isDelimiter(si));
        if (isDelim) {
          visible = false;
          charStyle = baseStyle; // unused, but Dart requires initialization
        } else {
          visible = true;
          final contentBase =
              block != null ? _contentStyle(block.kind, baseStyle) : baseStyle;
          charStyle = _combinedInlineStyle(contentBase, active);
        }
      }

      // Update source→rendered map (always, even for invisible chars).
      srcToRnd[si] = ri;

      if (visible) {
        // Group into a style run.
        if (charStyle != bufStyle) {
          flushBuf();
          bufStyle = charStyle;
        }
        bufText.write(char);
        rndToSrc.add(si);
        ri++;
      }
    }

    // Finalize.
    flushBuf();

    // Any link still pending has content reaching the end of the source (e.g. a
    // collapsed autolink at end of line); finalize it against the final ri.
    for (final p in pendingLinks) {
      links.add(LinkSlot(
        element: p.element,
        renderedStart: p.renderedStart,
        renderedEnd: ri,
      ));
    }

    srcToRnd[source.length] = ri;
    rndToSrc.add(source.length); // end sentinel: renderedLength → source.length

    // Blockquote stripe slots (post-pass). Recorded here, once srcToRnd is
    // complete, so the rendered content span can be read for any block —
    // including an empty blockquote, whose content position the per-character
    // loop never reaches while the block is still current (the fixed off-by-one).
    // renderedStart = rendered offset of the marker start (the '>'/'> ' chars
    // are hidden, so this equals the first content char's rendered offset);
    // renderedEnd = rendered offset just past the last content char. A revealed
    // blockquote (cursor anywhere on its line — the block is the outermost
    // element) shows raw source and paints no stripe, matching every other
    // element's reveal rule.
    for (final b in blocks) {
      if (b.kind != MdElKind.blockquote) continue;
      final revealed = cursorOffset >= b.start && cursorOffset <= b.end;
      if (revealed) continue;
      blockquotes.add(BlockquoteSlot(
        element: b,
        renderedStart: srcToRnd[b.start],
        renderedEnd: srcToRnd[b.end],
      ));
    }

    return RenderModel._(
      textSpan: TextSpan(children: spans.isEmpty ? null : spans),
      renderedLength: ri,
      sourceToRendered: srcToRnd,
      renderedToSource: rndToSrc,
      imageSlots: slots,
      linkSlots: links,
      checkboxSlots: checkboxes,
      blockquoteSlots: blockquotes,
      hrSlots: hrs,
    );
  }
}

// ---------------------------------------------------------------------------
// _PendingLink — a collapsed link whose renderedStart is known but whose
// renderedEnd is finalized only once its (possibly delimiter-hiding) label has
// been fully emitted. File-private to RenderModel.build().
// ---------------------------------------------------------------------------

class _PendingLink {
  _PendingLink({
    required this.element,
    required this.renderedStart,
    required this.contentEnd,
  });

  final MdElement element;
  final int renderedStart;
  final int contentEnd;
}

// ---------------------------------------------------------------------------
// Content style helper — file-private.
// ---------------------------------------------------------------------------

/// Primer DHC accent / link color.
const Color _linkColor = Color(0xFF71B7FF);

/// Primer DHC neutral elevated — used as inline code background.
/// Chosen to be visually distinct from both the canvas (#0a0c10) and
/// surface (#272b33); closer to GitHub's code-block background on dark theme.
const Color _codeBackground = Color(0xFF3D444D);

/// Primer DHC foreground color.
const Color _foreground = Color(0xFFF0F3F9);

/// Primer DHC muted color — used for delimiter characters in revealed mode.
const Color _muted = Color(0xFF9EA7B4);

TextStyle _contentStyle(MdElKind kind, TextStyle base) => switch (kind) {
      MdElKind.h1 => base.copyWith(
          fontSize: (base.fontSize ?? 16.0) * 2.0,
          fontWeight: FontWeight.bold,
        ),
      MdElKind.h2 => base.copyWith(
          fontSize: (base.fontSize ?? 16.0) * 1.5,
          fontWeight: FontWeight.bold,
        ),
      MdElKind.h3 => base.copyWith(
          fontSize: (base.fontSize ?? 16.0) * 1.25,
          fontWeight: FontWeight.bold,
        ),
      // h4: ~1.0× body size, bold, foreground — same size, heavier weight.
      MdElKind.h4 => base.copyWith(
          fontWeight: FontWeight.bold,
          color: _foreground,
        ),
      // h5: ~0.875× body size, bold, foreground.
      MdElKind.h5 => base.copyWith(
          fontSize: (base.fontSize ?? 16.0) * 0.875,
          fontWeight: FontWeight.bold,
          color: _foreground,
        ),
      // h6: ~0.85× body size, bold, muted.
      MdElKind.h6 => base.copyWith(
          fontSize: (base.fontSize ?? 16.0) * 0.85,
          fontWeight: FontWeight.bold,
          color: _muted,
        ),
      MdElKind.bold => base.copyWith(fontWeight: FontWeight.bold),
      MdElKind.italic => base.copyWith(fontStyle: FontStyle.italic),
      // Strikethrough: foreground color with line-through decoration.
      MdElKind.strikethrough => base.copyWith(
          color: _foreground,
          decoration: TextDecoration.lineThrough,
        ),
      // Inline code: monospace, distinct background.
      MdElKind.inlineCode => base.copyWith(
          fontFamily: 'monospace',
          backgroundColor: _codeBackground,
          color: _foreground,
        ),
      // Link and autolink: underlined + Primer DHC accent color.
      MdElKind.link || MdElKind.autolink => base.copyWith(
          color: _linkColor,
          decoration: TextDecoration.underline,
          decorationColor: _linkColor,
        ),
      // Blockquote: content in muted color.
      MdElKind.blockquote => base.copyWith(color: _muted),
      // Hr: the entire source line is the delimiter; no content chars rendered
      // as text.  This case is reached only in revealed mode (cursor inside hr),
      // where the raw source '---' etc. shows in base style.
      MdElKind.hr => base,
      // List kinds: content in baseStyle (marker substituted separately).
      // Image: revealed mode shows raw source in baseStyle.
      // Escape: the escaped character renders literally in the surrounding
      // style; the actual style comes from the ancestor combination, so base.
      MdElKind.ul ||
      MdElKind.ol ||
      MdElKind.checkboxUnchecked ||
      MdElKind.checkboxChecked ||
      MdElKind.image ||
      MdElKind.escape =>
        base,
    };

// ---------------------------------------------------------------------------
// Inline style combination — file-private.
//
// Applies each covering inline element's style modifier cumulatively, so a
// character inside nested/combined runs (e.g. bold containing italic
// containing strikethrough) gets every ancestor's styling at once. Elements
// are applied outermost→innermost so the innermost wins on conflicting scalar
// properties (color, background); text decorations accumulate rather than
// replace, so strikethrough and a link underline can coexist.
//
// For a single covering element this reproduces the single-level
// _contentStyle result exactly, preserving all pre-ADR-33 rendered output.
// ---------------------------------------------------------------------------

TextStyle _combinedInlineStyle(TextStyle base, List<MdElement> covering) {
  if (covering.isEmpty) return base;
  var s = base;
  final decorations = <TextDecoration>[];
  for (final e in covering) {
    switch (e.kind) {
      case MdElKind.bold:
        s = s.copyWith(fontWeight: FontWeight.bold);
      case MdElKind.italic:
        s = s.copyWith(fontStyle: FontStyle.italic);
      case MdElKind.strikethrough:
        s = s.copyWith(color: _foreground);
        decorations.add(TextDecoration.lineThrough);
      case MdElKind.inlineCode:
        s = s.copyWith(
          fontFamily: 'monospace',
          backgroundColor: _codeBackground,
          color: _foreground,
        );
      case MdElKind.link:
      case MdElKind.autolink:
        s = s.copyWith(color: _linkColor, decorationColor: _linkColor);
        decorations.add(TextDecoration.underline);
      case MdElKind.escape:
        // No style contribution — the escaped character inherits ancestors.
        break;
      default:
        // Block kinds never appear in the covering-inline list.
        break;
    }
  }
  if (decorations.isNotEmpty) {
    s = s.copyWith(decoration: TextDecoration.combine(decorations));
  }
  return s;
}
