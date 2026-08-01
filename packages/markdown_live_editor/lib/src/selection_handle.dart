import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// SelectionHandle — Stage 2 draggable selection-boundary handle.
//
// A small, always-independently-draggable affordance shown at a non-collapsed
// selection's start and end boundaries (see notes/dev/selection.md §2). This
// widget owns no selection state itself — it is a pure "paint a handle here,
// report drag deltas" building block. All drag bookkeeping (which boundary
// moves, crossing, the resulting TextSelection) lives in QuikiEditorState,
// which is what makes each handle a genuinely independent, later gesture: the
// GestureDetector below is fresh every time a user grabs it, unrelated to
// whatever gesture (long-press, double-tap) originally created the selection.
// ---------------------------------------------------------------------------

/// Paints a single teardrop-approximation handle glyph: a filled circle with
/// one top corner squared off, so the shape reads as "pointing" at the
/// corner that touches the caret line. [pointOnRight] selects which top
/// corner is squared off (true = top-right, used for the selection-start
/// handle which hangs down-and-left of its anchor; false = top-left, used
/// for the selection-end handle which hangs down-and-right) — mirroring the
/// handedness convention documented in notes/dev/selection.md §2.
///
/// This is a from-scratch Canvas painter, not a Material asset — the app's
/// visual-design standard (GitHub Primer palette, no stock Material handle
/// assets/colors) applies to selection handles the same as everywhere else.
class _HandlePainter extends CustomPainter {
  const _HandlePainter({required this.color, required this.pointOnRight});

  final Color color;
  final bool pointOnRight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final radius = size.width / 2;
    final circle =
        Rect.fromCircle(center: Offset(radius, radius), radius: radius);
    // A full circle would round off every corner of its bounding box. Filling
    // in one top quadrant square (in addition to the circle) squares off
    // exactly that corner instead, leaving the other three sides visually
    // round — the "point" where the handle meets the caret line.
    final pointCorner = pointOnRight
        ? Rect.fromLTWH(radius, 0, radius, radius) // top-right quadrant
        : Rect.fromLTWH(0, 0, radius, radius); // top-left quadrant
    final path = Path()
      ..addOval(circle)
      ..addRect(pointCorner);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HandlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointOnRight != pointOnRight;
}

/// A draggable selection-boundary handle.
///
/// [diameter] is the visible glyph size. The widget itself always occupies
/// its full incoming constraints (sized by the caller, typically larger than
/// [diameter], via a [Positioned] `width`/`height` in the parent [Stack]) so
/// the touch-hit area can be comfortably larger than the visible glyph
/// (notes/dev/selection.md §2: ~22dp visible, ~48dp recommended touch
/// target) — the glyph is centered within whatever box the caller gives it.
class SelectionHandle extends StatelessWidget {
  const SelectionHandle({
    super.key,
    required this.color,
    required this.diameter,
    required this.pointOnRight,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final Color color;
  final double diameter;

  /// True for the selection-start handle (squared top-right corner, bulb
  /// hangs down-left); false for the selection-end handle (squared top-left
  /// corner, bulb hangs down-right).
  final bool pointOnRight;

  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    // behavior: opaque so the whole touch target participates in hit-testing,
    // not just the pixels the CustomPainter actually paints — a bigger
    // invisible hit area is the entire point of separating diameter (visible)
    // from the box this widget is laid out into (see class doc).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: Center(
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: CustomPaint(
            painter: _HandlePainter(color: color, pointOnRight: pointOnRight),
          ),
        ),
      ),
    );
  }
}
