import { describe, expect, it } from "vitest";

import { buildExportFileName } from "./exportFileName.js";

describe("buildExportFileName", () => {
  it("names the file with a .tar.gz extension and a local-time timestamp", () => {
    const fixed = new Date(2026, 8, 26, 14, 5, 9); // 2026-09-26 14:05:09 local time

    expect(buildExportFileName(fixed)).toBe("quki-export-20260926-140509.tar.gz");
  });

  it("zero-pads single-digit month, day, hour, minute and second", () => {
    const fixed = new Date(2026, 0, 2, 3, 4, 5); // 2026-01-02 03:04:05 local time

    expect(buildExportFileName(fixed)).toBe("quki-export-20260102-030405.tar.gz");
  });

  it("produces a different name a second apart, so repeated exports don't collide", () => {
    const first = buildExportFileName(new Date(2026, 8, 26, 14, 5, 9));
    const second = buildExportFileName(new Date(2026, 8, 26, 14, 5, 10));

    expect(first).not.toBe(second);
  });
});
