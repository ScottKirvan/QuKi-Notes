import type { RevealElement } from "./types";

/**
 * Decide which elements reveal their raw markdown source for a given caret
 * position. Pure function, no CodeMirror dependency — see BEHAVIOR_SPEC.md
 * section 12, "Reveal semantics", for the rules this implements.
 *
 * `caret === null` is plain-text mode (rule 6): nothing is ever revealed.
 */
export function computeRevealedIds(
  elements: RevealElement[],
  caret: number | null,
): Set<number> {
  const revealed = new Set<number>();
  if (caret === null) {
    return revealed;
  }

  // Rule 3/4: block markers (and whole-line elements, which degenerate to
  // the same check) are independent of each other and of inline nesting.
  for (const el of elements) {
    if (el.category !== "block-marker") continue;
    if (el.checkStart <= caret && caret <= el.checkEnd) {
      revealed.add(el.id);
    }
  }

  // Rule 1/2: inline elements nest. Find every inline element whose span
  // contains the caret, then keep only the ones with no candidate ancestor
  // — those are the outermost reveal units. Because ranges nest, any
  // ancestor of a candidate is itself always a candidate (its span strictly
  // contains the child's), so this reduces to "root of the candidate
  // chain", not an approximation.
  const inlineElements = elements.filter((el) => el.category === "inline");
  const candidates = inlineElements.filter(
    (el) => el.checkStart <= caret && caret <= el.checkEnd,
  );
  const candidateIds = new Set(candidates.map((el) => el.id));
  const roots = candidates.filter(
    (el) => el.parentId === null || !candidateIds.has(el.parentId),
  );

  const childrenByParent = new Map<number, number[]>();
  for (const el of inlineElements) {
    if (el.parentId === null) continue;
    const siblings = childrenByParent.get(el.parentId);
    if (siblings) {
      siblings.push(el.id);
    } else {
      childrenByParent.set(el.parentId, [el.id]);
    }
  }

  const absorb = (id: number): void => {
    revealed.add(id);
    for (const childId of childrenByParent.get(id) ?? []) {
      absorb(childId);
    }
  };
  for (const root of roots) {
    absorb(root.id);
  }

  return revealed;
}

/**
 * Rule 5: with a selection, reveal resolves against the anchor (where the
 * selection began), never the moving head, and never a merge of both.
 */
export function caretForReveal(selection: {
  anchor: number;
}): number {
  return selection.anchor;
}
