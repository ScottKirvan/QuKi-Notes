import { EditorView } from "@codemirror/view";
import type { StateEffect } from "@codemirror/state";

/**
 * Where the text at `pos` starts on screen; its line's block when the
 * editor hasn't drawn it.
 */
function screenTop(view: EditorView, pos: number): number {
  return view.coordsAtPos(pos, 1)?.top ?? view.documentTop + view.lineBlockAt(pos).top;
}

/**
 * An effect that, dispatched with a change to how the text is drawn, keeps
 * the text the user is looking at at the same height on screen. The anchor
 * is the first line whose top is at or below the top edge of the visible
 * area, so a line partly scrolled off the top (a tall image) never anchors;
 * with `caret` and the caret's line on screen, that line anchors instead.
 */
export function keepVisibleTextInPlace(view: EditorView, caret?: number): StateEffect<unknown> {
  const top = view.scrollDOM.getBoundingClientRect().top;
  const bottom = top + view.scrollDOM.clientHeight;
  let anchor: number | null = null;
  if (caret !== undefined) {
    const caretLine = view.lineBlockAt(caret).from;
    const caretTop = screenTop(view, caretLine);
    if (caretTop >= top && caretTop < bottom) anchor = caretLine;
  }
  if (anchor === null) {
    let block = view.lineBlockAtHeight(top - view.documentTop);
    if (view.documentTop + block.top < top && block.to < view.state.doc.length) block = view.lineBlockAt(block.to + 1);
    anchor = block.from;
  }
  return EditorView.scrollIntoView(anchor, { y: "start", yMargin: screenTop(view, anchor) - top });
}
