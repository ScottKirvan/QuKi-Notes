import { EditorView } from "@codemirror/view";
import TurndownService from "turndown";

import { findImagePasteItem } from "./pasteImage";

const REMOVED_ELEMENTS = new Set([
  "script",
  "style",
  "noscript",
  "template",
  "iframe",
  "object",
  "embed",
  "head",
  "title",
  "meta",
  "link",
  "svg",
  "canvas",
  "button",
  "select",
  "textarea",
].map((name) => name.toUpperCase()));

const LINK_SCHEMES = /^(https?:|mailto:)/i;
const IMAGE_SCHEMES = /^https?:/i;

function closest(node: Node, nodeName: string): HTMLElement | null {
  let current = node.parentNode;
  while (current) {
    if (current.nodeName === nodeName) return current as HTMLElement;
    current = current.parentNode;
  }
  return null;
}

function elementChildren(node: Node): HTMLElement[] {
  return Array.from(node.childNodes).filter((child): child is HTMLElement => child.nodeType === 1);
}

function longestRun(text: string, char: string): number {
  let longest = 0;
  let current = 0;
  for (const c of text) {
    current = c === char ? current + 1 : 0;
    longest = Math.max(longest, current);
  }
  return longest;
}

function codeLanguage(node: HTMLElement): string {
  const classes = [node.getAttribute("class") ?? "", (node.parentNode as HTMLElement | null)?.getAttribute?.("class") ?? ""].join(" ");
  const match = /(?:language|lang|highlight-source|highlight-text)-([A-Za-z0-9_+#-]+)/.exec(classes);
  return match ? match[1]! : "";
}

function fenced(code: string, language: string): string {
  const fence = "`".repeat(Math.max(3, longestRun(code, "`") + 1));
  return `\n\n${fence}${language}\n${code.replace(/\n$/, "")}\n${fence}\n\n`;
}

function rowsOf(table: HTMLElement): HTMLElement[] {
  return Array.from(table.querySelectorAll("tr")).filter((row) => closest(row, "TABLE") === table) as HTMLElement[];
}

function cellsOf(row: HTMLElement): HTMLElement[] {
  return elementChildren(row).filter((cell) => cell.nodeName === "TD" || cell.nodeName === "TH");
}

function isCheckbox(node: HTMLElement): boolean {
  return node.nodeName === "INPUT" && (node.getAttribute("type") ?? "").toLowerCase() === "checkbox";
}

function createConverter(): TurndownService {
  const service = new TurndownService({
    headingStyle: "atx",
    hr: "---",
    br: "",
    bulletListMarker: "-",
    codeBlockStyle: "fenced",
    fence: "```",
    emDelimiter: "_",
    strongDelimiter: "**",
    linkStyle: "inlined",
  });

  service.remove((node) => REMOVED_ELEMENTS.has(node.nodeName));

  service.addRule("listItem", {
    filter: "li",
    replacement(content, node) {
      const parent = node.parentNode as HTMLElement | null;
      let prefix = "- ";
      if (parent?.nodeName === "OL") {
        const start = parent.getAttribute("start");
        const index = elementChildren(parent).indexOf(node as HTMLElement);
        prefix = `${start ? Number(start) + index : index + 1}. `;
      }
      const body = content
        .replace(/^\n+/, "")
        .replace(/\n+$/, "\n")
        .replace(/^\[( |x)\][ \t]+/, "[$1] ")
        .replace(/\n/g, "\n\t");
      return prefix + body + (node.nextSibling && !/\n\t?$/.test(body) ? "\n" : "");
    },
  });

  service.addRule("taskCheckbox", {
    filter: (node) => isCheckbox(node) && (closest(node, "LI") !== null),
    replacement(_content, node) {
      const input = node as HTMLInputElement;
      return input.checked || input.hasAttribute("checked") ? "[x] " : "[ ] ";
    },
  });

  service.addRule("strikethrough", {
    filter: (node) => ["DEL", "S", "STRIKE"].includes(node.nodeName),
    replacement: (content) => (content.trim() ? `~~${content}~~` : content),
  });

  // Google Docs wraps a whole copied selection in <b style="font-weight:normal">.
  service.addRule("notReallyBold", {
    filter: (node) =>
      (node.nodeName === "B" || node.nodeName === "STRONG") &&
      /font-weight\s*:\s*(normal|[1-4]00)\b/i.test(node.getAttribute("style") ?? ""),
    replacement: (content) => content,
  });

  service.addRule("link", {
    filter: (node) => node.nodeName === "A",
    replacement(content, node) {
      const href = ((node as HTMLElement).getAttribute("href") ?? "").trim();
      const text = content.replace(/\s*\n\s*/g, " ").trim();
      if (!LINK_SCHEMES.test(href)) return content;
      if (!text) return "";
      if (text === href || text === service.escape(href)) return href;
      return `[${text}](${href.replace(/[()\s]/g, encodeURIComponent)})`;
    },
  });

  service.addRule("image", {
    filter: "img",
    replacement(_content, node) {
      const src = ((node as HTMLElement).getAttribute("src") ?? "").trim();
      if (!IMAGE_SCHEMES.test(src)) return "";
      const alt = ((node as HTMLElement).getAttribute("alt") ?? "").replace(/\s+/g, " ").replace(/[[\]]/g, "\\$&").trim();
      return `![${alt}](${src.replace(/[()\s]/g, encodeURIComponent)})`;
    },
  });

  service.addRule("preWithoutCode", {
    filter: (node) => node.nodeName === "PRE" && node.firstElementChild?.nodeName !== "CODE",
    replacement: (_content, node) => fenced(node.textContent ?? "", codeLanguage(node as HTMLElement)),
  });

  service.addRule("fencedCodeBlock", {
    filter: (node) => node.nodeName === "PRE" && node.firstElementChild?.nodeName === "CODE",
    replacement(_content, node) {
      const code = node.firstElementChild as HTMLElement;
      return fenced(code.textContent ?? "", codeLanguage(code) || codeLanguage(node as HTMLElement));
    },
  });

  service.addRule("tableCell", {
    filter: ["th", "td"],
    replacement: (content) => ` ${content.replace(/\s*\n\s*/g, " ").trim().replace(/\|/g, "\\|")} |`,
  });

  service.addRule("tableRow", {
    filter: "tr",
    replacement(content, node) {
      const table = closest(node, "TABLE");
      if (!table) return content;
      const rows = rowsOf(table);
      const columns = Math.max(...rows.map((row) => cellsOf(row).length));
      const missing = columns - cellsOf(node as HTMLElement).length;
      const line = `|${content}${"  |".repeat(Math.max(0, missing))}`;
      if (rows[0] !== node) return `\n${line}`;
      return `\n${line}\n|${" --- |".repeat(columns)}`;
    },
  });

  service.addRule("tableSection", {
    filter: ["thead", "tbody", "tfoot"],
    replacement: (content) => content,
  });

  service.addRule("tableCaption", {
    filter: ["caption", "colgroup", "col"],
    replacement: () => "",
  });

  service.addRule("table", {
    filter: "table",
    replacement(content, node) {
      const caption = elementChildren(node).find((child) => child.nodeName === "CAPTION");
      const captionText = (caption?.textContent ?? "").replace(/\s+/g, " ").trim();
      const rows = content.replace(/\n+/g, "\n").trim();
      if (!rows) return "";
      return `\n\n${captionText ? `${service.escape(captionText)}\n\n` : ""}${rows}\n\n`;
    },
  });

  return service;
}

let converter: TurndownService | null = null;

export function htmlToMarkdown(html: string): string {
  converter ??= createConverter();
  return converter
    .turndown(html)
    .replace(/^[ \t]+$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function comparable(text: string): string {
  return text.replace(/\\([!-/:-@[-`{-~])/g, "$1").replace(/\s+/g, " ").trim();
}

/**
 * The markdown to insert for a paste carrying `text/html`, or null when the
 * paste should go in as its `text/plain` unchanged: the HTML is empty, or it
 * converts to nothing beyond the plain text itself (a code editor's
 * syntax-coloured spans around markdown source, say).
 */
export function markdownForHtmlPaste(html: string, plainText: string): string | null {
  if (!html.trim()) return null;
  const markdown = htmlToMarkdown(html);
  if (!markdown) return null;
  if (comparable(markdown) === comparable(plainText)) return null;
  return markdown;
}

export interface KeyLike {
  key: string;
  shiftKey: boolean;
  ctrlKey: boolean;
  metaKey: boolean;
  altKey: boolean;
}

export function isPlainTextPasteShortcut(event: KeyLike): boolean {
  return event.key.toLowerCase() === "v" && event.shiftKey && !event.altKey && event.ctrlKey !== event.metaKey;
}

function insertPaste(view: EditorView, text: string): void {
  view.dispatch({ ...view.state.replaceSelection(text), userEvent: "input.paste", scrollIntoView: true });
}

/**
 * Converts a paste's `text/html` to markdown. Leaves alone any paste
 * carrying an image (pasteImage.ts handles those), any paste whose HTML adds
 * nothing to its plain text, and a paste made with Ctrl+Shift+V
 * (Cmd+Shift+V): those fall through to CodeMirror's own plain-text paste.
 *
 * Chromium on Windows and Linux turns Ctrl+Shift+V into a paste event that
 * already carries only text/plain. Where the shortcut fires no paste event at
 * all (Chromium on macOS), the clipboard's text is read and inserted once the
 * keydown's own task has finished without one.
 */
export function createHtmlPastePlugin() {
  let plainTextRequested = false;

  return EditorView.domEventHandlers({
    keydown(event, view) {
      if (!isPlainTextPasteShortcut(event)) return false;
      plainTextRequested = true;
      setTimeout(() => {
        if (!plainTextRequested) return;
        plainTextRequested = false;
        navigator.clipboard?.readText().then(
          (text) => {
            if (text) insertPaste(view, text);
          },
          () => {},
        );
      }, 0);
      return false;
    },
    paste(event, view) {
      const plainTextOnly = plainTextRequested;
      plainTextRequested = false;
      const data = event.clipboardData;
      if (!data || plainTextOnly) return false;
      if (findImagePasteItem(data.items)) return false;
      const markdown = markdownForHtmlPaste(data.getData("text/html"), data.getData("text/plain"));
      if (markdown === null) return false;
      event.preventDefault();
      insertPaste(view, markdown);
      return true;
    },
  });
}
