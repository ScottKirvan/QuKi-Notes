import { describe, expect, it } from "vitest";

import { creditsData } from "./credits";

describe("credits data", () => {
  it("has at least one section, each with a title and at least one entry", () => {
    expect(creditsData.sections.length).toBeGreaterThan(0);
    for (const section of creditsData.sections) {
      expect(section.title.trim(), "section title").not.toBe("");
      expect(section.entries.length, `entries of "${section.title}"`).toBeGreaterThan(0);
    }
  });

  it("gives every entry a name, and a detail or url that is not blank when present", () => {
    for (const section of creditsData.sections) {
      for (const entry of section.entries) {
        expect(entry.name.trim(), `a name in "${section.title}"`).not.toBe("");
        if (entry.detail !== undefined) expect(entry.detail.trim(), `detail of ${entry.name}`).not.toBe("");
      }
    }
  });

  it("uses only https urls", () => {
    for (const section of creditsData.sections) {
      for (const entry of section.entries) {
        if (entry.url === undefined) continue;
        expect(() => new URL(entry.url!), `url of ${entry.name}`).not.toThrow();
        expect(new URL(entry.url).protocol, `url of ${entry.name}`).toBe("https:");
      }
    }
  });

  it("has no repeated name within a section, and a notice line", () => {
    for (const section of creditsData.sections) {
      const names = section.entries.map((entry) => entry.name);
      expect(new Set(names).size, `names in "${section.title}"`).toBe(names.length);
    }
    expect(creditsData.notice.trim()).not.toBe("");
  });

  it("has only the fields the dialog reads", () => {
    const entryFields = new Set(["name", "detail", "url"]);
    for (const section of creditsData.sections) {
      expect(Object.keys(section).sort()).toEqual(["entries", "title"]);
      for (const entry of section.entries) {
        for (const key of Object.keys(entry)) expect(entryFields.has(key), `field "${key}" of ${entry.name}`).toBe(true);
      }
    }
  });
});
