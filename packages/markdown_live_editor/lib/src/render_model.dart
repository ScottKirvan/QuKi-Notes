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
/// character (after the '> ' delimiter).  QuikiRenderEditor uses this to
/// look up the Y coordinate of the line via TextPainter.getOffsetForCaret().
class BlockquoteSlot {
  const BlockquoteSlot({
    required this.element,
    required this.renderedStart,
  });

  final MdElement element;

  /// Rendered offset of the first content character of the blockquote.
  final int renderedStart;
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
    var eIdx = 0;
    final slots = <ImageSlot>[];
    final links = <LinkSlot>[];
    final checkboxes = <CheckboxSlot>[];
    final blockquotes = <BlockquoteSlot>[];
    final hrs = <HrSlot>[];

    void flushBuf() {
      if (bufText.isNotEmpty) {
        spans.add(TextSpan(text: bufText.toString(), style: bufStyle));
        bufText.clear();
        bufStyle = null;
      }
    }

    for (var si = 0; si < source.length; si++) {
      final char = source[si];

      // Advance eIdx past elements whose end is <= si (no longer relevant).
      while (eIdx < elements.length && elements[eIdx].end <= si) {
        eIdx++;
      }

      // Determine which element (if any) contains si.
      final MdElement? currentEl =
          (eIdx < elements.length && si >= elements[eIdx].start)
              ? elements[eIdx]
              : null;

      final revealed = currentEl != null &&
          cursorOffset >= currentEl.start &&
          cursorOffset <= currentEl.end;

      // -----------------------------------------------------------------------
      // Collapsed image: record an ImageSlot and fast-forward past all source
      // chars.  The image emits no rendered characters; the newline that
      // follows (if any) is emitted normally by the next iteration and gives
      // the TextPainter a line break at the correct position.  We record
      // [renderedCharOffset] as the current [ri] — the position in rendered
      // space where the image row sits.  QuikiRenderEditor uses this offset
      // to look up the Y coordinate via TextPainter.getOffsetForCaret().
      // -----------------------------------------------------------------------
      if (!revealed &&
          currentEl != null &&
          currentEl.kind == MdElKind.image &&
          si == currentEl.start) {
        slots.add(ImageSlot(element: currentEl, renderedCharOffset: ri));

        // Map all source chars of the image line to the current rendered position.
        for (var d = currentEl.start; d < currentEl.end; d++) {
          srcToRnd[d] = ri;
        }

        // Fast-forward si to the last char of the element (outer loop increments).
        si = currentEl.end - 1;
        continue;
      }

      // -----------------------------------------------------------------------
      // Collapsed hr: record an HrSlot and fast-forward past all source chars.
      // The hr line emits no rendered characters (entire line is the delimiter).
      // -----------------------------------------------------------------------
      if (!revealed &&
          currentEl != null &&
          currentEl.kind == MdElKind.hr &&
          si == currentEl.start) {
        hrs.add(HrSlot(element: currentEl, renderedCharOffset: ri));

        // Map all source chars to the current rendered position.
        for (var d = currentEl.start; d < currentEl.end; d++) {
          srcToRnd[d] = ri;
        }

        // Fast-forward si to the last char of the element.
        si = currentEl.end - 1;
        continue;
      }

      // -----------------------------------------------------------------------
      // Collapsed blockquote slot recording.
      //
      // At the first content character (after the '> ' delimiter), record the
      // rendered position so QuikiRenderEditor can paint the left border stripe.
      // -----------------------------------------------------------------------
      if (!revealed &&
          currentEl != null &&
          currentEl.kind == MdElKind.blockquote) {
        final contentStart = currentEl.start + currentEl.openDelimLen;
        if (si == contentStart) {
          blockquotes.add(BlockquoteSlot(
            element: currentEl,
            renderedStart: ri,
          ));
        }
      }

      // -----------------------------------------------------------------------
      // Collapsed list marker substitution.
      //
      // When we arrive at the first source character of a collapsed list
      // element's delimiter, emit the collapsedMarker into rendered output
      // (all marker chars map back to [si], the first source delimiter pos),
      // then skip the entire source delimiter region by fast-forwarding [si].
      // -----------------------------------------------------------------------
      if (!revealed &&
          currentEl != null &&
          currentEl.collapsedMarker.isNotEmpty &&
          si == currentEl.start) {
        final marker = currentEl.collapsedMarker;
        final delimEnd = currentEl.start + currentEl.openDelimLen;
        final markerStyle = _contentStyle(currentEl.kind, baseStyle);

        // Emit the rendered marker glyph(s).
        flushBuf();
        if (markerStyle != bufStyle) {
          bufStyle = markerStyle;
        }
        for (final markerChar in marker.split('')) {
          bufText.write(markerChar);
          // All rendered marker chars map back to [si] (start of source delim).
          rndToSrc.add(si);
          ri++;
        }
        flushBuf();

        // Map all source delimiter positions to the rendered start of the marker.
        final markerRenderedStart = ri - marker.length;
        for (var d = si; d < delimEnd; d++) {
          srcToRnd[d] = markerRenderedStart;
        }

        // Record a CheckboxSlot for collapsed checkbox elements so that
        // QuikiRenderEditor can hit-test taps on and paint the checkbox.
        if (currentEl.kind == MdElKind.checkboxUnchecked ||
            currentEl.kind == MdElKind.checkboxChecked) {
          checkboxes.add(CheckboxSlot(
            element: currentEl,
            renderedMarkerStart: markerRenderedStart,
            renderedMarkerEnd: markerRenderedStart + marker.length,
            checked: currentEl.kind == MdElKind.checkboxChecked,
            color: markerStyle.color ?? _foreground,
          ));
        }

        // Skip past the source delimiter chars (si will be incremented by
        // the outer for-loop so advance to delimEnd - 1).
        si = delimEnd - 1;
        continue;
      }

      // -----------------------------------------------------------------------
      // Collapsed link slot recording.
      //
      // At the first content character (si == contentStart), we know both
      // bounds of the rendered content range because content chars are 1:1
      // with rendered chars in Stage 6 (no nested markup inside link text).
      // renderedStart = ri (current rendered position); renderedEnd = ri + contentLen.
      // -----------------------------------------------------------------------
      if (!revealed &&
          currentEl != null &&
          (currentEl.kind == MdElKind.link ||
              currentEl.kind == MdElKind.autolink)) {
        final contentStart = currentEl.start + currentEl.openDelimLen;
        final contentEnd = currentEl.end - currentEl.closeDelimLen;
        if (si == contentStart) {
          final contentLen = contentEnd - contentStart;
          links.add(LinkSlot(
            element: currentEl,
            renderedStart: ri,
            renderedEnd: ri + contentLen,
          ));
        }
      }

      // -----------------------------------------------------------------------
      // Normal per-character processing.
      // -----------------------------------------------------------------------

      // Determine visibility and style for this character.
      bool visible;
      TextStyle charStyle;

      if (currentEl == null) {
        visible = true;
        charStyle = baseStyle;
      } else if (revealed) {
        visible = true;
        charStyle = baseStyle;
      } else {
        // Collapsed.
        if (currentEl.isDelimiter(si)) {
          visible = false;
          charStyle = baseStyle; // unused, but Dart requires initialization
        } else {
          visible = true;
          charStyle = _contentStyle(currentEl.kind, baseStyle);
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
    srcToRnd[source.length] = ri;
    rndToSrc.add(source.length); // end sentinel: renderedLength → source.length

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
      MdElKind.ul ||
      MdElKind.ol ||
      MdElKind.checkboxUnchecked ||
      MdElKind.checkboxChecked ||
      MdElKind.image =>
        base,
    };
