import { EditorView, ViewPlugin } from "@codemirror/view";
import type { Extension } from "@codemirror/state";

export const CLEARANCE_LINES = 2;

/** How far above the scroller's bottom edge the caret must stay: the toolbar, plus two lines while it shows. */
export function bottomScrollMargin(toolbarHeight: number, lineHeight: number): number {
  return toolbarHeight > 0 ? toolbarHeight + CLEARANCE_LINES * lineHeight : 0;
}

/** Whether the editor shrinking (the keyboard rising) while the toolbar shows may have covered the caret. */
export function shouldRevealCaretAfterResize(previousHeight: number, height: number, toolbarHeight: number): boolean {
  return toolbarHeight > 0 && height < previousHeight;
}

/**
 * Keeps the caret two lines clear of the formatting toolbar whenever the
 * editor scrolls it into view. The toolbar overlays the bottom of the
 * scroller, so CodeMirror only knows about it through scrollMargins.
 *
 * The last line needs that room below it too, so the content's bottom
 * padding grows by the same two lines (through --quki-caret-clearance).
 *
 * The scroller shrinking while editing (Android's keyboard rising after the
 * tap that focused the editor) scrolls nothing on its own; that case
 * reveals the caret again once the new size has landed.
 */
export function keepCaretClearOfToolbar(toolbarHeight: () => number): Extension {
  const plugin = ViewPlugin.define((view) => {
    let lastLineHeight = 0;
    const syncPadding = (): void => {
      view.requestMeasure({
        read: (v) => v.defaultLineHeight,
        write: (lineHeight, v) => {
          if (lineHeight === lastLineHeight) return;
          lastLineHeight = lineHeight;
          v.scrollDOM.style.setProperty("--quki-caret-clearance", `${CLEARANCE_LINES * lineHeight}px`);
        },
      });
    };
    syncPadding();

    let previousHeight = view.scrollDOM.clientHeight;
    const observer = new ResizeObserver(() => {
      const height = view.scrollDOM.clientHeight;
      const reveal = shouldRevealCaretAfterResize(previousHeight, height, toolbarHeight());
      previousHeight = height;
      if (reveal) view.dispatch({ effects: EditorView.scrollIntoView(view.state.selection.main.head) });
    });
    observer.observe(view.scrollDOM);

    return {
      update(update) {
        if (update.geometryChanged) syncPadding();
      },
      destroy() {
        observer.disconnect();
      },
    };
  });

  return [plugin, EditorView.scrollMargins.of((view) => ({ bottom: bottomScrollMargin(toolbarHeight(), view.defaultLineHeight) }))];
}
