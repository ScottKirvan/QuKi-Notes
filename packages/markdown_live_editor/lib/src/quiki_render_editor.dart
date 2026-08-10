import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'render_model.dart';

// ---------------------------------------------------------------------------
// QuikiRenderWidget — LeafRenderObjectWidget
//
// Single responsibility: rendering. Passes state down to QuikiRenderEditor
// via createRenderObject / updateRenderObject. No input handling here.
// ---------------------------------------------------------------------------

class QuikiRenderWidget extends LeafRenderObjectWidget {
  const QuikiRenderWidget({
    super.key,
    required this.renderModel,
    required this.selection,
    required this.padding,
    required this.focused,
    required this.cursorColor,
    required this.selectionColor,
    this.imageCache = const {},
  });

  final RenderModel renderModel;
  final TextSelection selection;
  final EdgeInsets padding;
  final bool focused;
  final Color cursorColor;
  final Color selectionColor;

  /// Read-only snapshot of the image path → decoded [ui.Image] (or null for
  /// placeholder) cache maintained by [QuikiEditorState].
  final Map<String, ui.Image?> imageCache;

  @override
  QuikiRenderEditor createRenderObject(BuildContext context) {
    return QuikiRenderEditor(
      renderModel: renderModel,
      selection: selection,
      padding: padding,
      focused: focused,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
      imageCache: imageCache,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    QuikiRenderEditor renderObject,
  ) {
    renderObject
      ..renderModel = renderModel
      ..selection = selection
      ..padding = padding
      ..focused = focused
      ..cursorColor = cursorColor
      ..selectionColor = selectionColor
      ..imageCache = imageCache;
  }
}

// ---------------------------------------------------------------------------
// _RunLayout — one laid-out TextPainter for one RenderRun, plus its origin
// within this render object's own text-origin-relative coordinate space
// (ADR-34 / block_indentation.md). File-private to QuikiRenderEditor.
// ---------------------------------------------------------------------------

class _RunLayout {
  _RunLayout({
    required this.run,
    required this.painter,
    required this.x,
    required this.y,
  });

  final RenderRun run;
  final TextPainter painter;

  /// Horizontal origin — [run.indentLevel] * [QuikiRenderEditor._indentUnit].
  final double x;

  /// Vertical origin — the summed painter heights of every preceding run.
  final double y;
}

// ---------------------------------------------------------------------------
// QuikiRenderEditor — RenderBox
//
// Owns one TextPainter per layout run (ADR-34) instead of a single
// whole-document TextPainter. Paints selection highlight, text, caret, and
// images. No state, no TextInputConnection, no keyboard handling.
//
// Multi-run layout, in brief: RenderModel.build() already produces one flat
// rendered TextSpan plus RenderRun boundaries (maximal spans sharing one
// indent level). This render object slices that TextSpan per run
// (sliceTextSpan), lays each slice out at a width reduced by, and an X-offset
// derived from, that run's indent level, and stacks the runs vertically. A
// document with no indented content (indentLevel 0 throughout) always
// produces exactly one run spanning the whole document — identical, byte for
// byte, to the pre-ADR-34 single-TextPainter layout.
//
// Every public coordinate-mapping method keeps its exact pre-ADR-34 signature
// and coordinate semantics — one local space spanning the whole render
// object. Internally each gains one indirection step: resolve which run a
// rendered offset (or a tap/caret Y) falls into, delegate to that run's own
// TextPainter, then translate the result by the run's (x, y) origin.
// ---------------------------------------------------------------------------

/// Fixed height (in logical pixels) reserved for a collapsed image line when
/// the actual image is not yet loaded.  Once the image loads, the height
/// becomes aspect-ratio-correct based on the painted width.  Using a fixed
/// placeholder height avoids layout thrash when many images are loading.
const double _imagePlaceholderHeight = 200.0;

class QuikiRenderEditor extends RenderBox {
  QuikiRenderEditor({
    required RenderModel renderModel,
    required TextSelection selection,
    required EdgeInsets padding,
    required bool focused,
    required Color cursorColor,
    required Color selectionColor,
    Map<String, ui.Image?> imageCache = const {},
  })  : _renderModel = renderModel,
        _selection = selection,
        _padding = padding,
        _focused = focused,
        _cursorColor = cursorColor,
        _selectionColor = selectionColor,
        _imageCache = imageCache;

  RenderModel _renderModel;
  TextSelection _selection;
  EdgeInsets _padding;
  bool _focused;
  Color _cursorColor;
  Color _selectionColor;

  /// One laid-out TextPainter per [RenderModel.runs] entry, populated by
  /// [performLayout]. Always non-empty after the first layout pass —
  /// [RenderModel.build] guarantees at least one run, even for empty source.
  List<_RunLayout> _runLayouts = const [];

  /// Sum of every run painter's height — the real, wrap-correct total content
  /// height (excludes reserved image extra height; see [_totalImageExtraHeight]).
  double _totalTextHeight = 0.0;

  /// Read-only snapshot of the image cache from [QuikiEditorState].
  Map<String, ui.Image?> _imageCache;

  // -------------------------------------------------------------------------
  // Property setters — each marks the render object dirty as needed.
  // -------------------------------------------------------------------------

