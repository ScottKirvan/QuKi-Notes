/**
 * Pure decision logic for the right-to-left swipe-to-delete gesture
 * (BEHAVIOR_SPEC.md §5, §6). Kept free of the DOM so the thresholds are
 * unit-testable without a browser; see swipeToDelete.ts for the Pointer
 * Events wiring that calls into this.
 */

export interface SwipeGestureConfig {
  /** Movement below this, in any direction, reads as a tap rather than a drag. */
  tapThresholdPx: number;
  /** Fraction of the row's width that must be dragged left to commit the delete. */
  commitDistanceRatio: number;
  /** A leftward flick faster than this (px/ms) commits even short of commitDistanceRatio. */
  commitVelocityPxPerMs: number;
}

/**
 * tapThresholdPx: 10px covers normal finger jitter on a tap without
 * mistaking it for a drag.
 * commitDistanceRatio: 0.4 - a deliberate swipe past two-fifths of the row
 * commits; short of that it reads as "just looking" and snaps back.
 * commitVelocityPxPerMs: 0.5 (500px/s) - a fast flick commits even if
 * released before crossing the distance ratio, matching how swipe-to-
 * dismiss feels on Android and iOS.
 */
export const DEFAULT_SWIPE_CONFIG: SwipeGestureConfig = {
  tapThresholdPx: 10,
  commitDistanceRatio: 0.4,
  commitVelocityPxPerMs: 0.5,
};

export type GestureAxis = "horizontal" | "vertical";

/**
 * Once movement exceeds the tap threshold, decides whether it reads as a
 * horizontal swipe or a vertical scroll - a diagonal drag must not hijack
 * the row from the page's own scrolling. Ties favour vertical (scrolling),
 * the safer default when direction is ambiguous.
 */
export function classifyAxis(dx: number, dy: number): GestureAxis {
  return Math.abs(dx) > Math.abs(dy) ? "horizontal" : "vertical";
}

export function hasExceededTapThreshold(dx: number, dy: number, config: SwipeGestureConfig): boolean {
  return Math.abs(dx) >= config.tapThresholdPx || Math.abs(dy) >= config.tapThresholdPx;
}

/**
 * Only a right-to-left drag can reveal the delete background - both
 * BEHAVIOR_SPEC.md §5 and §6 specify "right-to-left." A rightward drag is
 * clamped to the resting position rather than allowed to overshoot.
 */
export function clampDragX(dx: number): number {
  return Math.min(0, dx);
}

export function shouldCommitSwipe(draggedX: number, rowWidthPx: number, elapsedMs: number, config: SwipeGestureConfig): boolean {
  if (rowWidthPx <= 0) return false;
  const distance = Math.abs(draggedX);
  const distanceRatio = distance / rowWidthPx;
  const velocity = distance / Math.max(1, elapsedMs);
  return distanceRatio >= config.commitDistanceRatio || velocity >= config.commitVelocityPxPerMs;
}
