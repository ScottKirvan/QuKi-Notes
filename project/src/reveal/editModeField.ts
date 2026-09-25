import { type EditorState, StateEffect, StateField } from "@codemirror/state";

export const setEditMode = StateEffect.define<boolean>();

/**
 * Whether the editor is genuinely in edit mode right now, per
 * editMode.ts's createEditModeTracker (real DOM focus, or on Android,
 * Capacitor's keyboard-visibility signal) - not derived from the caret's
 * raw position. buildDecorations reads this before treating
 * state.selection.main.anchor as a meaningful reveal target: BEHAVIOR_SPEC
 * §4's reading mode has no real cursor position at all, so a caret sitting
 * wherever a load last reset it to (main.ts's loadDocumentIntoEditor always
 * dispatches `selection: { anchor: 0 }`, even for an existing QuKi opened
 * into reading mode) must not be mistaken for the user actually editing
 * there.
 *
 * Defaults to true so any EditorState assembled without this field wired
 * in (every pre-existing decorations.test.ts fixture) keeps behaving
 * exactly as it did before this field existed - reveal driven purely by
 * caret position.
 */
export const editModeField = StateField.define<boolean>({
  create: () => true,
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setEditMode)) {
        value = effect.value;
      }
    }
    return value;
  },
});

/** state.field(editModeField) with the field's own "unwired" default applied. */
export function isEditMode(state: EditorState): boolean {
  return state.field(editModeField, false) ?? true;
}
