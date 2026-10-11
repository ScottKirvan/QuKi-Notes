import { describe, expect, it } from "vitest";

import { htmlToMarkdown, isPlainTextPasteShortcut, markdownForHtmlPaste } from "./pasteHtml.js";

describe("htmlToMarkdown", () => {
  it("writes bullet lists with - and nests them one tab per level", () => {
    const html = "<ul><li>one<ul><li>two<ul><li>three</li></ul></li></ul></li><li>four</li></ul>";
    expect(htmlToMarkdown(html)).toBe("- one\n\t- two\n\t\t- three\n- four");
  });

  it("numbers ordered lists, honouring start", () => {
    expect(htmlToMarkdown("<ol><li>a</li><li>b</li></ol>")).toBe("1. a\n2. b");
    expect(htmlToMarkdown('<ol start="4"><li>a</li><li>b</li></ol>')).toBe("4. a\n5. b");
  });

  it("nests a bullet list under a numbered item with a tab", () => {
    expect(htmlToMarkdown("<ol><li>a<ul><li>x</li></ul></li><li>b</li></ol>")).toBe("1. a\n\t- x\n2. b");
  });

  it("writes task list items from checkboxes", () => {
    const html =
      '<ul><li><input type="checkbox" disabled> todo</li><li><input type="checkbox" checked disabled> done</li></ul>';
    expect(htmlToMarkdown(html)).toBe("- [ ] todo\n- [x] done");
  });

  it("writes atx headings", () => {
    expect(htmlToMarkdown("<h1>Title</h1><h3>Sub</h3><p>text</p>")).toBe("# Title\n\n### Sub\n\ntext");
  });

  it("writes bold, italic, strikethrough and inline code in the app's style", () => {
    expect(htmlToMarkdown("<p><strong>b</strong> <em>i</em> <del>s</del> <code>c</code></p>")).toBe(
      "**b** _i_ ~~s~~ `c`",
    );
    expect(htmlToMarkdown("<p><b>b</b> <i>i</i> <s>s</s></p>")).toBe("**b** _i_ ~~s~~");
  });

  it("writes links, and a bare URL when the text is the URL", () => {
    expect(htmlToMarkdown('<p>see <a href="https://example.com/a">the docs</a></p>')).toBe(
      "see [the docs](https://example.com/a)",
    );
    expect(htmlToMarkdown('<a href="https://example.com/">https://example.com/</a>')).toBe("https://example.com/");
  });

  it("keeps only the text of links that are not web or mail links", () => {
    expect(htmlToMarkdown('<p><a href="javascript:alert(1)">click</a> <a href="#top">top</a></p>')).toBe("click top");
  });

  it("writes fenced code blocks with the language, with or without a <code> element", () => {
    expect(htmlToMarkdown('<pre><code class="language-js">let a = 1;\nlet b = 2;\n</code></pre>')).toBe(
      "```js\nlet a = 1;\nlet b = 2;\n```",
    );
    expect(htmlToMarkdown('<div class="highlight highlight-source-python"><pre>print("hi")</pre></div>')).toBe(
      '```python\nprint("hi")\n```',
    );
  });

  it("lengthens the fence when the code itself contains a fence", () => {
    expect(htmlToMarkdown("<pre><code>```\nx\n```</code></pre>")).toBe("````\n```\nx\n```\n````");
  });

  it("writes blockquotes", () => {
    expect(htmlToMarkdown("<blockquote><p>quoted</p><p>more</p></blockquote>")).toBe("> quoted\n> \n> more");
  });

  it("writes GFM tables, with a header row taken from thead or the first row", () => {
    const withHead =
      "<table><thead><tr><th>Name</th><th>Qty</th></tr></thead><tbody><tr><td><b>apple</b></td><td>2</td></tr></tbody></table>";
    expect(htmlToMarkdown(withHead)).toBe("| Name | Qty |\n| --- | --- |\n| **apple** | 2 |");
    const noHead = "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d|e</td></tr></table>";
    expect(htmlToMarkdown(noHead)).toBe("| a | b |\n| --- | --- |\n| c | d\\|e |");
  });

  it("pads short table rows to the widest row", () => {
    expect(htmlToMarkdown("<table><tr><th>a</th><th>b</th></tr><tr><td>c</td></tr></table>")).toBe(
      "| a | b |\n| --- | --- |\n| c |  |",
    );
  });

  it("links web images by URL and drops images with no web URL", () => {
    expect(htmlToMarkdown('<p><img src="https://example.com/cat.png" alt="a cat"></p>')).toBe(
      "![a cat](https://example.com/cat.png)",
    );
    expect(htmlToMarkdown('<p>x<img src="data:image/png;base64,AAAA" alt="inline"></p>')).toBe("x");
  });

  it("strips scripts, styles, comments and other non-content markup", () => {
    const html =
      '<style>p{color:red}</style><script>alert(1)</script><!-- tracking --><p>kept</p><noscript><img src="https://t.example/pixel.gif"></noscript><iframe src="https://ads.example"></iframe>';
    expect(htmlToMarkdown(html)).toBe("kept");
  });

  it("converts a messy real-world snippet with spans, styles and fragment markers", () => {
    const html = [
      '<html><body><!--StartFragment--><meta charset="utf-8">',
      '<h2 style="margin:0;font-family:Arial" class="mw-heading"><span id="History" class="mw-headline">History</span>',
      '<span class="mw-editsection"><span>[</span><a href="/w/edit">edit</a><span>]</span></span></h2>',
      '<p style="color: rgb(32, 33, 34);"><span style="font-size:14px">The <b><span class="x">first</span></b> ',
      '<a href="https://en.wikipedia.org/wiki/Note" title="Note" style="color:blue">note</a> was <i>written</i>.</span>',
      '<sup class="reference"><a href="#cite-1">[1]</a></sup></p>',
      '<div class="list-wrap"><ul style="list-style:disc"><li><span>Alpha</span></li>',
      '<li><span style="font-weight:400">Beta</span><ul><li>Gamma</li></ul></li></ul></div>',
      "<!--EndFragment--></body></html>",
    ].join("");
    expect(htmlToMarkdown(html)).toBe(
      "## History\\[edit\\]\n\nThe **first** [note](https://en.wikipedia.org/wiki/Note) was _written_.\\[1\\]\n\n- Alpha\n- Beta\n\t- Gamma",
    );
  });

  it("does not make a Google Docs paste bold because of its font-weight:normal wrapper", () => {
    const html =
      '<meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-1"><p dir="ltr"><span>Plain words</span></p><ul><li><span>item</span></li></ul></b>';
    expect(htmlToMarkdown(html)).toBe("Plain words\n\n- item");
  });
});

