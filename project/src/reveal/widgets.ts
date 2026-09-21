import { type EditorView, WidgetType } from "@codemirror/view";
import { imageResolver } from "./imageResolver";
import { acquireImageUrl, releaseImageUrl } from "./imageUrlCache";
import { toggleCheckboxAt } from "./checkboxTap";

/**
 * `this.src` is a markdown image path (e.g. "media/<name>.png"), not a URL
 * the browser can request — OPFS serves nothing over HTTP. toDOM() must
 * return synchronously, so the <img> is created immediately with no `src`
 * and the real blob: URL is attached once the configured imageResolver
 * (wired up in main.ts, backed by OpfsBackend) finishes reading the bytes.
 * A read failure (missing file, storage error) or no resolver being
 * configured at all both fall back to the same broken-image state rather
 * than throwing or leaving the promise to reject uncaught.
 */
export class ImageWidget extends WidgetType {
  private acquiredPath: string | null = null;

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
