import { ChangeSet } from "@codemirror/state";
import { describe, expect, it } from "vitest";

import { IMAGE_MIME_TO_EXTENSION, extensionForImageMime, findImagePasteItem, mapPasteRange } from "./pasteImage.js";

describe("findImagePasteItem", () => {
  it("finds a file item whose type is a supported image MIME", () => {
    const items = [
      { kind: "string", type: "text/plain" },
      { kind: "file", type: "image/png" },
    ];
    expect(findImagePasteItem(items)).toEqual({ kind: "file", type: "image/png" });
  });

  it("returns null when there is no file item at all", () => {
    const items = [{ kind: "string", type: "text/plain" }];
    expect(findImagePasteItem(items)).toBeNull();
  });

  it("ignores a file item whose type is not a supported image MIME (e.g. a pasted PDF)", () => {
    const items = [{ kind: "file", type: "application/pdf" }];
    expect(findImagePasteItem(items)).toBeNull();
  });

  it("returns null for an empty clipboard", () => {
    expect(findImagePasteItem([])).toBeNull();
  });

  it("finds the image regardless of whether it precedes or follows a text item (mixed-clipboard proposal)", () => {
    const textThenImage = [
      { kind: "string", type: "text/plain" },
      { kind: "file", type: "image/jpeg" },
    ];
    const imageThenText = [
      { kind: "file", type: "image/jpeg" },
      { kind: "string", type: "text/plain" },
    ];
    expect(findImagePasteItem(textThenImage)?.type).toBe("image/jpeg");
    expect(findImagePasteItem(imageThenText)?.type).toBe("image/jpeg");
  });

  it("recognises all four required MIME types", () => {
    for (const type of Object.keys(IMAGE_MIME_TO_EXTENSION)) {
      expect(findImagePasteItem([{ kind: "file", type }])).toEqual({ kind: "file", type });
    }
  });
});

describe("extensionForImageMime", () => {
  it("maps each required MIME type to its conventional extension", () => {
    expect(extensionForImageMime("image/png")).toBe("png");
    expect(extensionForImageMime("image/jpeg")).toBe("jpg");
    expect(extensionForImageMime("image/gif")).toBe("gif");
    expect(extensionForImageMime("image/webp")).toBe("webp");
  });

  it("falls back to png for a type findImagePasteItem would never actually pass it (keeps the function total)", () => {
    expect(extensionForImageMime("image/bmp")).toBe("png");
  });
});

describe("mapPasteRange", () => {
  // Bug repro (Scott, 2026-09-25): the pre-fix plugin captured {from, to}
  // once, synchronously, and reused that same fixed pair after the async
  // file-read-and-write gap. These tests pin the replacement: a pending
  // paste's range must move with the document, not stay fixed.

  it("shifts a range forward when a change inserts text before it", () => {
    const change = ChangeSet.of({ from: 0, insert: "XXXXX" }, 11);
    expect(mapPasteRange({ from: 6, to: 11 }, change)).toEqual({ from: 11, to: 16 });
  });

  it("pushes the range past a change landing exactly at its position, instead of colliding with it — two pastes fired at the same cursor spot, one resolving before the other", () => {
    const change = ChangeSet.of({ from: 5, insert: "![](media/a.png)" }, 10);
    expect(mapPasteRange({ from: 5, to: 5 }, change)).toEqual({ from: 21, to: 21 });
  });

  it("leaves the range unchanged when a change lands entirely after it", () => {
    const change = ChangeSet.of({ from: 20, insert: "XXXXX" }, 30);
    expect(mapPasteRange({ from: 5, to: 10 }, change)).toEqual({ from: 5, to: 10 });
  });

  it("shifts the range back when text before it is deleted", () => {
    const change = ChangeSet.of({ from: 0, to: 5, insert: "" }, 20);
    expect(mapPasteRange({ from: 10, to: 15 }, change)).toEqual({ from: 5, to: 10 });
  });

  it("composes correctly across multiple sequential changes, matching how trackChanges applies them one update at a time", () => {
    let range = { from: 5, to: 5 };
    range = mapPasteRange(range, ChangeSet.of({ from: 5, insert: "AAA" }, 10)); // -> 8
    range = mapPasteRange(range, ChangeSet.of({ from: 0, insert: "BB" }, 13)); // insert before -> 10
    expect(range).toEqual({ from: 10, to: 10 });
  });

  it("collapses a real selection (to > from) the same way a bare cursor does, so a selected-then-pasted-over range stays correct", () => {
    const change = ChangeSet.of({ from: 0, insert: "XX" }, 20);
    expect(mapPasteRange({ from: 5, to: 9 }, change)).toEqual({ from: 7, to: 11 });
  });

  // The actual repro (Scott, 2026-09-25): two pastes both replacing the
  // same selected placeholder text - independently mapping `from` and `to`
  // is unsafe here (ChangeDesc.mapPos resolves a position at the exact
  // START of an overlapping replacement to BEFORE it regardless of assoc),
  // which is what let a second paste's dispatch delete part of the first
  // paste's already-inserted link instead of appending after it.
  it("collapses to a cursor right after another change that replaces this range's exact span, instead of straddling its inserted content", () => {
    const change = ChangeSet.of({ from: 0, to: 1, insert: "!".repeat(51) }, 1);
    expect(mapPasteRange({ from: 0, to: 1 }, change)).toEqual({ from: 51, to: 51 });
  });

  it("collapses correctly when the overlapping change only partially covers this range", () => {
    // Our range [2, 8); the other change replaces just [4, 6) inside it.
    const change = ChangeSet.of({ from: 4, to: 6, insert: "XXXXXXXXXX" }, 10);
    expect(mapPasteRange({ from: 2, to: 8 }, change)).toEqual({ from: 14, to: 14 });
  });

  it("also collapses when a change lands exactly at this range's own boundary, not just strictly inside it - genuinely ambiguous, so the safe choice wins", () => {
    // A pure insert exactly at this range's `to` (5): `touchesRange`
    // counts a boundary-adjacent change as touching, and correctly so -
    // this range's own end was pointing at exactly where new content just
    // landed, so treating it as consumed (rather than guessing it should
    // stay put) is the safer read.
    const change = ChangeSet.of({ from: 5, insert: "YY" }, 10);
    expect(mapPasteRange({ from: 0, to: 5 }, change)).toEqual({ from: 7, to: 7 });
  });
});