describe("markdownForHtmlPaste", () => {
  it("returns the converted markdown when the HTML carries formatting the plain text lacks", () => {
    expect(markdownForHtmlPaste("<ul><li>a</li><li>b</li></ul>", "a\nb")).toBe("- a\n- b");
  });

  it("returns null for HTML that only wraps the plain text (markdown copied from a code editor)", () => {
    const html =
      '<div style="color:#ccc;white-space:pre"><div><span style="color:#569cd6">- </span><span>item with **bold** and 1. text</span></div><div><span>\t- nested</span></div></div>';
    expect(markdownForHtmlPaste(html, "- item with **bold** and 1. text\n\t- nested")).toBeNull();
  });

  it("returns null for plain paragraphs, which paste the same either way", () => {
    expect(markdownForHtmlPaste("<p>hello there</p>", "hello there")).toBeNull();
  });

  it("returns null for empty or content-free HTML", () => {
    expect(markdownForHtmlPaste("", "text")).toBeNull();
    expect(markdownForHtmlPaste("<script>alert(1)</script>", "text")).toBeNull();
  });

  it("returns null for a link whose text is its own URL, so the URL pastes as text", () => {
    expect(markdownForHtmlPaste('<a href="https://example.com/">https://example.com/</a>', "https://example.com/")).toBeNull();
  });
});

describe("isPlainTextPasteShortcut", () => {
  const key = (overrides: Partial<{ key: string; shiftKey: boolean; ctrlKey: boolean; metaKey: boolean; altKey: boolean }>) => ({
    key: "V",
    shiftKey: true,
    ctrlKey: false,
    metaKey: false,
    altKey: false,
    ...overrides,
  });

  it("matches Ctrl+Shift+V and Cmd+Shift+V", () => {
    expect(isPlainTextPasteShortcut(key({ ctrlKey: true }))).toBe(true);
    expect(isPlainTextPasteShortcut(key({ metaKey: true }))).toBe(true);
    expect(isPlainTextPasteShortcut(key({ ctrlKey: true, key: "v" }))).toBe(true);
  });

  it("does not match an ordinary paste or other combinations", () => {
    expect(isPlainTextPasteShortcut(key({ ctrlKey: true, shiftKey: false, key: "v" }))).toBe(false);
    expect(isPlainTextPasteShortcut(key({ ctrlKey: true, altKey: true }))).toBe(false);
    expect(isPlainTextPasteShortcut(key({}))).toBe(false);
    expect(isPlainTextPasteShortcut(key({ ctrlKey: true, key: "C" }))).toBe(false);
  });
});
