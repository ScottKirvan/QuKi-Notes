import { describe, expect, it } from "vitest";

import { buildLinkRows } from "./aboutDialog";

describe("buildLinkRows", () => {
  it("without a report form keeps the four link rows, GitHub included", () => {
    const rows = buildLinkRows(false);
    expect(rows.map((row) => row.key)).toEqual(["docs", "discord", "github", "kofi"]);
    expect(rows.find((row) => row.key === "github")).toMatchObject({
      title: "GitHub",
      description: "Source code, issues, and release notes.",
      label: "View",
      url: "https://github.com/ScottKirvan/QuKi-Notes",
    });
  });

  it("with a report form puts Report a problem where GitHub was, and GitHub is gone from the rows", () => {
    const rows = buildLinkRows(true);
    expect(rows.map((row) => row.key)).toEqual(["docs", "discord", "report", "kofi"]);
    expect(rows.find((row) => row.key === "report")).toEqual({
      key: "report",
      title: "Report a problem",
      description: "Bugs, ideas or feedback.",
      label: "Report",
    });
  });
});
