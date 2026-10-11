import type { SyntaxNode } from "@lezer/common";

export interface LinkParts {
  labelFrom: number;
  labelTo: number;
  destination: SyntaxNode | null;
}

// GFM's Autolink extension also emits "URL" nodes inside a Link's or Image's
// label, ahead of the destination's own URL node, so the destination is the
// URL child that starts after the label's closing "]" mark.
export function linkParts(node: SyntaxNode): LinkParts {
  const marks = node.getChildren("LinkMark");
  const labelFrom = marks.length >= 1 ? marks[0]!.to : node.from;
  const labelTo = marks.length >= 2 ? marks[1]!.from : node.to;
  const destinationStart = marks.length >= 2 ? marks[1]!.to : node.to;
  const destination =
    node.getChildren("URL").find((url) => url.from >= destinationStart) ?? null;
  return { labelFrom, labelTo, destination };
}
