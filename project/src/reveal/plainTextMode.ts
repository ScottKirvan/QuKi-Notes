import { StateEffect, StateField } from "@codemirror/state";

export const setPlainTextMode = StateEffect.define<boolean>();

/**
 * Rule 6: plain-text mode passes an invalid caret position into the reveal
 * engine, so nothing is ever revealed and nothing is ever collapsed. This
 * field just tracks the toggle; computeReveal.ts is what turns "plain text
 * mode is on" into caret === null.
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
});
