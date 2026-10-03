export interface VerticalBox {
  top: number;
  bottom: number;
}

const center = (box: VerticalBox): number => (box.top + box.bottom) / 2;

/**
 * The first box that sits on a later row than the first box, or null when
 * everything is on one row. Rows are told apart by centers rather than tops so
 * that a taller or offset box on the first row (a different font, an inline
 * widget) is not taken for a new row, and so a line height smaller than the
 * glyph box still separates them.
 */
export function secondRowBox(boxes: Iterable<VerticalBox>): VerticalBox | null {
  let first: VerticalBox | null = null;
  for (const box of boxes) {
    if (first === null) {
      first = box;
      continue;
    }
    if (center(box) > center(first) + (first.bottom - first.top) / 2) return box;
  }
  return null;
}

/**
 * Where a row's line box begins, from one of its glyph boxes: the line height
 * adds equal leading above and below the glyphs.
 */
export function rowTopFor(glyphBox: VerticalBox, lineHeight: number): number {
  return glyphBox.top - (lineHeight - (glyphBox.bottom - glyphBox.top)) / 2;
}

/**
 * The vertical extent, in the line's own coordinates, of the float that
 * pushes every row after the first to the right: it starts `margin` below the
 * top of the second row and ends just inside the last row. The margin absorbs
 * the error in estimating the row's top, which must not be overshot upwards
 * (that would move the first row too) and costs nothing when overshot
 * downwards; ending inside the last row's line box rather than past it keeps
 * the float from making the line taller or reaching the next one.
 */
export function floatSpan(
  secondRowTop: number,
  lastRowCenter: number,
  margin: number,
): { top: number; height: number } {
  const top = secondRowTop + margin;
  return { top, height: Math.max(1, lastRowCenter + 1 - top) };
}
