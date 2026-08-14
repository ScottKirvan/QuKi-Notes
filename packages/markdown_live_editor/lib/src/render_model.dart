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

/// Groups blockquote stripe slots into one run-list **per nesting level**
/// (ADR-34), generalizing [groupBlockquoteRuns] to nested blockquotes.
///
/// For a given level K (1-indexed), a level-K stripe must span every
/// consecutive line whose depth is `>= K` — not just lines whose depth
/// exactly equals K — matching GFM/GitHub nested-blockquote rendering: an
/// outer quote's border spans its entire range *including* any deeper-nested
/// content inside it, while an inner level's border only spans where that
/// deeper nesting actually continues. For example:
///
/// ```
/// > level 1 line
/// >> level 2 line
/// > level 1 again
/// ```
///
/// stripe-level-1 spans all three lines continuously, and stripe-level-2
/// spans only the middle line. Implemented as: for each level K from 1 to the
/// deepest depth present, filter to slots whose `element.indentLevel >= K`,
/// then merge consecutively-adjacent survivors exactly as [groupBlockquoteRuns]
/// does — adjacency is defined purely by source-line adjacency (one `\n`
/// apart), independent of the exact depth at each line, which is what gives
/// the correct per-level continuity without any special-casing.
///
/// The returned map's keys are the 1-indexed levels present among [slots].
/// Iterate them in ascending order to paint outermost stripes first (level 1
/// sits leftmost in the indent gutter).
Map<int, List<List<BlockquoteSlot>>> groupBlockquoteRunsByLevel(
  List<BlockquoteSlot> slots,
) {
  if (slots.isEmpty) return const {};
  var maxLevel = 0;
  for (final s in slots) {
    if (s.element.indentLevel > maxLevel) maxLevel = s.element.indentLevel;
  }
  final result = <int, List<List<BlockquoteSlot>>>{};
  for (var level = 1; level <= maxLevel; level++) {
    final runs = <List<BlockquoteSlot>>[];
    for (final slot in slots) {
      if (slot.element.indentLevel < level) continue;
      if (runs.isNotEmpty &&
          runs.last.last.element.end + 1 == slot.element.start) {
        runs.last.add(slot);
      } else {
        runs.add([slot]);
      }
    }
    if (runs.isNotEmpty) result[level] = runs;
  }
  return result;
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
// CheckboxSlot — carries one collapsed checkbox element for paint + tap.
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
/// [renderedStart] is the rendered offset of the first content character
/// following the checkbox marker — the same "content-start" position
/// [ListMarkerSlot] and [BlockquoteSlot] use. QuikiRenderEditor derives both
/// the box's vertical position (via a caret lookup on this offset) and its
/// horizontal position (the containing run's own content-start x, with the
/// box painted in the gutter immediately to its left) from this single
/// offset — there is no separate marker range to hit-test against (ADR-34
/// Fix 2): the box is no longer reserved as inline rendered characters, so
/// tap-to-toggle hit-tests the box's actual painted [Rect] instead. See
/// QuikiRenderEditor's shared box-rect helper, used by both paint and
/// `checkboxSourceOffsetForTap`.
class CheckboxSlot {
  const CheckboxSlot({
    required this.element,
    required this.renderedStart,
    required this.checked,
    required this.color,
  });

  final MdElement element;

  /// Rendered offset of the first content character following the checkbox
  /// marker (used only for vertical/run position lookup — see class doc).
  final int renderedStart;

  /// Whether this is a checked (vs unchecked) checkbox.
  final bool checked;

  /// The color to paint the box outline / checkmark in — matches the
  /// surrounding text color so it adapts to the active theme.
  final Color color;
}

// ---------------------------------------------------------------------------
// ListMarkerSlot — carries one collapsed ul/ol marker for paint (ADR-34
// Fix 2 / block_indentation.md).
// ---------------------------------------------------------------------------

/// Describes a collapsed unordered- or ordered-list marker that
/// QuikiRenderEditor must paint as a gutter decoration — not as inline
/// rendered characters, which only reserve width on a line's first visual
/// row and so cannot survive word-wrap (the same defect this fix's
/// [CheckboxSlot] redesign and Stage 1's [BlockquoteSlot] both address).
///
/// [element] is the parsed [MdElement] with kind [MdElKind.ul] or
/// [MdElKind.ol].
/// [renderedStart] is the rendered offset of the first content character
/// following the marker — see [CheckboxSlot.renderedStart] for how
/// QuikiRenderEditor uses it.
/// [label] is the literal text to paint: `'•'` for a ul bullet, or
/// `'$seqNum.'` for an ol marker (the GFM-compatible rendered sequence
/// number — see [MdElement.seqNum]).
class ListMarkerSlot {
  const ListMarkerSlot({
    required this.element,
    required this.renderedStart,
    required this.label,
    required this.style,
  });

  final MdElement element;

  /// Rendered offset of the first content character following the marker.
  final int renderedStart;

  /// The literal marker text to paint (`'•'` or `'$seqNum.'`).
  final String label;

  /// The text style to paint [label] in.
  final TextStyle style;
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
// RenderRun — a maximal span of the flat rendered text sharing one indent
// level (ADR-34 / block_indentation.md).
// ---------------------------------------------------------------------------

/// Describes one layout run: a maximal, contiguous range of the rendered
/// text (in rendered-offset space, matching [RenderModel.sourceToRendered] /
/// [RenderModel.renderedToSource]) whose source lines all share the same
/// [indentLevel].
///
/// General mechanism, not blockquote-specific — any block kind that sets
/// [MdElement.indentLevel] contributes to run boundaries the same way. A
/// document with no indented content produces exactly one run spanning
/// `[0, renderedLength)` at [indentLevel] 0, matching the pre-ADR-34
/// single-`TextPainter` behavior exactly.
///
/// [start] and [end] include each covered line's trailing newline character
/// (the rendered '\n', when one exists) — i.e. a run's range extends up to
/// (but not including) the next run's [start]. This keeps every rendered
/// offset in `[0, renderedLength]` covered by exactly one run (with the
/// renderedLength end-sentinel resolving into the last run), which is what
/// lets consumers do a single linear/binary search rather than special-case
/// the newline between two differently-indented lines.
class RenderRun {
  const RenderRun({
    required this.start,
    required this.end,
    required this.indentLevel,
    this.listMarker = false,
  });

  /// Rendered offset of the first character covered by this run.
  final int start;

  /// Rendered offset just past the last character covered by this run
  /// (exclusive).
  final int end;

  /// Indent depth shared by every source line in this run. 0 = no indent.
  final int indentLevel;

  /// True if every source line covered by this run carries a collapsed
  /// ul/ol/checkbox marker (ADR-34 Fix 2 / block_indentation.md).
  /// QuikiRenderEditor reserves extra gutter width for such a run — on top
  /// of the [indentLevel]-driven width reduction — so the marker (bullet
  /// dot, ordered-list number, or checkbox box) has somewhere to be painted
  /// without consuming any of the run's own content-start x, which must stay
  /// identical to a run with no marker at the same [indentLevel] (that x is
  /// what keeps every visual row — including the first — aligned; see
  /// block_indentation.md).
  ///
  /// Alongside [indentLevel], this DOES gate run merging in
  /// [RenderModel._computeRuns] (ADR-34 Fix 3): two adjacent lines only
  /// combine into one run when both their [indentLevel] AND their
  /// marker-bearing status agree. Earlier this was OR-merged onto a run
  /// after the fact instead — a marker-bearing line (ul/ol/checkbox) and a
  /// non-marker line (plain paragraph, blockquote, heading) sharing an
  /// [indentLevel] would merge into one run purely because the level
  /// matched, and the whole run — including the non-marker content, no
  /// matter how far from the actual list item — would incorrectly reserve
  /// the marker gutter and shift right. Gating the merge on this field too
  /// confines the gutter to lines that actually carry a marker (list items
  /// at the same [indentLevel] still merge into one run exactly as before,
  /// since they all report `true`; a blockquote line adjacent to a
  /// same-depth list item no longer merges with it, since one reports
  /// `false` and the other `true`).
  final bool listMarker;
}

// ---------------------------------------------------------------------------
// sliceTextSpan — extracts the rendered characters in [start, end) from a
// TextSpan produced by RenderModel.build(), preserving per-leaf styling.
// ---------------------------------------------------------------------------

/// Returns a new [TextSpan] containing only the rendered characters in
/// `[start, end)` of [span], preserving each leaf's style.
///
/// [span] must have the shape [RenderModel.build] always produces: either a
/// single flat span (`text` non-null, no children) or a flat list of leaf
/// `TextSpan` children (each with non-null `text` and no further nesting).
/// Any other shape is not supported.
///
/// Used by the render layer to build one narrower [TextPainter] per
/// [RenderRun] from slices of the single flat rendered TextSpan that
/// [RenderModel.build] already produces — the offset-mapping/inline-styling
/// machinery in [RenderModel] does not need to change for multi-run layout
/// (ADR-34); only this slicing step is new.
TextSpan sliceTextSpan(TextSpan span, int start, int end) {
  if (start >= end) return const TextSpan(text: '');
  final children = span.children;
  if (children == null || children.isEmpty) {
    final text = span.text ?? '';
    final s = start.clamp(0, text.length);
    final e = end.clamp(0, text.length);
    if (s >= e) return const TextSpan(text: '');
    return TextSpan(text: text.substring(s, e), style: span.style);
  }
  final out = <TextSpan>[];
  var leafStart = 0;
  for (final child in children) {
    final leaf = child as TextSpan;
    final text = leaf.text ?? '';
    final leafEnd = leafStart + text.length;
    if (leafEnd > start && leafStart < end) {
      final sliceStart = (start - leafStart).clamp(0, text.length);
      final sliceEnd = (end - leafStart).clamp(0, text.length);
      if (sliceStart < sliceEnd) {
        out.add(TextSpan(
          text: text.substring(sliceStart, sliceEnd),
          style: leaf.style,
        ));
      }
    }
    leafStart = leafEnd;
  }
  return TextSpan(children: out.isEmpty ? null : out);
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
    this.listMarkerSlots = const [],
    this.blockquoteSlots = const [],
    this.hrSlots = const [],
    this.runs = const [],
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

  /// Collapsed ul/ol marker elements (ADR-34 Fix 2 / block_indentation.md).
  /// QuikiRenderEditor uses this list to paint each item's bullet dot or
  /// ordered-list number as a gutter decoration, positioned independently of
  /// inline text flow so it survives word-wrap on every visual row.
  final List<ListMarkerSlot> listMarkerSlots;

  /// Collapsed blockquote elements.  QuikiRenderEditor uses this list to paint
  /// the left border stripe for each blockquote line.
  final List<BlockquoteSlot> blockquoteSlots;

  /// Collapsed horizontal rule elements.  QuikiRenderEditor uses this list to
  /// paint a thin horizontal line in place of the source text.
  final List<HrSlot> hrSlots;

  /// Layout run boundaries (ADR-34 / block_indentation.md), in ascending,
  /// non-overlapping, contiguous order — together they cover
  /// `[0, renderedLength]` (the end sentinel resolves into the last run).
  /// QuikiRenderEditor lays out one `TextPainter` per run, at a width reduced
  /// by and an X-offset derived from that run's [RenderRun.indentLevel].
  final List<RenderRun> runs;

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
    listMarkerSlots: const [],
    blockquoteSlots: const [],
    hrSlots: const [],
    // A single degenerate level-0 run so QuikiRenderEditor's run-resolution
    // logic never needs a special case for empty source — it always has at
    // least one run to lay out and place the caret in.
    runs: const [RenderRun(start: 0, end: 0, indentLevel: 0)],
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
    final listMarkers = <ListMarkerSlot>[];
    final blockquotes = <BlockquoteSlot>[];
    final hrs = <HrSlot>[];

    // Block elements (one per line, non-overlapping) and inline elements
    // (nested/overlapping) are handled separately. Blocks drive image / hr
    // handling and supply the per-line content base style; inline elements
    // nest and combine on top (ADR-33). List/checkbox/blockquote marker
    // decoration slots (bullet, ol number, checkbox box, stripe) are all
    // recorded in one post-pass below, once srcToRnd is complete — ADR-34
    // Fix 2 removed the inline collapsedMarker substitution these used to go
    // through here, since inline rendered characters only reserve width on a
    // line's first visual row (see block_indentation.md).
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

      // Reveal unit = the outermost element under the cursor (ADR-37 / #345).
      // For a marker-scoped block kind (list/checkbox/heading/blockquote —
      // see _isMarkerScopedBlock), the block counts as "covering" si only
      // while si is within its own marker span (si < _blockRevealEnd(block),
      // i.e. block.start + openDelimLen) — past the marker, the block plays
      // no further role and content defers entirely to whichever inline
      // element (if any) covers si, exactly as an unadorned paragraph line
      // already does. This is what stops the marker from dragging the whole
      // line's reveal boundary along with it. image/hr are unaffected: their
      // "marker" already spans openDelimLen == the entire line by design, so
      // _blockRevealEnd degenerates to the old block.end for them.
      final MdElement? effectiveBlock =
          (block != null && si < _blockRevealEnd(block)) ? block : null;
      final MdElement? topLevel =
          effectiveBlock ?? (active.isEmpty ? null : active.first);
      final int topLevelEnd = effectiveBlock != null
          ? _blockRevealEnd(effectiveBlock)
          : (topLevel == null ? 0 : topLevel.end);
      final revealed = topLevel != null &&
          cursorOffset >= topLevel.start &&
          cursorOffset <= topLevelEnd;

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

        // List/checkbox/blockquote marker decoration slots (bullet, ol
        // number, checkbox box, blockquote stripe) are all recorded in one
        // post-pass after the source → rendered map is complete (see below),
        // not here — recording at the first content char failed for an empty
        // blockquote, whose content position coincides with where the block
        // is retired from this loop (the off-by-one Stage 4 fixed), and the
        // same reasoning now applies uniformly to every marker kind (ADR-34
        // Fix 2). The marker's source delimiter characters are hidden by the
        // ordinary per-character delimiter-hiding path below (block
        // .isDelimiter), exactly like a heading's `#` prefix — no special
        // fast-forward is needed since no rendered characters are emitted
        // for the marker at all.
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
        // A literal tab character has no real tab-stop concept under
        // Flutter's TextPainter — it renders at whatever narrow width the
        // font's tab glyph happens to report, in practice roughly one
        // space-width, which reads as too narrow to see as an indent
        // (surfaced by ADR-34 Stage 4's Indent/Dedent, which can insert a
        // literal '\t' into visible text — see indent_dedent.dart). Substitute
        // any VISIBLE tab with [_tabSubstitute] (4 literal space characters)
        // of the same style: a 1-source-char -> N-rendered-char expansion, the
        // same "one source position needs special rendered treatment" shape
        // as the historical list/checkbox marker substitutions (see
        // MdElement.collapsedMarker) — every one of the N rendered positions
        // maps back to this tab's own source offset, so tap/caret lookups
        // anywhere inside the widened region resolve to the tab character
        // itself. Real (actual glyph) space characters guarantee the visual
        // width is exactly N times a single space glyph, regardless of font.
        //
        // This runs unconditionally in the shared visible-character path —
        // not gated on any MdElement — so it applies identically whether or
        // not markdown parsing ran at all: plain-text mode (whose elements
        // list is always empty; see QuikiEditorState.build) never populates
        // any element for a tab to be gated on, and a hidden (delimiter) tab,
        // e.g. a list item's leading indentation tab, never reaches this
        // branch in the first place (isDelimiter routes it to the invisible
        // path above), so list-item indentation is unaffected.
        final substitute = char == '\t' ? _tabSubstitute : char;

        // Group into a style run.
        if (charStyle != bufStyle) {
          flushBuf();
          bufStyle = charStyle;
        }
        bufText.write(substitute);
        for (var k = 0; k < substitute.length; k++) {
          rndToSrc.add(si);
        }
        ri += substitute.length;
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

    // Marker/decoration slots (post-pass, ADR-34). Recorded here, once
    // srcToRnd is complete, so the rendered content position can be read for
    // any block — including an empty blockquote or list item, whose content
    // position the per-character loop never reaches while the block is still
    // current (the off-by-one Stage 4 fixed for blockquote; the same
    // reasoning now covers every marker kind uniformly). renderedStart is the
    // rendered offset of the marker's own start — since the marker's source
    // characters are always hidden, this equals the first content
    // character's rendered offset. A revealed block (cursor anywhere on its
    // line) shows raw source and gets no slot, matching every other
    // element's reveal rule.
    for (final b in blocks) {
      // Narrowed to the marker's own span (ADR-37 / #345) — every kind
      // reaching this switch (blockquote/ul/ol/checkbox) is marker-scoped,
      // so this always resolves to b.start + b.openDelimLen, not b.end. See
      // _blockRevealEnd's doc for the full rationale.
      final revealed =
          cursorOffset >= b.start && cursorOffset <= _blockRevealEnd(b);
      if (revealed) continue;
      switch (b.kind) {
        case MdElKind.blockquote:
          blockquotes.add(BlockquoteSlot(
            element: b,
            renderedStart: srcToRnd[b.start],
            renderedEnd: srcToRnd[b.end],
          ));
        case MdElKind.ul:
          listMarkers.add(ListMarkerSlot(
            element: b,
            renderedStart: srcToRnd[b.start],
            label: '•',
            style: baseStyle,
          ));
        case MdElKind.ol:
          listMarkers.add(ListMarkerSlot(
            element: b,
            renderedStart: srcToRnd[b.start],
            label: '${b.seqNum}.',
            style: baseStyle,
          ));
        case MdElKind.checkboxUnchecked:
        case MdElKind.checkboxChecked:
          checkboxes.add(CheckboxSlot(
            element: b,
            renderedStart: srcToRnd[b.start],
            checked: b.kind == MdElKind.checkboxChecked,
            color: baseStyle.color ?? _foreground,
          ));
        default:
          break;
      }
    }

    // Layout runs (post-pass, ADR-34). One indent level per source line,
    // looked up via the now-complete srcToRnd map and merged into maximal
    // consecutive-same-level runs in rendered-offset space. A revealed block
    // (cursor inside — raw source visible, markers and leading whitespace
    // all shown as literal text) is treated as indentLevel 0: the source
    // itself already shows the nesting, so no additional layout indent
    // applies, and this also means a still-collapsed run above/below a
    // revealed line correctly breaks there (matching how it also gets no
    // blockquoteSlot / marker substitution while revealed). Applies uniformly
    // to every block kind that can set [MdElement.indentLevel] — blockquote
    // (Stage 1) and now ul/ol/checkbox (Stage 2+3, ADR-34) — since only those
    // kinds ever produce a non-zero value; headings/image/hr always report 0
    // regardless of reveal state, so no kind-specific branch is needed here.
    final runs = _computeRuns(
      source: source,
      blocks: blocks,
      cursorOffset: cursorOffset,
      srcToRnd: srcToRnd,
      renderedLength: ri,
    );

    return RenderModel._(
      textSpan: TextSpan(children: spans.isEmpty ? null : spans),
      renderedLength: ri,
      sourceToRendered: srcToRnd,
      renderedToSource: rndToSrc,
      imageSlots: slots,
      linkSlots: links,
      checkboxSlots: checkboxes,
      listMarkerSlots: listMarkers,
      blockquoteSlots: blockquotes,
      hrSlots: hrs,
      runs: runs,
    );
  }

  /// Computes [RenderRun] boundaries — see the field doc on [runs].
  ///
  /// Walks source lines independently of the main per-character loop (which
  /// has already finished and fully populated [srcToRnd] by the time this
  /// runs), determines each line's indent level, and merges consecutive
  /// lines sharing a level into one run. A run's rendered range includes each
  /// covered line's trailing newline (assigned to the *preceding* line, not
  /// the next), so runs are contiguous and non-overlapping.
  static List<RenderRun> _computeRuns({
    required String source,
    required List<MdElement> blocks,
    required int cursorOffset,
    required List<int> srcToRnd,
    required int renderedLength,
  }) {
    final lines = source.split('\n');
    final result = <RenderRun>[];
    var lineStart = 0;
    var bi = 0;
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      final thisLineStart = lineStart;
      final thisLineEnd = thisLineStart + line.length; // excludes trailing \n
      final isLast = li == lines.length - 1;
      // Rendered lookup boundary for "one past this line's content and its
      // trailing newline" — the next line's start, or the end sentinel for
      // the last line (which has no trailing '\n' to skip past).
      final nextLineSrcOffset = isLast ? source.length : thisLineEnd + 1;

      while (bi < blocks.length && blocks[bi].end < thisLineStart) {
        bi++;
      }
      final block = (bi < blocks.length && blocks[bi].start == thisLineStart)
          ? blocks[bi]
          : null;

      var level = 0;
      var listMarker = false;
      if (block != null) {
        // Narrowed to the marker's own span (ADR-37 / #345) — see
        // _blockRevealEnd's doc. Only matters functionally for blockquote/
        // ul/ol/checkbox (the only kinds that ever set indentLevel); headings
        // always report indentLevel 0 regardless, so this narrowing is a
        // no-op for them.
        final revealed = cursorOffset >= block.start &&
            cursorOffset <= _blockRevealEnd(block);
        if (!revealed) {
          level = block.indentLevel;
          listMarker = block.kind == MdElKind.ul ||
              block.kind == MdElKind.ol ||
              block.kind == MdElKind.checkboxUnchecked ||
              block.kind == MdElKind.checkboxChecked;
        }
      }

      final rStart = srcToRnd[thisLineStart];
      final rEnd = srcToRnd[nextLineSrcOffset];

      if (result.isNotEmpty &&
          result.last.indentLevel == level &&
          result.last.listMarker == listMarker) {
        // Both indentLevel AND listMarker must agree to merge (ADR-34 Fix 3)
        // — see the field doc on [RenderRun.listMarker] for why a
        // level-only match isn't sufficient: it let a marker-bearing line's
        // gutter reservation leak into adjacent same-level content that
        // carries no marker of its own.
        result[result.length - 1] = RenderRun(
          start: result.last.start,
          end: rEnd,
          indentLevel: level,
          listMarker: listMarker,
        );
      } else {
        result.add(RenderRun(
          start: rStart,
          end: rEnd,
          indentLevel: level,
          listMarker: listMarker,
        ));
      }

      lineStart = thisLineEnd + 1; // start of the next line; unused after last
    }
    return result;
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
// Tab rendering — file-private.
// ---------------------------------------------------------------------------

/// The literal replacement text for one visible source tab character — 4
/// literal space characters, so its rendered visual width is exactly 4x a
/// single space glyph at the active font size. See the substitution site in
/// [RenderModel.build] for the full rationale.
const String _tabSubstitute = '    ';

// ---------------------------------------------------------------------------
// Marker-scoped reveal (ADR-37 / #345) — file-private.
// ---------------------------------------------------------------------------

/// True for block kinds whose reveal is scoped to just the marker's own
/// source range rather than the whole line (ADR-37 / #345): list items,
/// checkboxes, headings, and blockquotes all have inline content sharing the
/// line with their marker, so only the marker itself should snap to raw
/// source when the cursor lands on it — the content should behave exactly
/// like an unadorned paragraph (deferring to whichever inline element, if
/// any, actually covers the cursor).
///
/// False for [MdElKind.image] and [MdElKind.hr]: neither has inline content
/// sharing the line with its marker — [MdElement.openDelimLen] is already
/// `end - start` (the entire line) for both — so the pre-ADR-37 whole-block
/// reveal is already correct for them and deliberately left unchanged.
bool _isMarkerScopedBlock(MdElKind kind) => switch (kind) {
      MdElKind.ul ||
      MdElKind.ol ||
      MdElKind.checkboxUnchecked ||
      MdElKind.checkboxChecked ||
      MdElKind.h1 ||
      MdElKind.h2 ||
      MdElKind.h3 ||
      MdElKind.h4 ||
      MdElKind.h5 ||
      MdElKind.h6 ||
      MdElKind.blockquote =>
        true,
      MdElKind.image ||
      MdElKind.hr ||
      MdElKind.bold ||
      MdElKind.italic ||
      MdElKind.strikethrough ||
      MdElKind.inlineCode ||
      MdElKind.link ||
      MdElKind.autolink ||
      MdElKind.escape =>
        false,
    };

/// The source offset up to which [block] itself counts as "covering" a
/// character for reveal purposes (ADR-37 / #345).
///
/// For a marker-scoped kind (see [_isMarkerScopedBlock]) this is just past
/// the marker's own characters — `block.start + block.openDelimLen`, which
/// [MdElement.openDelimLen] already computes correctly for every in-scope
/// kind, including the variable-length list/ol/checkbox/blockquote markers
/// (ADR-34's `srcMarkerLen` mechanism). Content past this point defers
/// entirely to inline elements for reveal, exactly like a plain paragraph.
///
/// For every other block kind (image, hr) this is simply [MdElement.end] —
/// unchanged pre-ADR-37 whole-line reveal, since neither has inline content
/// sharing the line with its marker in the first place.
int _blockRevealEnd(MdElement block) => _isMarkerScopedBlock(block.kind)
    ? block.start + block.openDelimLen
    : block.end;

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
      // Checked checkbox: content renders with strikethrough, mirroring the
      // literal ~~text~~ MdElKind.strikethrough case above. This is a pure
      // rendering affordance — the underlying '- [x] ' source is untouched;
      // toggling the checkbox back to unchecked (checkboxUnchecked, below)
      // restores unstyled content.
      MdElKind.checkboxChecked => base.copyWith(
          decoration: TextDecoration.lineThrough,
        ),
      // List kinds: content in baseStyle (marker substituted separately).
      // Image: revealed mode shows raw source in baseStyle.
      // Escape: the escaped character renders literally in the surrounding
      // style; the actual style comes from the ancestor combination, so base.
      MdElKind.ul ||
      MdElKind.ol ||
      MdElKind.checkboxUnchecked ||
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
  // Seed with any decoration [base] already carries (e.g. a checked
  // checkbox's block-level strikethrough, see _contentStyle) so a covering
  // inline element that also contributes a decoration (link underline,
  // nested ~~strikethrough~~) combines with it below instead of the final
  // copyWith silently discarding it.
  final decorations = <TextDecoration>[
    if (base.decoration != null && base.decoration != TextDecoration.none)
      base.decoration!,
  ];
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