  RenderModel get renderModel => _renderModel;

  set renderModel(RenderModel m) {
    if (_renderModel == m) return;
    _renderModel = m;
    markNeedsLayout();
  }

  set selection(TextSelection s) {
    if (_selection == s) return;
    _selection = s;
    markNeedsPaint();
  }

  set padding(EdgeInsets p) {
    if (_padding == p) return;
    _padding = p;
    markNeedsLayout();
  }

  set focused(bool f) {
    if (_focused == f) return;
    _focused = f;
    markNeedsPaint();
  }

  set cursorColor(Color c) {
    if (_cursorColor == c) return;
    _cursorColor = c;
    markNeedsPaint();
  }

  set selectionColor(Color c) {
    if (_selectionColor == c) return;
    _selectionColor = c;
    markNeedsPaint();
  }

  set imageCache(Map<String, ui.Image?> cache) {
    // Reference equality is sufficient: QuikiEditorState always passes the
    // same map instance; when it calls setState() after a load completes the
    // build() pass creates a new QuikiRenderWidget with the updated map.
    if (identical(_imageCache, cache)) return;
    _imageCache = cache;
    markNeedsLayout();
  }

  // -------------------------------------------------------------------------
  // Image height helpers.
  // -------------------------------------------------------------------------

  /// Returns the height to reserve for [slot]'s image given the available
  /// [paintWidth].
  ///
  /// If the image is loaded and has known dimensions: aspect-ratio-correct
  /// height (= paintWidth * h / w).  Otherwise: fixed placeholder height.
  double _imageHeight(ImageSlot slot, double paintWidth) {
    final img = _imageCache[slot.element.imagePath];
    if (img != null && img.width > 0) {
      return paintWidth * img.height / img.width;
    }
    return _imagePlaceholderHeight;
  }

  /// Computes the total extra height added by collapsed image slots (i.e. the
  /// space no run's TextPainter can account for since image lines emit no
  /// chars). Images are always indentLevel 0 (Stage 1 does not nest them
  /// inside blockquotes — the parser doesn't support that combination), so
  /// this stays a flat document-wide total exactly as before ADR-34; it is
  /// not distributed per-run.
  double _totalImageExtraHeight(double paintWidth) {
    double extra = 0.0;
    for (final slot in _renderModel.imageSlots) {
      extra += _imageHeight(slot, paintWidth);
    }
    return extra;
  }

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  /// Horizontal space, in logical pixels, added per nesting level for an
  /// indented run and subtracted from that run's own available width. Chosen
  /// to approximate the ~1em content indent the (now-removed) blockquote
  /// blank-character reservation trick targeted — see ADR-34 /
  /// block_indentation.md. Exact pixel indent is a design choice, not a
  /// correctness invariant; device verification is still needed (see the
  /// spec's honest test-strategy note).
  static const double _indentUnit = 16.0;

  /// Extra horizontal space, in logical pixels, reserved for a list-kind
  /// marker (bullet dot, ordered-list number, or checkbox box) — on top of
  /// any [_indentUnit]-driven nesting-depth reduction — for a run whose
  /// [RenderRun.listMarker] is true (ADR-34 Fix 2 / block_indentation.md).
  /// The marker is painted in this gutter band, immediately to the left of
  /// the run's own content-start x, rather than as inline rendered
  /// characters — inline characters only reserve width on a line's first
  /// visual row, so a wrapped item's continuation rows snapped back to the
  /// un-indented margin (the same defect ADR-34 Stage 1 fixed for
  /// blockquotes). Sized generously enough for a two-digit ordered-list
  /// marker ("12.") or the checkbox box at typical body-text font sizes; an
  /// exact pixel value is a design choice, not a correctness invariant, and
  /// still needs device verification (see the spec's honest test-strategy
  /// note).
  static const double _listMarkerGutterWidth = 24.0;

  /// Gap, in logical pixels, between a painted marker (bullet, ol number, or
  /// checkbox box) and the content-start x it sits just to the left of.
  static const double _listMarkerContentGap = 4.0;

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth - _padding.horizontal;
    final paintWidth = maxWidth < 0 ? 0.0 : maxWidth;

    final runs = _renderModel.runs;
    final layouts = <_RunLayout>[];
    var y = 0.0;
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      final listGutter = run.listMarker ? _listMarkerGutterWidth : 0.0;
      final indentWidth = run.indentLevel * _indentUnit + listGutter;
      final runWidth = (paintWidth - indentWidth).clamp(0.0, paintWidth);
      // Every run except the last ends exactly at the trailing newline that
      // separates it from the next (differently-indented) run — see
      // RenderModel._computeRuns, which assigns each line's newline to the
      // line it terminates. That trailing '\n' must NOT be handed to this
      // run's own TextPainter: a string ending in '\n' lays out as if it had
      // one additional, empty trailing line, inflating this run's height by
      // a whole phantom row and pushing every following run's Y-origin down
      // by the same amount. The vertical separation between runs is already
      // achieved explicitly by this stacking loop (`y += painter.height`), so
      // the run doesn't need its own trailing newline to produce one — it is
      // sliced out here. sourceToRendered / renderedToSource are untouched;
      // the one rendered offset this trims (the newline itself) still
      // resolves correctly via _runForRendered's ordinary half-open-range
      // lookup, landing at this run's own local "end of text" position.
      final sliceEnd = i < runs.length - 1 ? run.end - 1 : run.end;
      final painter = TextPainter(
        text: sliceTextSpan(_renderModel.textSpan, run.start, sliceEnd),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: runWidth);
      layouts.add(_RunLayout(run: run, painter: painter, x: indentWidth, y: y));
      y += painter.height;
    }
    _runLayouts = layouts;
    _totalTextHeight = y;

