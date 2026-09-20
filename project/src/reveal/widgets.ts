import { type EditorView, WidgetType } from "@codemirror/view";
import { imageResolver } from "./imageResolver";
import { acquireImageUrl, releaseImageUrl } from "./imageUrlCache";

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
