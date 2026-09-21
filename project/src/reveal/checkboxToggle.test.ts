import { describe, expect, it } from "vitest";
import { toggleCheckbox } from "./checkboxToggle";

function toggled(line: string): string {
  const edit = toggleCheckbox(line);
  if (edit === null) return line;
  return line.slice(0, edit.from) + edit.insert + line.slice(edit.to);
}

describe("toggleCheckbox", () => {
  it("given an unchecked item, when toggled, then it becomes checked", () => {
    expect(toggled("- [ ] foo")).toBe("- [x] foo");
  });

  it("given a checked item, when toggled, then it becomes unchecked", () => {
    expect(toggled("- [x] foo")).toBe("- [ ] foo");
  });

  it("given a capital X, when toggled, then it counts as checked and becomes unchecked", () => {
    expect(toggled("- [X] foo")).toBe("- [ ] foo");
  });

  it("given an empty task item, when toggled, then the marker flips", () => {
    expect(toggled("- [ ] ")).toBe("- [x] ");
    expect(toggled("- [x] ")).toBe("- [ ] ");
  });

  it("given content after the marker, when toggled, then the content is untouched", () => {
    expect(toggled("- [ ] **urgent** call back")).toBe("- [x] **urgent** call back");
    expect(toggled("- [x] **urgent** call back")).toBe("- [ ] **urgent** call back");
  });

  it.each([
    ["  - [ ] nested", "  - [x] nested"],
    ["\t- [ ] nested", "\t- [x] nested"],
    ["    - [ ] deeper", "    - [x] deeper"],
    [" \t - [x] mixed", " \t - [ ] mixed"],
  ])("given indentation %j, when toggled, then the indentation is skipped and preserved", (line, expected) => {
    expect(toggled(line)).toBe(expected);
  });

  it("given a toggle, then the edit is the six-character marker and nothing else", () => {
    expect(toggleCheckbox("\t- [ ] x")).toEqual({ from: 1, to: 7, insert: "- [x] " });
    expect(toggleCheckbox("- [X] x")).toEqual({ from: 0, to: 6, insert: "- [ ] " });
  });

  it.each([
    "- item",
    "plain text",
    "",
    "- [ ]",
    "- [ ]x",
    "- [y] x",
    "-[ ] x",
    "* [ ] x",
    "+ [x] x",
    "1. [ ] x",
    "> - [ ] x",
    "-  [ ] x",
    "- [  ] x",
    "text - [ ] x",
  ])("given %j, then it is not a checkbox marker and is ignored", (line) => {
    expect(toggleCheckbox(line)).toBeNull();
  });

  it("given a line that only looks like a marker after non-indentation text, then it is ignored", () => {
    expect(toggleCheckbox("a\n- [ ] x")).toBeNull();
  });
});
