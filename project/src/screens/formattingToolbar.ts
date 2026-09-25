import type { EditorView, ViewUpdate } from "@codemirror/view";
import {
  Bold,
  Code,
  Heading,
  Heading1,
  Heading2,
  Heading3,
  IndentDecrease,
  IndentIncrease,
  Italic,
  List,
  ListChecks,
  ListOrdered,
  Strikethrough,
  createElement,
} from "lucide";

import { applyDedent, applyIndent } from "../toolbar/indentDedent";
import { cycleHeading, nextHeadingLevel } from "../toolbar/heading";
import { toggleCheckboxList, toggleOrderedList, toggleUnorderedList } from "../toolbar/listToggle";
import type { EditorValue } from "../toolbar/types";
import { wrapSelection } from "../toolbar/wrap";
import { currentHeadingLevel, runToolbarCommand } from "../toolbarAdapter";

type IconNode = Parameters<typeof createElement>[0];

// No Lucide icon reads as "plain text, not a heading" on its own — its own
// `Heading` icon is a bare "H" and would still look like some kind of
// heading. A hand-drawn single-stroke "n" (two curved legs, matching every
// other icon's outline style) turned out to be genuinely unrecognisable as
// the letter "n" at this size — confirmed directly, it read as an upside-
// down "u" instead. This is the actual lowercase "n" glyph from Arial
// (extracted via opentype.js's real glyph outline, not hand-drawn), scaled
// into the 24x24 icon grid. It's filled rather than stroked — fill/stroke
// are set explicitly on this one path, overriding the stroke-only default
// every other icon here inherits from `createElement`'s root <svg>, because
// an outline-only rendering of real letterform curves is exactly what read
// as ambiguous in the first place.
const NORMAL_TEXT_ICON: IconNode = [
  [
    "path",
    {
      d: "M9.38 19L7.45 19L7.45 7.59L9.19 7.59L9.19 9.21Q10.45 7.33 12.82 7.33Q13.85 7.33 14.72 7.70Q15.58 8.08 16.01 8.68Q16.44 9.28 16.61 10.11Q16.72 10.64 16.72 11.99L16.72 19L14.79 19L14.79 12.06Q14.79 10.88 14.56 10.29Q14.34 9.71 13.76 9.36Q13.19 9.01 12.41 9.01Q11.18 9.01 10.28 9.79Q9.38 10.58 9.38 12.77Z",
      fill: "currentColor",
      stroke: "none",
    },
  ],
];

/**
 * BEHAVIOR_SPEC.md's heading-cycle rewrite ("normal -> H1 -> H2 -> H3 ->
 * normal") pairs with "the icon explains itself": the button should show
 * what clicking WILL produce next, not the level currently under the caret.
 * Keyed by `nextHeadingLevel`'s result, which is always 0-3 — it already
 * collapses H3 and any hand-typed H4-H6 line alike down to 0 ("normal"),
 * matching `cycleHeading`'s own next-press behavior on such a line.
 */
const HEADING_ICONS: Record<number, IconNode> = {
  0: NORMAL_TEXT_ICON,
  1: Heading1,
  2: Heading2,
  3: Heading3,
};

function iconElement(iconNode: IconNode): SVGElement {
  return createElement(iconNode, { width: 18, height: 18, "aria-hidden": "true", focusable: "false" });
}

function makeButton(iconNode: IconNode, label: string, onClick: () => void): HTMLButtonElement {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "toolbar-btn";
  button.title = label;
  button.setAttribute("aria-label", label);
  button.replaceChildren(iconElement(iconNode));
  // mousedown (not click) fires first, before the button would otherwise
  // take focus away from the editor - preventing default here means the
  // editor's selection is never disturbed by the click itself, and
  // runToolbarCommand's view.focus() below is then just belt-and-braces.
  button.addEventListener("mousedown", (event) => event.preventDefault());
  button.addEventListener("click", onClick);
  return button;
}

