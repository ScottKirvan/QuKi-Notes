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
import { cycleHeading } from "../toolbar/heading";
import { toggleCheckboxList, toggleOrderedList, toggleUnorderedList } from "../toolbar/listToggle";
import type { EditorValue } from "../toolbar/types";
import { wrapSelection } from "../toolbar/wrap";
import { currentHeadingLevel, runToolbarCommand } from "../toolbarAdapter";

type IconNode = Parameters<typeof createElement>[0];

/**
 * BEHAVIOR_SPEC.md's heading-cycle rewrite ("normal -> H1 -> H2 -> H3 ->
 * normal... The icon tracks the current level") — `cycleHeading`
 * (toolbar/heading.ts) never produces a level past 3, so levels 4-6 never
 * reach this map; `currentHeadingLevel` can still return them for a line
 * the toolbar didn't create (typed by hand, or ported content), which the
 * `?? Heading` fallback below treats the same as "normal".
 */
const HEADING_ICONS: Record<number, IconNode> = {
  0: Heading,
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
    const level = currentHeadingLevel(view.state);
    headingButton.replaceChildren(iconElement(HEADING_ICONS[level] ?? Heading));
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
