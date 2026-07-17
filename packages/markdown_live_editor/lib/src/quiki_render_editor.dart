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
// QuikiRenderEditor — RenderBox
//
// Owns a TextPainter. Paints selection highlight, text, caret, and images.
// No state, no TextInputConnection, no keyboard handling.
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
        _imageCache = imageCache {
    _textPainter = TextPainter(
      text: renderModel.textSpan,
      textDirection: ui.TextDirection.ltr,
    );
  }

  RenderModel _renderModel;
  TextSelection _selection;
  EdgeInsets _padding;
  bool _focused;
  Color _cursorColor;
  Color _selectionColor;
  late TextPainter _textPainter;

  /// Read-only snapshot of the image cache from [QuikiEditorState].
  Map<String, ui.Image?> _imageCache;

  // -------------------------------------------------------------------------
  // Property setters — each marks the render object dirty as needed.
  // -------------------------------------------------------------------------

  RenderModel get renderModel => _renderModel;

  set renderModel(RenderModel m) {
    if (_renderModel == m) return;
    _renderModel = m;
    _textPainter.text = m.textSpan;
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
  /// space the TextPainter cannot account for since image lines emit no chars).
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

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth - _padding.horizontal;
    final paintWidth = maxWidth < 0 ? 0.0 : maxWidth;
    _textPainter.layout(maxWidth: paintWidth);
    final textHeight = _textPainter.height;
    // Height = text content + reserved space for all collapsed image slots.
    // The TextPainter gives image lines zero height (they emit no chars), so
    // we add back the reserved height for each slot here.
    final imageExtra = _totalImageExtraHeight(paintWidth);
    size = Size(
      constraints.maxWidth,
      textHeight + imageExtra + _padding.vertical,
    );
  }

  // -------------------------------------------------------------------------
  // Hit testing
  // -------------------------------------------------------------------------

  @override
  bool hitTestSelf(Offset position) => true;

  // -------------------------------------------------------------------------
  // Public helpers — used by QuikiEditorState for input handling.
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

    // Check whether the tap hits a collapsed image rect.
    double imageYOffset = 0.0;
    for (final slot in _renderModel.imageSlots) {
      final el = slot.element;
      final imgHeight = _imageHeight(slot, paintWidth);
      final renderedOff = slot.renderedCharOffset;
      final textCaretOff = _textPainter.getOffsetForCaret(
        TextPosition(offset: renderedOff),
        Rect.zero,
      );
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
    final renderedPos = _textPainter.getPositionForOffset(textOffset);
    final sourceOffset = _renderModel.sourceForRendered(renderedPos.offset);
    return TextPosition(offset: sourceOffset);
  }

  /// Maps a source TextPosition to a canvas offset relative to the text origin
  /// (does NOT include padding — callers add padding.topLeft as needed).
  Offset getOffsetForCaret(TextPosition position) {
    final rOff = _renderModel.renderedForSource(position.offset);
    return _textPainter.getOffsetForCaret(
      TextPosition(offset: rOff),
      Rect.zero,
    );
  }

  /// Maps a canvas offset (relative to text origin, no padding) to a
  /// source TextPosition.
  TextPosition getPositionForOffset(Offset textOffset) {
    final renderedPos = _textPainter.getPositionForOffset(textOffset);
    final sourceOffset = _renderModel.sourceForRendered(renderedPos.offset);
    return TextPosition(offset: sourceOffset);
  }

  /// The preferred line height from the TextPainter.
  double get preferredLineHeight => _textPainter.preferredLineHeight;

  /// The total painted text height (without padding).
  double get textHeight => _textPainter.height;

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
    final renderedPos = _textPainter.getPositionForOffset(textOffset);
    final ri = renderedPos.offset;
    for (final slot in _renderModel.linkSlots) {
      if (ri >= slot.renderedStart && ri < slot.renderedEnd) {
        return slot.element.url;
      }
    }
    return null;
  }

  /// Returns the source offset of the collapsed checkbox element whose glyph
  /// (☐ or ☑) was tapped at [localPosition], or null if the tap does not hit
  /// any collapsed checkbox glyph.
  ///
  /// Hit-tests by mapping the tap to a rendered offset and checking whether
  /// that offset falls within the [renderedMarkerStart, renderedMarkerEnd)
  /// range of any collapsed [CheckboxSlot].  Returns [element.start] of the
  /// matching slot so the caller can locate the 6-char marker in the source.
  int? checkboxSourceOffsetForTap(Offset localPosition) {
    final textOffset = localPosition - _padding.topLeft;
    final renderedPos = _textPainter.getPositionForOffset(textOffset);
    final ri = renderedPos.offset;
    for (final slot in _renderModel.checkboxSlots) {
      if (ri >= slot.renderedMarkerStart && ri < slot.renderedMarkerEnd) {
        return slot.element.start;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Paint
  // -------------------------------------------------------------------------

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final textOrigin = offset + _padding.topLeft;
    final paintWidth = constraints.maxWidth - _padding.horizontal;

    // Draw selection highlight boxes.
    final sel = _selection;
    if (sel.isValid && !sel.isCollapsed) {
      final rStart = _renderModel.renderedForSource(sel.start);
      final rEnd = _renderModel.renderedForSource(sel.end);
      final boxes = _textPainter.getBoxesForSelection(
        TextSelection(baseOffset: rStart, extentOffset: rEnd),
      );
      final highlightPaint = Paint()
        ..color = _selectionColor
        ..style = PaintingStyle.fill;
      for (final box in boxes) {
        canvas.drawRect(box.toRect().shift(textOrigin), highlightPaint);
      }
    }

    // Draw text.
    _textPainter.paint(canvas, textOrigin);

    // Draw blockquote left border stripes for collapsed blockquote slots.
    //
    // For each collapsed blockquote line, look up the Y position of the first
    // content character via TextPainter.getOffsetForCaret().  Paint a 3px-wide
    // vertical stripe in the border color (#7a828e) at the left edge of the
    // content area, spanning one line height.
    const Color blockquoteBorderColor = Color(0xFF7A828E);
    for (final bq in _renderModel.blockquoteSlots) {
      final el = bq.element;
      final cursorSrc = sel.isValid ? sel.baseOffset : -1;
      final revealed = cursorSrc >= el.start && cursorSrc <= el.end;
      if (revealed) continue;

      final contentOffset = _textPainter.getOffsetForCaret(
        TextPosition(offset: bq.renderedStart),
        Rect.zero,
      );
      final lineHeight = _textPainter.preferredLineHeight;
      // Paint the stripe at the left edge of the text area, same Y as content.
      final stripeRect = Rect.fromLTWH(
        textOrigin.dx,
        textOrigin.dy + contentOffset.dy,
        3.0,
        lineHeight,
      );
      canvas.drawRect(
        stripeRect,
        Paint()
          ..color = blockquoteBorderColor
          ..style = PaintingStyle.fill,
      );
    }

    // Draw horizontal rules for collapsed hr slots.
    //
    // For each collapsed hr line, look up the Y position via
    // TextPainter.getOffsetForCaret() at the hr's renderedCharOffset.  Paint
    // a 1px-wide horizontal line in muted color (#9ea7b4) at the vertical
    // midpoint of where that line of text would sit.
    const Color hrColor = Color(0xFF9EA7B4);
    for (final hr in _renderModel.hrSlots) {
      final el = hr.element;
      final cursorSrc = sel.isValid ? sel.baseOffset : -1;
      final revealed = cursorSrc >= el.start && cursorSrc <= el.end;
      if (revealed) continue;

      final caretOffset = _textPainter.getOffsetForCaret(
        TextPosition(offset: hr.renderedCharOffset),
        Rect.zero,
      );
      final lineHeight = _textPainter.preferredLineHeight;
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
    for (final cb in _renderModel.checkboxSlots) {
      final el = cb.element;
      final cursorSrc = sel.isValid ? sel.baseOffset : -1;
      final revealed = cursorSrc >= el.start && cursorSrc <= el.end;
      if (revealed) continue;

      final caretOffset = _textPainter.getOffsetForCaret(
        TextPosition(offset: cb.renderedMarkerStart),
        Rect.zero,
      );
      final lineHeight = _textPainter.preferredLineHeight;
      final boxSize = lineHeight * 0.55;
      final boxRect = Rect.fromLTWH(
        textOrigin.dx + caretOffset.dx,
        textOrigin.dy + caretOffset.dy + (lineHeight - boxSize) / 2,
        boxSize,
        boxSize,
      );
      final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(2));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = cb.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
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
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // Draw images (or placeholders) for collapsed image slots.
    //
    // Each image slot corresponds to a line that emits no rendered characters.
    // The TextPainter gives such a line zero height.  We look up the rendered
    // char offset of each slot, ask the TextPainter for the Y coordinate of
    // that position, then paint the image or placeholder rect at that Y.
    //
    // We track a cumulative vertical offset [imageYOffset] to account for the
    // extra height we added for previously-painted slots (since the TextPainter
    // is unaware of image heights, all subsequent slots are shifted down by the
    // sum of heights of all image slots above them).
    double imageYOffset = 0.0;
    for (final slot in _renderModel.imageSlots) {
      // Skip revealed elements: the raw source text is already visible via
      // the TextPainter and no separate image painting is needed.
      final el = slot.element;
      final cursorSrc = sel.isValid ? sel.baseOffset : -1;
      final revealed = cursorSrc >= el.start && cursorSrc <= el.end;
      if (revealed) {
        // Even though we skip painting, we still account for the height of
        // revealed image lines.  In practice a revealed image line IS painted
        // by the TextPainter (raw source chars are visible), and the layout
        // step reserved placeholder height for it.  We skip both painting and
        // the offset accumulation here because the TextPainter already placed
        // those characters at the correct Y position.
        continue;
      }

      final imgHeight = _imageHeight(slot, paintWidth);
      final renderedOff = slot.renderedCharOffset;

      // Look up the Y position in TextPainter space for this slot.
      final textCaretOff = _textPainter.getOffsetForCaret(
        TextPosition(offset: renderedOff),
        Rect.zero,
      );

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
      final caretOffset = _textPainter.getOffsetForCaret(
        TextPosition(offset: rOff),
        Rect.zero,
      );
      final caretHeight = _textPainter.getFullHeightForCaret(
        TextPosition(offset: rOff),
        Rect.zero,
      );
      final caretRect = Rect.fromLTWH(
        textOrigin.dx + caretOffset.dx,
        textOrigin.dy + caretOffset.dy,
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
