import type { MenuItemConstructorOptions } from 'electron';

export interface MisspellingContext {
  misspelledWord: string;
  dictionarySuggestions: string[];
}

export interface SpellingActions {
  replaceMisspelling(word: string): void;
  addToDictionary(word: string): void;
}

export function spellingMenuTemplate(
  context: MisspellingContext,
  actions: SpellingActions,
): MenuItemConstructorOptions[] {
  const word = context.misspelledWord;
  if (!word) return [];
  const suggestions: MenuItemConstructorOptions[] =
    context.dictionarySuggestions.length > 0
      ? context.dictionarySuggestions.map((suggestion) => ({
          label: suggestion,
          click: () => actions.replaceMisspelling(suggestion),
        }))
      : [{ label: 'No suggestions', enabled: false }];
  return [
    ...suggestions,
    { type: 'separator' },
    { label: 'Add to dictionary', click: () => actions.addToDictionary(word) },
  ];
}
