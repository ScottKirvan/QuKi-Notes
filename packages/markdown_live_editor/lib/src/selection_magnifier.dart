import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// QuikiMagnifier — Stage 4 magnifier/loupe shown while dragging a selection
// handle (notes/dev/selection.md §3, ADR-36).
//
// Built on RawMagnifier / MagnifierController — the low-level, unstyled
// mechanism classes in package:flutter/widgets.dart (a BackdropFilter-based
// lens plus an OverlayEntry lifecycle helper). These are NOT tied to
// RenderEditable/EditableText — they're the general-purpose building blocks
// Flutter itself uses to implement its own stock text-field magnifier, and
// they work identically against this editor's custom RenderObject (ADR-31).
//
// Deliberately NOT flutter/material.dart's own `Magnifier`/`TextMagnifier`
// widgets: those hardcode Material's visual look (a specific film-color
// tint, corner radius, and shadow) and Android/iOS-specific positioning
// wiring via `MagnifierInfo`/`TextMagnifierConfiguration`, which are designed
// to be fed from RenderEditable's own selection geometry. This app's design
// standard (see notes/dev/decisions.md's "Visual design standard" and
// selection.md's framing note) is explicit that Android/Material's
// BEHAVIORAL conventions should transfer but stock Material's exact visual
// styling should not — this editor already overrides that everywhere else
// (Primer palette, Lucide icons, a from-scratch Canvas-painted selection
// handle in selection_handle.dart instead of a Material handle asset). This
// file re-implements the same POSITIONING algorithm Flutter's own
// TextMagnifier uses (horizontal tracks the gesture, clamped to the current
// line's bounds; vertical locked to the line's center, jumping only when the
// drag crosses a line boundary) against our own geometry, and decorates the
// lens with this app's own accent color instead of Material's.
// ---------------------------------------------------------------------------

/// A snapshot of the current handle-drag gesture, in GLOBAL (screen)
/// coordinates — everything the magnifier needs to position itself and
/// choose what to sample, computed by [QuikiEditorState] from
/// [QuikiRenderEditor.lineBoundsForRendered] the same way
/// [QuikiEditorState] already computes global positions for the floating
/// toolbar and the handles themselves (getOffsetForCaret + localToGlobal).
@immutable
class QuikiMagnifierInfo {
  const QuikiMagnifierInfo({
    required this.gesturePosition,
    required this.lineBounds,
  });

  /// The live pointer position driving the active handle drag.
  final Offset gesturePosition;

  /// The bounding rect of the VISUAL (soft-wrapped) line currently under the
  /// dragged handle. The magnifier's horizontal tracking is clamped to
  /// `[lineBounds.left, lineBounds.right]` and its vertical position is
  /// locked to `lineBounds.center.dy` — see [computeMagnifierGeometry].
  final Rect lineBounds;

  @override
  bool operator ==(Object other) =>
      other is QuikiMagnifierInfo &&
      other.gesturePosition == gesturePosition &&
      other.lineBounds == lineBounds;

  @override
  int get hashCode => Object.hash(gesturePosition, lineBounds);
}

/// The resolved on-screen placement for one [QuikiMagnifierInfo] snapshot —
/// where the lens widget itself is drawn ([widgetCenter]), and how far the
/// content it samples is offset from that drawn position ([focalPointOffset],
/// fed straight to [RawMagnifier.focalPointOffset]).
@immutable
class QuikiMagnifierGeometry {
  const QuikiMagnifierGeometry({
    required this.widgetCenter,
    required this.focalPointOffset,
  });

  final Offset widgetCenter;
  final Offset focalPointOffset;
}

