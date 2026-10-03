export interface QuKisButtonInputs {
  hasSavedQuKis: boolean;
  editorHasText: boolean;
}

// Typed text counts before its debounced save lands: the button saves on the
// way out (flush), so the list it opens will have that QuKi.
export function isQuKisButtonEnabled({ hasSavedQuKis, editorHasText }: QuKisButtonInputs): boolean {
  return hasSavedQuKis || editorHasText;
}
