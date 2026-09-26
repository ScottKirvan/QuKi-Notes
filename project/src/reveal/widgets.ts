import { type EditorView, WidgetType } from "@codemirror/view";
import { imageResolver } from "./imageResolver";
import { acquireImageUrl, releaseImageUrl } from "./imageUrlCache";
import { remoteImageFetcher } from "./remoteImageFetcher";
import { fetchRemoteImageBytes } from "./remoteImageCache";
import { toggleCheckboxAt } from "./checkboxTap";
import type { InlineSpan, TableAlign, TableModel } from "./tableModel";

const REMOTE_URL_PATTERN = /^https?:\/\//i;

/**
 * `this.src` is either a local markdown image path (e.g. "media/<name>.png")
 * or a remote `http(s)://` URL. toDOM() must return synchronously, so the
 * <img> is created immediately with no `src`, and the two kinds of source
 * are resolved through entirely separate facets/caches (imageResolver +
 * imageUrlCache for local OPFS reads, remoteImageFetcher + remoteImageCache
 * for network fetches — see remoteImageFetcher.ts for why these aren't one
 * resolver branching internally). Either path's failure (missing file,
 * storage error, network error, non-image response, or no
 * resolver/fetcher configured at all) falls back to the same broken-image
 * state rather than throwing or leaving the promise to reject uncaught.
 */
export class ImageWidget extends WidgetType {
  private acquiredPath: string | null = null;
  private remoteObjectUrl: string | null = null;

  constructor(
    readonly alt: string,
    readonly src: string,
  ) {
    super();
  }

  override eq(other: ImageWidget): boolean {
    return other.alt === this.alt && other.src === this.src;
  }

  toDOM(view: EditorView): HTMLElement {
    const img = document.createElement("img");
    img.alt = this.alt;
    img.className = "cm-quki-image";

    if (REMOTE_URL_PATTERN.test(this.src)) {
      const fetcher = view.state.facet(remoteImageFetcher);
      if (!fetcher) {
        img.classList.add("cm-quki-image-broken");
        return img;
      }

      fetchRemoteImageBytes(this.src, fetcher).then(
        ({ bytes, contentType }) => {
          const blob = new Blob([bytes as unknown as BlobPart], { type: contentType });
          this.remoteObjectUrl = URL.createObjectURL(blob);
          img.src = this.remoteObjectUrl;
        },
        () => {
          img.classList.add("cm-quki-image-broken");
        },
      );

      return img;
    }

    const resolve = view.state.facet(imageResolver);
    if (!resolve) {
      img.classList.add("cm-quki-image-broken");
      return img;
    }

    this.acquiredPath = this.src;
    acquireImageUrl(this.src, resolve).then(
      (url) => {
        img.src = url;
      },
      () => {
        img.classList.add("cm-quki-image-broken");
      },
    );

    return img;
  }

  override destroy(): void {
    if (this.acquiredPath !== null) {
      releaseImageUrl(this.acquiredPath);
      this.acquiredPath = null;
    }
    if (this.remoteObjectUrl !== null) {
      URL.revokeObjectURL(this.remoteObjectUrl);
      this.remoteObjectUrl = null;
    }
  }
}

export class HorizontalRuleWidget extends WidgetType {
  override eq(): boolean {
    return true;
  }

  toDOM(): HTMLElement {
    const hr = document.createElement("hr");
    hr.className = "cm-quki-hr";
    return hr;
  }
}

// Rule 7: a collapsed link is interactive (clickable/tappable). A revealed
// link is ordinary editable text with no special tap behavior — which is
// automatic here, since this widget only exists in the collapsed case.
export class LinkWidget extends WidgetType {
  constructor(
    readonly label: string,
    readonly url: string,
  ) {
    super();
  }

  override eq(other: LinkWidget): boolean {
    return other.label === this.label && other.url === this.url;
  }

  toDOM(): HTMLElement {
    const anchor = document.createElement("a");
    anchor.textContent = this.label.length > 0 ? this.label : this.url;
    anchor.href = this.url;
    anchor.target = "_blank";
    anchor.rel = "noopener noreferrer";
    anchor.className = "cm-quki-link";
    anchor.title = this.url;
    return anchor;
  }
}

// The marker's whole 24px gutter (20px label box plus its 4px gap) matches
// the Flutter editor's list-marker gutter: the marker is right-aligned in it
// and the item's content starts just past it.
export class BulletWidget extends WidgetType {
  override eq(): boolean {
    return true;
  }

  toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-quki-marker cm-quki-bullet";
    span.textContent = "•";
    return span;
  }
}

export class OrderedMarkerWidget extends WidgetType {
  constructor(readonly number: number) {
    super();
  }

  override eq(other: OrderedMarkerWidget): boolean {
    return other.number === this.number;
  }

  toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-quki-marker cm-quki-ordered";
    span.textContent = `${this.number}.`;
    return span;
  }
}

const SVG_NS = "http://www.w3.org/2000/svg";