/// Computes where the magnifier lens should be drawn, and what it should
/// sample, for [info] — pure geometry, no BuildContext/widget tree involved,
/// so it can be unit-tested directly (see selection_magnifier_test.dart)
/// independent of driving a real drag gesture.
///
/// Mirrors the structure of Flutter's own (Material-private)
/// `_TextMagnifierState._determineMagnifierPositionAndFocalPoint`, adapted
/// to this editor's stricter confirmed requirement (selection.md §3): the
/// SAMPLED content must never extend past the current line's own actual
/// left/right edges, not just the field's — so the focal-point inset below
/// is computed against [QuikiMagnifierInfo.lineBounds] directly, rather than
/// a whole-field bounds as Flutter's Material implementation does.
QuikiMagnifierGeometry computeMagnifierGeometry(
  QuikiMagnifierInfo info, {
  Size lensSize = QuikiMagnifier.defaultSize,
  double magnificationScale = QuikiMagnifier.defaultMagnificationScale,
  double verticalShift = QuikiMagnifier.defaultVerticalShift,
}) {
  final line = info.lineBounds;

  // Where the LENS itself is drawn: tracks the gesture's x smoothly, but
  // never past the line's own edges — this is what makes the lens visually
  // "hug" the line rather than drift out over the margin.
  final widgetX = line.left <= line.right
      ? info.gesturePosition.dx.clamp(line.left, line.right)
      : line.left;

  // Where the content it SAMPLES is centered: additionally inset by half the
  // lens's own on-screen width (divided by magnification, since a wider
  // sample maps to the same on-screen lens width when zoomed in) so that,
  // even at the very edge of the line, the magnified image itself never
  // shows anything past the line's true boundary.
  final halfSampleWidth = (lensSize.width / 2) / magnificationScale;
  final insetLeft = line.left + halfSampleWidth;
  final insetRight = line.right - halfSampleWidth;
  final double focalX;
  if (insetLeft > insetRight) {
    // The line is narrower than one lens-width of sampled content — no
    // position keeps the whole sample in-bounds, so center on the line
    // rather than clamp(low, high) with low > high (a Dart range error).
    focalX = line.left + line.width / 2;
  } else {
    focalX = info.gesturePosition.dx.clamp(insetLeft, insetRight);
  }

  final lineCenterY = line.top + line.height / 2;
  final widgetCenter = Offset(widgetX, lineCenterY - verticalShift);
  // sees = widgetCenter + focalPointOffset (RawMagnifier.focalPointOffset's
  // documented contract) — solve for the offset that makes the sampled
  // point land at (focalX, lineCenterY): the true line center vertically
  // (never the raw finger y — that's the "vertically locked" requirement),
  // and the edge-safe focalX horizontally.
  final focalPointOffset = Offset(focalX - widgetX, verticalShift);

  return QuikiMagnifierGeometry(
    widgetCenter: widgetCenter,
    focalPointOffset: focalPointOffset,
  );
}

/// The magnifier lens widget itself — positioned via [Positioned] (valid
/// because [MagnifierController.show] inserts its builder's result directly
/// into the root [Overlay]'s own internal Stack, the same way Flutter's own
/// TextMagnifier does) and rebuilt on every [info] change via
/// [ValueListenableBuilder].
class QuikiMagnifier extends StatelessWidget {
  const QuikiMagnifier({
    super.key,
    required this.info,
    required this.color,
  });

  /// Live drag geometry — updated by [QuikiEditorState] on every handle
  /// pan-update (and after an auto-scroll tick re-resolves the dragged
  /// boundary, ADR-36 Stage 3).
  final ValueListenable<QuikiMagnifierInfo> info;

  /// Border/accent color — threaded from the ambient cursor/accent color the
  /// same way [SelectionHandle] receives its color, so the lens matches this
  /// app's own Primer palette rather than a fixed Material tint.
  final Color color;

  /// Lens size. A design choice (needs real-device tuning), not a
  /// correctness invariant — chosen to roughly match the aspect ratio of
  /// Android's own text magnifier (wide, short) at a size comfortably larger
  /// than one line of body text.
  static const Size defaultSize = Size(84, 42);

  static const double defaultMagnificationScale = 1.5;

  /// Vertical distance, in logical pixels, the lens is drawn ABOVE the line
  /// it samples — this is what keeps the dragging finger from obscuring the
  /// character being targeted (selection.md §3). A design choice, not a
  /// correctness invariant; tune from real device feel.
  static const double defaultVerticalShift = 64.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<QuikiMagnifierInfo>(
      valueListenable: info,
      builder: (context, value, _) {
        final geometry = computeMagnifierGeometry(value);
        final topLeft = geometry.widgetCenter -
            Offset(defaultSize.width / 2, defaultSize.height / 2);
        return Positioned(
          left: topLeft.dx,
          top: topLeft.dy,
          // Purely a visual overlay — must never intercept the pointer that
          // is actively driving the handle drag underneath it.
          child: IgnorePointer(
            child: RawMagnifier(
              size: defaultSize,
              magnificationScale: defaultMagnificationScale,
              focalPointOffset: geometry.focalPointOffset,
              decoration: MagnifierDecoration(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: color, width: 1.5),
                ),
                shadows: const [
                  BoxShadow(
                    blurRadius: 4,
                    offset: Offset(0, 2),
                    color: Color(0x66000000),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