    // Height = run content + reserved space for all collapsed image slots.
    // Image lines emit zero rendered chars in their own run, so we add back
    // the reserved height for each slot here (see _totalImageExtraHeight).
    final imageExtra = _totalImageExtraHeight(paintWidth);
    size = Size(
      constraints.maxWidth,
      _totalTextHeight + imageExtra + _padding.vertical,
    );
  }

  // -------------------------------------------------------------------------
  // Run resolution — the one indirection every coordinate-mapping method
  // gains under ADR-34. _runLayouts is always non-empty post-layout.
  // -------------------------------------------------------------------------

  /// The run containing rendered offset [ri]. Runs are sorted, non-overlapping
  /// half-open ranges covering `[0, renderedLength]` (the end sentinel,
  /// `ri == renderedLength`, resolves into the last run — there is no run
  /// whose own range starts there).
  _RunLayout _runForRendered(int ri) {
    for (final r in _runLayouts) {
      if (ri >= r.run.start && ri < r.run.end) return r;
    }
    return _runLayouts.last;
  }

  /// The run whose vertical band `[r.y, r.y + r.painter.height)` contains
  /// text-origin-relative Y coordinate [y]. Clamps to the first/last run when
  /// [y] falls outside the laid-out content (e.g. a tap below the last line).
  _RunLayout _runForLocalY(double y) {
    for (final r in _runLayouts) {
      if (y >= r.y && y < r.y + r.painter.height) return r;
    }
    if (_runLayouts.isNotEmpty && y < _runLayouts.first.y) {
      return _runLayouts.first;
    }
    return _runLayouts.last;
  }

  /// Local caret offset (relative to this render object's text origin, no
  /// padding) for rendered offset [ri] — resolves the containing run, asks
  /// that run's own TextPainter, then translates by the run's origin. Shared
  /// by the public [getOffsetForCaret] and by internal image/hr/checkbox
  /// paint-position lookups.
  Offset _caretOffsetForRendered(int ri) {
    final r = _runForRendered(ri);
    final localOff = ri - r.run.start;
    final o =
        r.painter.getOffsetForCaret(TextPosition(offset: localOff), Rect.zero);
    return Offset(r.x + o.dx, r.y + o.dy);
  }

  /// Rendered offset for a text-origin-relative tap/position [textOffset] —
  /// resolves which run's vertical band the position falls in, then
  /// delegates to that run's own TextPainter (translating both the query and
  /// the result by the run's origin).
  int _renderedOffsetForTextOffset(Offset textOffset) {
    final r = _runForLocalY(textOffset.dy);
    final localPos = r.painter
        .getPositionForOffset(Offset(textOffset.dx - r.x, textOffset.dy - r.y));
    return r.run.start + localPos.offset;
  }

  // -------------------------------------------------------------------------
  // Hit testing
  // -------------------------------------------------------------------------

  @override
  bool hitTestSelf(Offset position) => true;

  // -------------------------------------------------------------------------
  // Public helpers — used by QuikiEditorState for input handling.
  //
  // Every method below keeps its pre-ADR-34 signature and coordinate
  // semantics exactly (a single local coordinate space spanning the whole
  // render object) — quiki_editor.dart's calling code is unchanged.
  // -------------------------------------------------------------------------

  /// Maps a local tap offset (relative to this render object's top-left) to a
  /// source TextPosition in the buffer.
  ///
  /// If the tap lands inside a collapsed image rect, the cursor is placed at
  /// whichever source boundary (element.start or element.end) is nearer the
  /// tap's x-coordinate — consistent with ADR-31's tap-to-source-character
  /// rule for non-text rendered content.
  TextPosition positionForOffset(Offset localPosition) {
    final textOffset = localPosition - _padding.topLeft;
    final paintWidth = constraints.maxWidth - _padding.horizontal;

    // Check whether the tap hits a collapsed image rect. Images are always
    // indentLevel 0, so their rect spans the full paint width from x = 0.
    double imageYOffset = 0.0;
    for (final slot in _renderModel.imageSlots) {
      final el = slot.element;
      final imgHeight = _imageHeight(slot, paintWidth);
      final textCaretOff = _caretOffsetForRendered(slot.renderedCharOffset);
      final imageTop = textCaretOff.dy + imageYOffset;
      final imageRect = Rect.fromLTWH(0, imageTop, paintWidth, imgHeight);

      if (imageRect.contains(textOffset)) {
        // Tap is inside this image rect.  Place cursor at the nearer boundary.
        final midX = imageRect.width / 2;
        final srcOff = textOffset.dx < midX ? el.start : el.end;
        return TextPosition(offset: srcOff);
      }

      imageYOffset += imgHeight;
    }

    // Normal text-position mapping.
    final ri = _renderedOffsetForTextOffset(textOffset);
    final sourceOffset = _renderModel.sourceForRendered(ri);
    return TextPosition(offset: sourceOffset);
  }

  /// Maps a source TextPosition to a canvas offset relative to the text origin
  /// (does NOT include padding — callers add padding.topLeft as needed).
  Offset getOffsetForCaret(TextPosition position) {
    final rOff = _renderModel.renderedForSource(position.offset);
    return _caretOffsetForRendered(rOff);
  }

  /// Maps a canvas offset (relative to text origin, no padding) to a
  /// source TextPosition.
  TextPosition getPositionForOffset(Offset textOffset) {
    final ri = _renderedOffsetForTextOffset(textOffset);
    final sourceOffset = _renderModel.sourceForRendered(ri);
    return TextPosition(offset: sourceOffset);
  }

  /// The bounding [Rect] (text-origin-relative local coordinates — no
  /// padding, no canvas/scroll offset, matching [getOffsetForCaret]'s own
  /// convention) of the VISUAL (soft-wrapped) line containing rendered
  /// offset [ri].
  ///
  /// Used by the Stage 4 magnifier (notes/dev/selection.md §3) to lock its
  /// vertical position to the current line's center and to clamp its
  /// horizontal tracking so it never samples content past that line's own
  /// actual left/right edges. This is a visual/wrapped line, not a source
  /// markdown "line" and not a whole [RenderRun] — a run's own TextPainter
  /// may itself wrap into several visual lines (ADR-34), and
  /// [TextPainter.getLineBoundary] resolves exactly the one containing [ri].
  Rect lineBoundsForRendered(int ri) {
    final r = _runForRendered(ri);
    final localLen = r.run.end - r.run.start;
    final localOff = (ri - r.run.start).clamp(0, localLen);
    final lineRange = r.painter.getLineBoundary(TextPosition(offset: localOff));
    final boxes = r.painter.getBoxesForSelection(
      TextSelection(baseOffset: lineRange.start, extentOffset: lineRange.end),
      boxHeightStyle: ui.BoxHeightStyle.tight,
    );
    if (boxes.isEmpty) {
      // An empty visual line (e.g. a blank source line) has no glyph boxes —
      // fall back to the caret's own position with zero width, the same
      // fallback _slotVerticalExtent uses for the same reason.
      final caret = r.painter
          .getOffsetForCaret(TextPosition(offset: localOff), Rect.zero);
      return Rect.fromLTWH(
        r.x + caret.dx,
        r.y + caret.dy,
        0,
        r.painter.preferredLineHeight,
      );
    }
    var left = boxes.first.left;
    var right = boxes.first.right;
    var top = boxes.first.top;
    var bottom = boxes.first.bottom;
    for (final b in boxes) {
      if (b.left < left) left = b.left;
      if (b.right > right) right = b.right;
      if (b.top < top) top = b.top;
      if (b.bottom > bottom) bottom = b.bottom;
    }
    return Rect.fromLTRB(r.x + left, r.y + top, r.x + right, r.y + bottom);
  }

  /// The preferred line height, from the first run's TextPainter.
  ///
  /// A pre-existing simplification (unchanged by ADR-34): callers (arrow-key
  /// line-to-line movement) already treat the whole document as having one
  /// uniform line height, regardless of cursor position — e.g. a heading line
  /// and a paragraph line already used the same single value pre-ADR-34, from
  /// the one whole-document TextPainter. For an indentLevel-0-only document
  /// there is exactly one run (identical to the pre-ADR-34 single painter),
  /// so this is byte-identical to before in the common case.
  double get preferredLineHeight => _runLayouts.isNotEmpty
      ? _runLayouts.first.painter.preferredLineHeight
      : 0.0;

  /// The total painted text height across all runs (without padding, without
  /// reserved image extra height) — the real, wrap-correct sum of every run's
  /// height.
  double get textHeight => _totalTextHeight;

  /// The padding insets configured for this editor.
  EdgeInsets get localPadding => _padding;

  /// Returns the URL of the collapsed link at [localPosition], or null if the
  /// tap does not hit any collapsed link.
  ///
  /// Hit-tests by mapping the tap to a rendered offset and checking whether
  /// that offset falls within the [renderedStart, renderedEnd) range of any
  /// collapsed [LinkSlot].
  String? linkUrlForOffset(Offset localPosition) {
    final textOffset = localPosition - _padding.topLeft;
    final ri = _renderedOffsetForTextOffset(textOffset);
    for (final slot in _renderModel.linkSlots) {
      if (ri >= slot.renderedStart && ri < slot.renderedEnd) {
        return slot.element.url;
      }
    }
    return null;
  }

  /// Returns the source offset of the collapsed checkbox element whose tap
  /// zone contains [localPosition], or null if the tap does not hit any
  /// checkbox's zone.
  ///
  /// Hit-tests against [_checkboxHitTestRect], a widened zone anchored on the
  /// box's actual painted [Rect] (#352) — not the painted box itself, which
  /// has zero margin and is extremely hard to tap precisely. Returns
  /// [element.start] of the matching slot so the caller can locate the marker
  /// in the source.
  int? checkboxSourceOffsetForTap(Offset localPosition) {
    final textOffset = localPosition - _padding.topLeft;
    for (final slot in _renderModel.checkboxSlots) {
      if (_checkboxHitTestRect(slot).contains(textOffset)) {
        return slot.element.start;
      }
    }
    return null;
  }

  /// The vertical (row-top-relative) Y offset at which to position a
  /// gutter-decoration marker (checkbox box, or bullet/ol-number label) of
  /// [contentHeight] within a row whose text painter reports
  /// [lineHeight] — shared by [_checkboxLocalRect] and
  /// [_listMarkerLabelOffset] so every marker kind aligns to the same
  /// baseline (ADR-34 Fix 3).
  ///
  /// Plain centering (`(lineHeight - contentHeight) / 2`) sits noticeably
  /// higher than the visible glyph ink on an adjacent line of body text,
  /// because this editor renders at `height: 1.4` — `preferredLineHeight`
  /// reports the full multiplied line-box height, most of which sits below
  /// the actual glyphs, not evenly split above and below them. The
  /// `+ lineHeight / 3` term is the empirically-tuned downward nudge #267
  /// already established for the checkbox box; applying the exact same
  /// nudge here (previously the bullet/ol-number label used plain centering
  /// with no nudge at all) is what makes a bullet dot or ol number line up
  /// with body text and with a checkbox box on an adjacent line, instead of
  /// rendering visibly higher than both.
  @visibleForTesting
  static double markerVerticalOffset(double lineHeight, double contentHeight) =>
      (lineHeight - contentHeight) / 2 + lineHeight / 3;

  /// The checkbox box's [Rect] for [slot], in text-origin-relative local
  /// coordinates (no padding, no canvas offset) — shared by [paint] and
  /// [_checkboxHitTestRect] (the latter widens it for tap purposes only; the
  /// painted glyph itself always matches this rect exactly, ADR-34 Fix 2).
  ///
  /// The box sits in [slot]'s containing run's list-marker gutter,
  /// immediately to the left of that run's own content-start x
  /// ([_RunLayout.x]) — the same position [_listMarkerLabelOffset] anchors a
  /// bullet/ol-number label against. Vertical position and [boxSize] mirror
  /// the pre-Fix-2 formula exactly (only the horizontal anchor changed, from
  /// the removed inline marker reservation to the run's content-start x).
  Rect _checkboxLocalRect(CheckboxSlot slot) {
    final r = _runForRendered(slot.renderedStart);
    // _caretOffsetForRendered already returns a GLOBAL (whole-render-object,
    // text-origin-relative) offset — it has already added r.y internally —
    // so it must NOT be added to r.y again here.
    final caretOffset = _caretOffsetForRendered(slot.renderedStart);
    final lineHeight = r.painter.preferredLineHeight;
    final boxSize = lineHeight * 0.8;
    final gutterRight = r.x;
    return Rect.fromLTWH(
      gutterRight - _listMarkerContentGap - boxSize,
      caretOffset.dy + markerVerticalOffset(lineHeight, boxSize),
      boxSize,
      boxSize,
    );
  }

  /// The checkbox's tap **hit-test** [Rect] for [slot] — wider than the
  /// painted glyph itself ([_checkboxLocalRect]), used only by
  /// [checkboxSourceOffsetForTap] (#352, round 2). [paint] never uses this
  /// rect, so the visible box size is unaffected — this widens only what
  /// counts as "close enough" to register a tap.
  ///
  /// Round 1 (#352) bounded the widened zone's left edge to
  /// `r.x - _listMarkerGutterWidth` — the reserved list-marker gutter's own
  /// left edge. That is only equal to this ROW's true left edge when
  /// [RenderRun.indentLevel] is 0: [_RunLayout.x] (`r.x`, aliased here as
  /// [gutterRight]) is computed in [performLayout] as an ABSOLUTE offset from
  /// this render object's own text origin (`run.indentLevel * _indentUnit +
  /// listGutter`), not incrementally stacked from a parent run's own x — so
  /// for an indented (nested list/checkbox) run, `r.x - _listMarkerGutterWidth`
  /// still leaves a dead zone `indentLevel * _indentUnit` pixels wide between
  /// the row's actual left edge (local x = 0, same physical margin every run
  /// shares) and the start of round 1's zone. That dead band grows with
  /// nesting depth, which is why round 1's fix read as having little to no
  /// effect for nested checkboxes on-device even though it measurably widened
  /// the top-level case.
  ///
  /// The fix: anchor the left edge at this ROW's own true left edge (local
  /// x = 0) instead of a gutter-relative offset. The right edge stays at this
  /// run's content-start x ([_RunLayout.x]), which already folds in
  /// [_listMarkerContentGap] (the small gap between the box and the text) —
  /// matching #352's restated requirement: the entire leading
  /// whitespace/marker region of the row, from its true start through to
  /// just before the visible text, is one tap target. For a non-nested
  /// (indentLevel 0) run this is numerically identical to round 1's zone
  /// (content-start x IS the gutter width there), so the top-level case is
  /// unchanged in geometry — round 1's own zone there was already anchored at
  /// the row's true left edge; the narrowness reported on-device is inherent
  /// to a ~24px-wide target, not a further geometry bug this round addresses.
  ///
  /// Safe from collision with other content: each [RenderRun] owns an
  /// exclusive vertical band (no other run's TextPainter, marker, or
  /// checkbox paints inside `[box.top, box.bottom)` for THIS slot's line —
  /// see [_checkboxLocalRect]'s and [_listMarkerLabelOffset]'s Y derivation,
  /// both keyed to the specific slot/line, never to a whole run), so widening
  /// the X range up to local 0 cannot bleed into a shallower ancestor's own
  /// content — an ancestor list item is always a DIFFERENT source line, hence
  /// a different (non-overlapping) Y band, never the same row.
  ///
  /// Vertical extent is left identical to [_checkboxLocalRect] — the bug
  /// report and the box's own vertical placement (already tuned by #267) are
  /// unrelated to this widening, and leaving it untouched guarantees this
  /// zone can never reach into an adjacent line's own checkbox hit zone.
  Rect _checkboxHitTestRect(CheckboxSlot slot) {
    final r = _runForRendered(slot.renderedStart);
    final box = _checkboxLocalRect(slot);
    final gutterRight = r.x;
    return Rect.fromLTRB(0, box.top, gutterRight, box.bottom);
  }

  /// The top-left [Offset] to paint a [ListMarkerSlot]'s [label] at, in
  /// text-origin-relative local coordinates (no padding, no canvas offset) —
  /// right-aligned within the run's list-marker gutter, [_listMarkerContentGap]
  /// pixels before its content-start x, and vertically aligned with body text
  /// and the checkbox box via [markerVerticalOffset] (ADR-34 Fix 3).
  /// [labelPainter] must already be laid out.
  Offset _listMarkerLabelOffset(ListMarkerSlot slot, TextPainter labelPainter) {
    final r = _runForRendered(slot.renderedStart);
    // _caretOffsetForRendered already returns a GLOBAL (whole-render-object,
    // text-origin-relative) offset — see the matching note in
    // [_checkboxLocalRect] — so it must NOT be added to r.y again here.
    final caretOffset = _caretOffsetForRendered(slot.renderedStart);
    final lineHeight = r.painter.preferredLineHeight;
    final labelRight = r.x - _listMarkerContentGap;
    return Offset(
      labelRight - labelPainter.width,
      caretOffset.dy + markerVerticalOffset(lineHeight, labelPainter.height),
    );
  }

  // -------------------------------------------------------------------------
  // Blockquote stripe vertical-extent helper.
  // -------------------------------------------------------------------------

  /// Vertical extent (top, bottom), in text-origin-relative Y (no padding, no
  /// canvas offset), of a single blockquote slot's rendered content.
  ///
  /// A slot's rendered range always lies entirely within one run (a slot
  /// corresponds to exactly one source line, and layout runs are grouped by
  /// exact per-line indent level match — see [RenderModel._computeRuns]), so
  /// this resolves the slot's containing run once via [slot.renderedStart]
  /// and asks only that run's own TextPainter.
  ///
  /// Uses glyph bounding boxes (BoxHeightStyle.tight) rather than a caret's
  /// line-box position — getOffsetForCaret returns the top of the *line box*,
  /// which sits above the visible glyph ink when line height > 1.0 (this
  /// editor uses 1.4), so a caret-derived stripe would read as too high. Falls
  /// back to a caret + one line height when the selection is degenerate
  /// (empty blockquote content), matching the pre-ADR-34 fallback.
  ({double top, double bottom}) _slotVerticalExtent(BlockquoteSlot slot) {
    final r = _runForRendered(slot.renderedStart);
    final localStart = slot.renderedStart - r.run.start;
    final localEnd = slot.renderedEnd - r.run.start;
    final boxes = r.painter.getBoxesForSelection(
      TextSelection(baseOffset: localStart, extentOffset: localEnd),
      boxHeightStyle: ui.BoxHeightStyle.tight,
    );
    if (boxes.isNotEmpty) {
      var minTop = boxes.first.top;
      var maxBottom = boxes.first.bottom;
      for (final b in boxes) {
        if (b.top < minTop) minTop = b.top;
        if (b.bottom > maxBottom) maxBottom = b.bottom;
      }
      return (top: r.y + minTop, bottom: r.y + maxBottom);
    }
    final caret = r.painter
        .getOffsetForCaret(TextPosition(offset: localStart), Rect.zero);
    final top = r.y + caret.dy;
    return (top: top, bottom: top + r.painter.preferredLineHeight);
  }

  // -------------------------------------------------------------------------
  // Paint
  // -------------------------------------------------------------------------

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final textOrigin = offset + _padding.topLeft;
    final paintWidth = constraints.maxWidth - _padding.horizontal;

    // Draw selection highlight boxes. A selection may span multiple runs
    // (e.g. from inside a blockquote to a plain line below it), so it is
    // clipped and painted per-run rather than in one getBoxesForSelection
    // call.
    final sel = _selection;
    if (sel.isValid && !sel.isCollapsed) {
      final rStart = _renderModel.renderedForSource(sel.start);
      final rEnd = _renderModel.renderedForSource(sel.end);
      final highlightPaint = Paint()
        ..color = _selectionColor
        ..style = PaintingStyle.fill;
      for (final r in _runLayouts) {
        final segStart = rStart > r.run.start ? rStart : r.run.start;
        final segEnd = rEnd < r.run.end ? rEnd : r.run.end;
        if (segStart >= segEnd) continue;
        final boxes = r.painter.getBoxesForSelection(
          TextSelection(
            baseOffset: segStart - r.run.start,
            extentOffset: segEnd - r.run.start,
          ),
        );
        final runOrigin = textOrigin + Offset(r.x, r.y);
        for (final box in boxes) {
          canvas.drawRect(box.toRect().shift(runOrigin), highlightPaint);
        }
      }
    }

    // Draw text — one run at a time, each at its own (x, y) origin.
    for (final r in _runLayouts) {
      r.painter.paint(canvas, textOrigin + Offset(r.x, r.y));
    }

    // Draw blockquote left border stripes — one stripe per active nesting
    // level, with per-level continuity (ADR-34): a level-K stripe spans every
    // consecutive line whose depth is >= K, not just lines with exactly
    // matching depth. Level 1 sits leftmost in the indent gutter; deeper
    // levels sit progressively further right; content starts just past the
    // deepest active level for that line (that line's own run X-offset).
    //
    // The stripe is painted in the content's own indent gutter, gapPx to the
    // left of that level's own column, instead of directly over the first
    // glyph — like GitHub's border-then-gap-then-text. Revealed blockquote
    // lines carry no slot (they show raw source at indentLevel 0), so a run
    // naturally breaks around them, same as the pre-ADR-34 single-level case.
    const Color blockquoteBorderColor = Color(0xFF7A828E);
    const double blockquoteStripeWidth = 3.0;
    const double blockquoteLevelGap = 4.0;
    final grouped = groupBlockquoteRunsByLevel(_renderModel.blockquoteSlots);
    final levels = grouped.keys.toList()..sort();
    for (final level in levels) {
      for (final stripeRun in grouped[level]!) {
        double? top;
        double? bottom;
        for (final slot in stripeRun) {
          final ext = _slotVerticalExtent(slot);
          top = (top == null || ext.top < top) ? ext.top : top;
          bottom =
              (bottom == null || ext.bottom > bottom) ? ext.bottom : bottom;
        }
        if (top == null || bottom == null) continue; // unreachable (>=1 slot)

        final stripeX =
            textOrigin.dx + (level - 1) * _indentUnit + blockquoteLevelGap;
        canvas.drawRect(
          Rect.fromLTRB(
            stripeX,
            textOrigin.dy + top,
            stripeX + blockquoteStripeWidth,
            textOrigin.dy + bottom,
          ),
          Paint()
            ..color = blockquoteBorderColor
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Draw horizontal rules for collapsed hr slots. Always indentLevel 0
    // (hr detection isn't reachable inside a blockquote — the parser treats
    // any '>'-prefixed line as blockquote content first), so the line spans
    // the full paint width exactly as before ADR-34.
    const Color hrColor = Color(0xFF9EA7B4);
    for (final hr in _renderModel.hrSlots) {
      final el = hr.element;
      final cursorSrc = sel.isValid ? sel.baseOffset : -1;
      final revealed = cursorSrc >= el.start && cursorSrc <= el.end;
      if (revealed) continue;

      final caretOffset = _caretOffsetForRendered(hr.renderedCharOffset);
      final lineHeight =
          _runForRendered(hr.renderedCharOffset).painter.preferredLineHeight;
      // Horizontal line at vertical midpoint of the line.
      final midY = textOrigin.dy + caretOffset.dy + lineHeight / 2;
      canvas.drawLine(
        Offset(textOrigin.dx, midY),
        Offset(textOrigin.dx + paintWidth, midY),
        Paint()
          ..color = hrColor
          ..strokeWidth = 1.0,
      );
    }

    // Draw checkbox glyphs for collapsed checkbox slots.
    //
    // Painted directly via Canvas rather than as a Unicode text glyph: on
    // Android, font-fallback shaping resolves a font per text run (not per
    // character), so a checked-box glyph can render as a large colour emoji
    // or a small monochrome symbol depending on what precedes it in the same
    // document — see #267. Drawing the box/checkmark ourselves sidesteps
    // font fallback entirely and guarantees consistent, theme-aware output.
    //
    // The box is positioned via [_checkboxLocalRect] — the run's own
    // content-start x, shifted left into the list-marker gutter — rather than
    // the removed inline blank-character marker reservation (ADR-34 Fix 2),
    // so it now correctly tracks a nested (indented) checkbox's run just like
    // the bullet/ol-number labels below.
    for (final cb in _renderModel.checkboxSlots) {
      final el = cb.element;
      final cursorSrc = sel.isValid ? sel.baseOffset : -1;
      final revealed = cursorSrc >= el.start && cursorSrc <= el.end;
      if (revealed) continue;

      final boxRect = _checkboxLocalRect(cb).shift(textOrigin);
      final rrect = RRect.fromRectAndRadius(
          boxRect, Radius.circular(boxRect.width * 0.2));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = cb.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      if (cb.checked) {
        final path = Path()
          ..moveTo(boxRect.left + boxRect.width * 0.2,
              boxRect.top + boxRect.height * 0.52)
          ..lineTo(boxRect.left + boxRect.width * 0.42,
              boxRect.top + boxRect.height * 0.74)
          ..lineTo(boxRect.left + boxRect.width * 0.82,
              boxRect.top + boxRect.height * 0.28);
        canvas.drawPath(
          path,
          Paint()
            ..color = cb.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // Draw bullet dots / ordered-list numbers for collapsed ul/ol markers.
    //
    // Painted as a gutter decoration via a one-off TextPainter per label,
    // right-aligned against the run's own content-start x (the same anchor
    // the checkbox box above uses) — not as inline rendered characters
    // (ADR-34 Fix 2): inline characters only reserve width on a line's first
    // visual row, so a wrapped item's continuation rows snapped back to the
    // un-indented margin.
    for (final marker in _renderModel.listMarkerSlots) {
      final el = marker.element;
      final cursorSrc = sel.isValid ? sel.baseOffset : -1;
      final revealed = cursorSrc >= el.start && cursorSrc <= el.end;
      if (revealed) continue;

      final labelPainter = TextPainter(
        text: TextSpan(text: marker.label, style: marker.style),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final labelOffset =
          _listMarkerLabelOffset(marker, labelPainter) + textOrigin;
      labelPainter.paint(canvas, labelOffset);
    }

    // Draw images (or placeholders) for collapsed image slots.
    //
    // Each image slot corresponds to a line that emits no rendered characters.
    // Its own run's TextPainter gives such a line zero height. We look up the
    // rendered char offset of each slot via the run-resolved caret position,
    // then paint the image or placeholder rect at that Y.
    //
    // We track a cumulative vertical offset [imageYOffset] to account for the
    // extra height we added for previously-painted slots (since no run's
    // TextPainter is aware of image heights, all subsequent slots are shifted
    // down by the sum of heights of all image slots above them). This is the
    // exact pre-ADR-34 approach, carried over unchanged — images stay out of
    // scope for this stage (always indentLevel 0), so their interaction with
    // surrounding content is neither improved nor regressed here.
    double imageYOffset = 0.0;
    for (final slot in _renderModel.imageSlots) {
      // Skip revealed elements: the raw source text is already visible via
      // the containing run's TextPainter and no separate image painting is
      // needed.
      final el = slot.element;
      final cursorSrc = sel.isValid ? sel.baseOffset : -1;
      final revealed = cursorSrc >= el.start && cursorSrc <= el.end;
      if (revealed) {
        // Even though we skip painting, we still account for the height of
        // revealed image lines.  In practice a revealed image line IS painted
        // by its run's TextPainter (raw source chars are visible), and the
        // layout step reserved placeholder height for it.  We skip both
        // painting and the offset accumulation here because the TextPainter
        // already placed those characters at the correct Y position.
        continue;
      }

      final imgHeight = _imageHeight(slot, paintWidth);
      final textCaretOff = _caretOffsetForRendered(slot.renderedCharOffset);

      // The actual top-left of the image rect in canvas space.
      final imageTop = textOrigin.dy + textCaretOff.dy + imageYOffset;
      final imageRect = Rect.fromLTWH(
        textOrigin.dx,
        imageTop,
        paintWidth,
        imgHeight,
      );

      final img = _imageCache[el.imagePath];
      if (img != null) {
        // Paint the loaded image scaled to fit the editor width while
        // preserving the aspect ratio.
        final srcRect = Rect.fromLTWH(
          0,
          0,
          img.width.toDouble(),
          img.height.toDouble(),
        );
        canvas.drawImageRect(img, srcRect, imageRect, Paint());
      } else {
        // Placeholder: a muted gray rect.
        final placeholderPaint = Paint()
          ..color = const Color(0xFFBDBDBD)
          ..style = PaintingStyle.fill;
        canvas.drawRect(imageRect, placeholderPaint);
      }

      imageYOffset += imgHeight;
    }

    // Draw caret when focused and selection is collapsed.
    if (_focused && sel.isValid && sel.isCollapsed) {
      final rOff = _renderModel.renderedForSource(sel.baseOffset);
      final r = _runForRendered(rOff);
      final localOff = rOff - r.run.start;
      final caretOffset = r.painter
          .getOffsetForCaret(TextPosition(offset: localOff), Rect.zero);
      final caretHeight = r.painter
          .getFullHeightForCaret(TextPosition(offset: localOff), Rect.zero);
      final caretRect = Rect.fromLTWH(
        textOrigin.dx + r.x + caretOffset.dx,
        textOrigin.dy + r.y + caretOffset.dy,
        2.0,
        caretHeight,
      );
      final caretPaint = Paint()
        ..color = _cursorColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(caretRect, caretPaint);
    }
  }
}