export interface FormattingToolbarHandle {
  /** Shown in edit mode, hidden in reading mode — BEHAVIOR_SPEC.md §4. Driven by editMode.ts's tracker; see main.ts. */
  setVisible(visible: boolean): void;
  /** Forwarded from main.ts's EditorView.updateListener so the heading icon tracks the caret's line. */
  onUpdate(update: ViewUpdate): void;
  /**
   * The toolbar's own rendered height in px while visible, 0 while hidden.
   * style.css positions the toolbar `absolute`, overlaying the bottom of
   * the editor's own scroller rather than pushing it up — `.cm-content`'s
   * matching `padding-bottom: 36px` keeps a *stationary* last line clear of
   * it, but CodeMirror's automatic scroll-into-view (on typing, on the
   * caret moving) has no way to know that band of the scroller is visually
   * covered, so a caret arriving at the true bottom of a long QuKi can land
   * underneath the toolbar instead of above it. Confirmed on a real Android
   * emulator: with the keyboard up shrinking the scroller, this is the
   * common case, not an edge case (chunk 3's report has the reproduction).
   * main.ts feeds this into EditorView.scrollMargins so CodeMirror keeps
   * this much clearance below the caret — the mechanism the library itself
   * documents for exactly this situation ("the plugin introduces elements
   * that cover part of [the scrolling element]").
   */
  scrollMarginBottom(): number;
}

/**
 * Builds the ten-button formatting toolbar (BEHAVIOR_SPEC.md "Formatting
 * toolbar — ten buttons") and mounts it into `container`. Button order,
 * icons and inline delimiters match formatting_toolbar.dart exactly, aside
 * from the heading button, which BEHAVIOR_SPEC.md explicitly changes from
 * an H1-only toggle to the normal/H1/H2/H3 cycle `toolbar/heading.ts`
 * implements.
 *
 * Every button routes through `runToolbarCommand`, which dispatches a real
 * transaction (auto-save-triggering, undoable) and returns focus to the
 * editor — never the suppressed programmatic-load path `main.ts` uses when
 * switching QuKis.
 */
export function createFormattingToolbar(view: EditorView, container: HTMLElement): FormattingToolbarHandle {
  const element = document.createElement("div");
  element.className = "formatting-toolbar";
  element.setAttribute("role", "toolbar");
  element.setAttribute("aria-label", "Formatting");
  element.hidden = true;

  function run(command: (value: EditorValue) => EditorValue): void {
    runToolbarCommand(view, command);
  }

  const headingButton = makeButton(Heading, "Heading", () => run(cycleHeading));

  element.append(
    makeButton(Bold, "Bold", () => run((v) => wrapSelection(v, "**", "**"))),
    makeButton(Italic, "Italic", () => run((v) => wrapSelection(v, "_", "_"))),
    makeButton(Strikethrough, "Strikethrough", () => run((v) => wrapSelection(v, "~~", "~~"))),
    makeButton(Code, "Inline code", () => run((v) => wrapSelection(v, "`", "`"))),
    headingButton,
    makeButton(List, "Unordered list", () => run(toggleUnorderedList)),
    makeButton(ListOrdered, "Ordered list", () => run(toggleOrderedList)),
    makeButton(ListChecks, "Task list", () => run(toggleCheckboxList)),
    makeButton(IndentIncrease, "Indent", () => run(applyIndent)),
    makeButton(IndentDecrease, "Dedent", () => run(applyDedent)),
  );

  container.appendChild(element);

  function updateHeadingIcon(): void {
    const nextLevel = nextHeadingLevel(currentHeadingLevel(view.state));
    headingButton.replaceChildren(iconElement(HEADING_ICONS[nextLevel] ?? NORMAL_TEXT_ICON));
  }
  updateHeadingIcon();

  return {
    setVisible(visible: boolean): void {
      element.hidden = !visible;
    },
    onUpdate(update: ViewUpdate): void {
      if (update.docChanged || update.selectionSet) updateHeadingIcon();
    },
    scrollMarginBottom(): number {
      // `element.hidden` (display: none) makes getBoundingClientRect()
      // report a zero-height rect on its own, so there's no separate
      // visible/hidden branch to keep in sync with setVisible above.
      return element.getBoundingClientRect().height;
    },
  };
}
