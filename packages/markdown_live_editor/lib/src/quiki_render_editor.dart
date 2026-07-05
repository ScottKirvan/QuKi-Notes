import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// QuikiRenderWidget — LeafRenderObjectWidget
//
// Single responsibility: rendering. Passes state down to QuikiRenderEditor
// via createRenderObject / updateRenderObject. No input handling here.
// ---------------------------------------------------------------------------

class QuikiRenderWidget extends LeafRenderObjectWidget {
  const QuikiRenderWidget({
    super.key,
    required this.value,
    required this.textStyle,
    required this.padding,
    required this.focused,
    required this.cursorColor,
    required this.selectionColor,
  });

  final TextEditingValue value;
  final TextStyle textStyle;
  final EdgeInsets padding;
  final bool focused;
  final Color cursorColor;
  final Color selectionColor;

  @override
  QuikiRenderEditor createRenderObject(BuildContext context) {
    return QuikiRenderEditor(
      value: value,
      textStyle: textStyle,
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
      ..value = value
      ..textStyle = textStyle
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
    required TextEditingValue value,
    required TextStyle textStyle,
    required EdgeInsets padding,
    required bool focused,
    required Color cursorColor,
    required Color selectionColor,
  })  : _value = value,
        _textStyle = textStyle,
        _padding = padding,
        _focused = focused,
        _cursorColor = cursorColor,
        _selectionColor = selectionColor {
    _textPainter = TextPainter(
      text: _buildTextSpan(),
      textDirection: ui.TextDirection.ltr,
    );
  }

  TextEditingValue _value;
  TextStyle _textStyle;
  EdgeInsets _padding;
  bool _focused;
  Color _cursorColor;
  Color _selectionColor;
  late TextPainter _textPainter;

  // -------------------------------------------------------------------------
  // Property setters — each marks the render object dirty as needed.
  // -------------------------------------------------------------------------

  set value(TextEditingValue v) {
    if (_value == v) return;
    _value = v;
    _textPainter.text = _buildTextSpan();
    markNeedsLayout();
  }

  set textStyle(TextStyle s) {
    if (_textStyle == s) return;
    _textStyle = s;
    _textPainter.text = _buildTextSpan();
    markNeedsLayout();
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
  // TextSpan builder — plain text only in Stage 1.
  // -------------------------------------------------------------------------

  InlineSpan _buildTextSpan() {
    return TextSpan(text: _value.text, style: _textStyle);
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
    return _textPainter.getPositionForOffset(textOffset);
  }

  /// Maps a source TextPosition to a canvas offset relative to the text origin
  /// (does NOT include padding — callers add padding.topLeft as needed).
  Offset getOffsetForCaret(TextPosition position) {
    return _textPainter.getOffsetForCaret(position, Rect.zero);
  }

  /// Maps a canvas offset (relative to text origin, no padding) to a TextPosition.
  TextPosition getPositionForOffset(Offset textOffset) {
    return _textPainter.getPositionForOffset(textOffset);
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
    final sel = _value.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final boxes = _textPainter.getBoxesForSelection(
        TextSelection(baseOffset: sel.start, extentOffset: sel.end),
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
      final caretOffset = _textPainter.getOffsetForCaret(
        TextPosition(offset: sel.baseOffset),
        Rect.zero,
      );
      final caretHeight = _textPainter.getFullHeightForCaret(
        TextPosition(offset: sel.baseOffset),
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
