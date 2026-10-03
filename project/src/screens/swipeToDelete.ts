import { DEFAULT_SWIPE_CONFIG, classifyAxis, clampDragX, hasExceededTapThreshold, shouldCommitSwipe } from "./swipeGesture.js";

export interface SwipeToDeleteCallbacks {
  /** A release that never crossed the tap threshold - open/restore the row as before. */
  onTap: () => void;
  /** A release that crossed the commit threshold; the row is already animated fully off-screen. */
  onCommit: () => void;
}

/**
 * Wires the Pointer Events API (pointerdown/pointermove/pointerup/
 * pointercancel) to `content` so it tracks right-to-left drags, unifying
 * mouse and touch input rather than handling them as separate paths
 * (BEHAVIOR_SPEC.md §5/§6's "swiping right-to-left deletes it"). `content`
 * is the piece that visually follows the drag; it must stay opaque so it
 * occludes the row's `.list-row-swipe-bg` sibling until the drag reveals it.
 *
 * A tap and a drag are mutually exclusive outcomes of the same gesture, so
 * this owns "what counts as opening the row" too (via onTap) rather than
 * leaving a separate click listener to race against it.
 */
export function attachSwipeToDelete(content: HTMLElement, callbacks: SwipeToDeleteCallbacks): void {
  const config = DEFAULT_SWIPE_CONFIG;

  let pointerId: number | null = null;
  let startX = 0;
  let startY = 0;
  let startTime = 0;
  let currentX = 0;
  let axisDecided = false;
  let isSwipe = false;

  function setTransform(x: number, animate: boolean): void {
    content.style.transition = animate ? "transform 200ms ease" : "none";
    content.style.transform = `translateX(${x}px)`;
  }

  function reset(): void {
    pointerId = null;
    currentX = 0;
    axisDecided = false;
    isSwipe = false;
  }

  function onPointerDown(e: PointerEvent): void {
    if (pointerId !== null) return;
    if (e.pointerType === "mouse" && e.button !== 0) return;
    pointerId = e.pointerId;
    startX = e.clientX;
    startY = e.clientY;
    startTime = performance.now();
    axisDecided = false;
    isSwipe = false;
  }

  function onPointerMove(e: PointerEvent): void {
    if (pointerId === null || e.pointerId !== pointerId) return;
    const dx = e.clientX - startX;
    const dy = e.clientY - startY;

    if (!axisDecided) {
      if (!hasExceededTapThreshold(dx, dy, config)) return;
      axisDecided = true;
      isSwipe = classifyAxis(dx, dy) === "horizontal";
      if (isSwipe) content.setPointerCapture(pointerId);
    }
    if (!isSwipe) return;

    e.preventDefault();
    currentX = clampDragX(dx);
    setTransform(currentX, false);
  }

  function onPointerUp(e: PointerEvent): void {
    if (pointerId === null || e.pointerId !== pointerId) return;
    const elapsed = performance.now() - startTime;
    const wasSwipe = isSwipe;
    const draggedX = currentX;
    if (content.hasPointerCapture(pointerId)) content.releasePointerCapture(pointerId);
    reset();

    if (!wasSwipe) {
      callbacks.onTap();
      return;
    }

    const width = content.getBoundingClientRect().width || content.offsetWidth;
    if (shouldCommitSwipe(draggedX, width, elapsed, config)) {
      commit();
    } else {
      setTransform(0, true);
    }
  }

  function commit(): void {
    let done = false;
    const finish = (): void => {
      if (done) return;
      done = true;
      content.removeEventListener("transitionend", finish);
      callbacks.onCommit();
    };
    content.addEventListener("transitionend", finish);
    // transitionend can fail to fire (reduced-motion settings, a detached
    // layout in a headless test runner) - a short fallback timer keeps the
    // commit from silently hanging in that case.
    setTimeout(finish, 250);
    setTransform(-content.getBoundingClientRect().width - 40, true);
  }

  function onPointerCancel(e: PointerEvent): void {
    if (pointerId === null || e.pointerId !== pointerId) return;
    if (content.hasPointerCapture(pointerId)) content.releasePointerCapture(pointerId);
    reset();
    setTransform(0, true);
  }

  content.addEventListener("pointerdown", onPointerDown);
  content.addEventListener("pointermove", onPointerMove);
  content.addEventListener("pointerup", onPointerUp);
  content.addEventListener("pointercancel", onPointerCancel);
}
