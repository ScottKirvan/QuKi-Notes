import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { syntaxTree } from "@codemirror/language";
import type { SyntaxNode } from "@lezer/common";
import { buildTableModel, parseTableAlignment, type TableModel } from "./tableModel";

function tableModelFor(doc: string): TableModel {
  const state = EditorState.create({
    doc,
    extensions: [markdown({ extensions: GFM })],
  });
  let tableNode: SyntaxNode | null = null;
  syntaxTree(state).iterate({
    enter(node) {
      if (tableNode === null && node.name === "Table") tableNode = node.node;
    },
  });
  if (!tableNode) throw new Error(`no Table node parsed from: ${doc}`);
  return buildTableModel(state, tableNode);
}

describe("parseTableAlignment", () => {
  it("given a plain dash column, then its alignment is null", () => {
    expect(parseTableAlignment("|---|")).toEqual([null]);
  });

  it("given a leading colon, then the column is left-aligned", () => {
    expect(parseTableAlignment("|:---|")).toEqual(["left"]);
  });

  it("given a trailing colon, then the column is right-aligned", () => {
    expect(parseTableAlignment("|---:|")).toEqual(["right"]);
  });

  it("given colons on both ends, then the column is centered", () => {
    expect(parseTableAlignment("|:---:|")).toEqual(["center"]);
  });

  it("given several columns, then each gets its own declared alignment", () => {
    expect(parseTableAlignment("|:---|:---:|---:|---|")).toEqual(["left", "center", "right", null]);
  });

  it("given no leading or trailing pipe, then the columns still parse", () => {
    expect(parseTableAlignment(":--|--:")).toEqual(["left", "right"]);
  });

  it("given extra whitespace around a segment, then it is ignored", () => {
    expect(parseTableAlignment("| :--- | ---: |")).toEqual(["left", "right"]);
  });
});

describe("buildTableModel", () => {
  it("given a simple table, then the header and one row are extracted as plain text cells", () => {
    const doc = "| A | B |\n|---|---|\n| 1 | 2 |\n";
    const model = tableModelFor(doc);
    expect(model.align).toEqual([null, null]);
    expect(model.header.cells).toEqual([
      { align: null, spans: [{ kind: "text", text: "A" }] },
      { align: null, spans: [{ kind: "text", text: "B" }] },
    ]);
    expect(model.rows).toHaveLength(1);
    expect(model.rows[0]?.cells).toEqual([
      { align: null, spans: [{ kind: "text", text: "1" }] },
      { align: null, spans: [{ kind: "text", text: "2" }] },
    ]);
  });

  it("given declared column alignment, then each cell in the model carries its column's alignment", () => {
    const doc = "| A | B | C |\n|:---|:---:|---:|\n| 1 | 2 | 3 |\n";
    const model = tableModelFor(doc);
    expect(model.align).toEqual(["left", "center", "right"]);
    expect(model.header.cells.map((c) => c.align)).toEqual(["left", "center", "right"]);
    expect(model.rows[0]?.cells.map((c) => c.align)).toEqual(["left", "center", "right"]);
  });

  it("given bold text in a cell, then the cell's spans include a strong span with its marks stripped", () => {
    const doc = "| A |\n|---|\n| **bold** |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells[0]?.spans).toEqual([{ kind: "strong", children: [{ kind: "text", text: "bold" }] }]);
  });

  it("given italic text in a cell, then the cell's spans include an em span", () => {
    const doc = "| A |\n|---|\n| *italic* |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells[0]?.spans).toEqual([{ kind: "em", children: [{ kind: "text", text: "italic" }] }]);
  });

  it("given strikethrough text in a cell, then the cell's spans include a strike span", () => {
    const doc = "| A |\n|---|\n| ~~gone~~ |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells[0]?.spans).toEqual([{ kind: "strike", children: [{ kind: "text", text: "gone" }] }]);
  });

  it("given a code span in a cell, then the cell's spans include a code span with its backticks stripped", () => {
    const doc = "| A |\n|---|\n| `code` |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells[0]?.spans).toEqual([{ kind: "code", text: "code" }]);
  });

  it("given a link in a cell, then the cell's spans include a link span with its url and label", () => {
    const doc = "| A |\n|---|\n| [text](https://example.com) |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells[0]?.spans).toEqual([
      { kind: "link", url: "https://example.com", children: [{ kind: "text", text: "text" }] },
    ]);
  });

  it("given a bare autolink in a cell, then it becomes a link span over its own matched text", () => {
    const doc = "| A |\n|---|\n| see www.example.com |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells[0]?.spans).toEqual([
      { kind: "text", text: "see " },
      { kind: "link", url: "http://www.example.com", children: [{ kind: "text", text: "www.example.com" }] },
    ]);
  });

  it("given mixed plain text and formatting, then the cell's spans preserve surrounding text order", () => {
    const doc = "| A |\n|---|\n| pre **bold** post |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells[0]?.spans).toEqual([
      { kind: "text", text: "pre " },
      { kind: "strong", children: [{ kind: "text", text: "bold" }] },
      { kind: "text", text: " post" },
    ]);
  });

  it("given nested formatting inside a cell, then the nested span appears as a child, not flattened", () => {
    const doc = "| A |\n|---|\n| **_both_** |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells[0]?.spans).toEqual([
      { kind: "strong", children: [{ kind: "em", children: [{ kind: "text", text: "both" }] }] },
    ]);
  });

  it("given several body rows, then each is extracted in source order", () => {
    const doc = "| A |\n|---|\n| 1 |\n| 2 |\n| 3 |\n";
    const model = tableModelFor(doc);
    expect(model.rows.map((r) => r.cells[0]?.spans)).toEqual([
      [{ kind: "text", text: "1" }],
      [{ kind: "text", text: "2" }],
      [{ kind: "text", text: "3" }],
    ]);
  });

  it("given a ragged row with fewer cells than the header, then only the cells actually present are extracted", () => {
    const doc = "| A | B | C |\n|---|---|---|\n| 1 |\n";
    const model = tableModelFor(doc);
    expect(model.rows[0]?.cells).toHaveLength(1);
    expect(model.rows[0]?.cells[0]).toEqual({ align: null, spans: [{ kind: "text", text: "1" }] });
  });

  it("given a table with no body rows, then rows is an empty array and the header still parses", () => {
    const doc = "| A | B |\n|---|---|\n";
    const model = tableModelFor(doc);
    expect(model.rows).toEqual([]);
    expect(model.header.cells).toHaveLength(2);
  });
});
