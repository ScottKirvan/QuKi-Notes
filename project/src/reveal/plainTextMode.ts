import { StateEffect, StateField } from "@codemirror/state";
import { EditorView } from "@codemirror/view";

export const setPlainTextMode = StateEffect.define<boolean>();

export const PLAIN_TEXT_CLASS = "cm-quki-plain-text";

/**
 * Rule 6: plain-text mode passes an invalid caret position into the reveal
 * engine, so nothing is ever revealed and nothing is ever collapsed. This
 * field just tracks the toggle; computeReveal.ts is what turns "plain text
 * mode is on" into caret === null. The editor carries PLAIN_TEXT_CLASS while
 * it is on, so the raw-source surface can be styled as one.
 */
export const plainTextMode = StateField.define<boolean>({
  create: () => false,
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setPlainTextMode)) {
        value = effect.value;
      }
    }
    return value;
  },
  provide: (field) => EditorView.editorAttributes.from(field, (on): Record<string, string> => (on ? { class: PLAIN_TEXT_CLASS } : {})),
});
