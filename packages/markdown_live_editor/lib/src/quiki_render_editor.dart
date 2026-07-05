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
  });

  final RenderModel renderModel;
  final TextSelection selection;
  final EdgeInsets padding;
  final bool focused;
  final Color cursorColor;
  final Color selectionColor;

  @override
  QuikiRenderEditor createRenderObject(BuildContext context) {
    return QuikiRenderEditor(
      renderModel: renderModel,
      selection: selection,
      padding: padding,
      focused: focused,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
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
      ..selectionColor = selectionColor;
  }
}

// ---------------------------------------------------------------------------
// QuikiRenderEditor — RenderBox
//
// Owns a TextPainter. Paints selection highlight, text, and caret.
// No state, no TextInputConnection, no keyboard handling.
// ---------------------------------------------------------------------------

class QuikiRenderEditor extends RenderBox {
  QuikiRenderEditor({
    required RenderModel renderModel,
    required TextSelection selection,
    required EdgeInsets padding,
    required bool focused,
    required Color cursorColor,
    required Color selectionColor,
  })  : _renderModel = renderModel,
        _selection = selection,
        _padding = padding,
        _focused = focused,
        _cursorColor = cursorColor,
        _selectionColor = selectionColor {
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

  // -------------------------------------------------------------------------
  // Property setters — each marks the render object dirty as needed.
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth - _padding.horizontal;
    _textPainter.layout(maxWidth: maxWidth < 0 ? 0 : maxWidth);
    final textHeight = _textPainter.height;
    // Height is content-driven; parent scroll view handles clipping.
    size = Size(
      constraints.maxWidth,
      textHeight + _padding.vertical,
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
  TextPosition positionForOffset(Offset localPosition) {
    final textOffset = localPosition - _padding.topLeft;
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

  // -------------------------------------------------------------------------
  // Paint
  // -------------------------------------------------------------------------

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final textOrigin = offset + _padding.topLeft;

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