function svgElement(tag: string, attrs: Record<string, string>): SVGElement {
  const el = document.createElementNS(SVG_NS, tag);
  for (const [name, value] of Object.entries(attrs)) el.setAttribute(name, value);
  return el;
}

// Drawn, not a Unicode glyph: font fallback picks a different font per text
// run on Android, so a ballot-box character can come out as a colour emoji.
// Proportions are the Flutter editor's painted box: an outlined rounded
// square with radius 0.2 of its side and a three-point round-capped tick.
function checkboxSvg(checked: boolean): SVGElement {
  const svg = svgElement("svg", {
    viewBox: "-6 -6 112 112",
    "aria-hidden": "true",
    focusable: "false",
  });
  svg.appendChild(
    svgElement("rect", {
      x: "0",
      y: "0",
      width: "100",
      height: "100",
      rx: "20",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": "10",
    }),
  );
  if (checked) {
    svg.appendChild(
      svgElement("polyline", {
        points: "20,52 42,74 82,28",
        fill: "none",
        stroke: "currentColor",
        "stroke-width": "11",
        "stroke-linecap": "round",
        "stroke-linejoin": "round",
      }),
    );
  }
  return svg;
}

// Rule 7: a collapsed checkbox is interactive, a revealed one is ordinary
// text — automatic here, since this widget only exists while collapsed.
//
// Tap handling is on the widget's own element (CodeMirror ignores events
// that originate in a widget). mousedown is cancelled so neither a mouse
// press nor the mouse events a touch tap synthesises can move the caret or
// take focus; the toggle itself happens on click, which both a mouse click
// and a touch tap produce.
export class CheckboxWidget extends WidgetType {
  constructor(readonly checked: boolean) {
    super();
  }

  override eq(other: CheckboxWidget): boolean {
    return other.checked === this.checked;
  }

  toDOM(view: EditorView): HTMLElement {
    const box = document.createElement("span");
    box.className = "cm-quki-marker cm-quki-checkbox";
    box.setAttribute("role", "checkbox");
    box.setAttribute("aria-checked", String(this.checked));
    box.appendChild(checkboxSvg(this.checked));
    box.addEventListener("mousedown", (event) => event.preventDefault());
    box.addEventListener("click", (event) => {
      event.preventDefault();
      toggleCheckboxAt(view, view.posAtDOM(box));
    });
    return box;
  }
}

function appendSpans(parent: HTMLElement, spans: readonly InlineSpan[]): void {
  for (const span of spans) appendSpan(parent, span);
}

function appendSpan(parent: HTMLElement, span: InlineSpan): void {
  switch (span.kind) {
    case "text":
      parent.appendChild(document.createTextNode(span.text));
      break;
    case "strong": {
      const el = document.createElement("strong");
      appendSpans(el, span.children);
      parent.appendChild(el);
      break;
    }
    case "em": {
      const el = document.createElement("em");
      appendSpans(el, span.children);
      parent.appendChild(el);
      break;
    }
    case "strike": {
      const el = document.createElement("del");
      appendSpans(el, span.children);
      parent.appendChild(el);
      break;
    }
    case "code": {
      const el = document.createElement("code");
      el.textContent = span.text;
      parent.appendChild(el);
      break;
    }
    case "link": {
      const a = document.createElement("a");
      a.href = span.url;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      a.className = "cm-quki-link";
      appendSpans(a, span.children);
      parent.appendChild(a);
      break;
    }
  }
}

function applyAlign(el: HTMLElement, align: TableAlign): void {
  if (align) el.style.textAlign = align;
}

// Render-only (issue #245): a table renders as a real <table>, but is never
// itself editable in this form - the reveal mechanism (rule 4, whole-element
// reveal like Image/HorizontalRule) is what lets its raw markdown be edited,
// by showing the source instead of this widget whenever the caret is inside
// it. An always-editable grid is a separate, later feature (issue #446).
export class TableWidget extends WidgetType {
  constructor(readonly model: TableModel) {
    super();
  }

  override eq(other: TableWidget): boolean {
    return JSON.stringify(other.model) === JSON.stringify(this.model);
  }

  toDOM(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "cm-quki-table-wrap";

    const table = document.createElement("table");
    table.className = "cm-quki-table";

    const thead = document.createElement("thead");
    const headRow = document.createElement("tr");
    for (const cell of this.model.header.cells) {
      const th = document.createElement("th");
      applyAlign(th, cell.align);
      appendSpans(th, cell.spans);
      headRow.appendChild(th);
    }
    thead.appendChild(headRow);
    table.appendChild(thead);

    const tbody = document.createElement("tbody");
    for (const row of this.model.rows) {
      const tr = document.createElement("tr");
      for (const cell of row.cells) {
        const td = document.createElement("td");
        applyAlign(td, cell.align);
        appendSpans(td, cell.spans);
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
    table.appendChild(tbody);

    wrap.appendChild(table);
    return wrap;
  }
}
