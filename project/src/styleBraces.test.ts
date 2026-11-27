import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

function braceBalance(css: string): number {
  const withoutCommentsAndStrings = css.replace(/\/\*[\s\S]*?\*\//g, "").replace(/"(?:[^"\\n]|\.)*"|'(?:[^'\\n]|\.)*'/g, '""');
  let depth = 0;
  for (const char of withoutCommentsAndStrings) {
    if (char === "{") depth++;
    if (char === "}") depth--;
    if (depth < 0) return depth;
  }
  return depth;
}

describe("style.css", () => {
  it("given the app stylesheet, when its braces are counted, then every rule is closed and none is stray", () => {
    const css = readFileSync(new URL("./style.css", import.meta.url), "utf8");
    expect(braceBalance(css)).toBe(0);
  });

  it("given a rule that is never closed, when its braces are counted, then the balance is not zero", () => {
    expect(braceBalance(".a { color: red;\n.b { color: blue; }")).toBe(1);
  });

  it("given a closing brace with no opener, when its braces are counted, then the balance is negative", () => {
    expect(braceBalance(".a { color: red; } }")).toBeLessThan(0);
  });

  it("given braces inside a comment or a string, when its braces are counted, then they are ignored", () => {
    expect(braceBalance('/* { */ .a::before { content: "}"; }')).toBe(0);
  });
});
