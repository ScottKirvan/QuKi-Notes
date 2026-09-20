import { describe, expect, it } from "vitest";

import { IMAGE_MIME_TO_EXTENSION, extensionForImageMime, findImagePasteItem } from "./pasteImage.js";

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
