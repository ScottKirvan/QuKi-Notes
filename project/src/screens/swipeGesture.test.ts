import { describe, expect, it } from "vitest";

import { DEFAULT_SWIPE_CONFIG, classifyAxis, clampDragX, hasExceededTapThreshold, shouldCommitSwipe } from "./swipeGesture.js";

describe("classifyAxis", () => {
  it("reads a mostly-leftward drag as horizontal", () => {
    expect(classifyAxis(-40, 5)).toBe("horizontal");
  });

  it("reads a mostly-rightward drag as horizontal too (axis, not direction)", () => {
    expect(classifyAxis(40, 5)).toBe("horizontal");
  });

  it("reads a mostly-vertical drag as vertical", () => {
    expect(classifyAxis(5, 40)).toBe("vertical");
  });

  it("favours vertical on an exact tie, so ambiguous diagonal drags scroll rather than swipe", () => {
    expect(classifyAxis(20, 20)).toBe("vertical");
  });
});

describe("hasExceededTapThreshold", () => {
  it("is false for jitter well under the threshold", () => {
    expect(hasExceededTapThreshold(2, -3, DEFAULT_SWIPE_CONFIG)).toBe(false);
  });

  it("is false exactly at the boundary minus one", () => {
    expect(hasExceededTapThreshold(9, 0, DEFAULT_SWIPE_CONFIG)).toBe(false);
  });

  it("is true once horizontal movement reaches the threshold", () => {
    expect(hasExceededTapThreshold(10, 0, DEFAULT_SWIPE_CONFIG)).toBe(true);
  });

  it("is true once vertical movement reaches the threshold, even with no horizontal movement", () => {
    expect(hasExceededTapThreshold(0, 10, DEFAULT_SWIPE_CONFIG)).toBe(true);
  });
});

describe("clampDragX", () => {
  it("passes a leftward (negative) delta through unchanged", () => {
    expect(clampDragX(-55)).toBe(-55);
  });

  it("clamps a rightward (positive) delta to 0", () => {
    expect(clampDragX(30)).toBe(0);
  });

  it("leaves 0 as 0", () => {
    expect(clampDragX(0)).toBe(0);
  });
});

describe("shouldCommitSwipe", () => {
  it("commits once dragged distance crosses the commit ratio, even released slowly", () => {
    // 45% of a 200px row, over 2 full seconds - far too slow to read as a flick.
    expect(shouldCommitSwipe(-90, 200, 2000, DEFAULT_SWIPE_CONFIG)).toBe(true);
  });

  it("does not commit a short, slow drag", () => {
    // 10% of a 200px row, released slowly.
    expect(shouldCommitSwipe(-20, 200, 1000, DEFAULT_SWIPE_CONFIG)).toBe(false);
  });

  it("commits a fast flick even short of the distance ratio", () => {
    // Only 15% of a 200px row, but released in 30ms (~1px/ms velocity).
    expect(shouldCommitSwipe(-30, 200, 30, DEFAULT_SWIPE_CONFIG)).toBe(true);
  });

  it("treats a zero-width row as never committing rather than dividing by zero", () => {
    expect(shouldCommitSwipe(-50, 0, 100, DEFAULT_SWIPE_CONFIG)).toBe(false);
  });

  it("floors elapsed time at 1ms so an instantaneous release can't produce infinite velocity", () => {
    expect(() => shouldCommitSwipe(-5, 200, 0, DEFAULT_SWIPE_CONFIG)).not.toThrow();
  });
});
