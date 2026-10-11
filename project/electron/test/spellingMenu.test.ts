import { describe, expect, it, vi } from 'vitest';

import { spellingMenuTemplate } from '../src/spellingMenu.js';

function actions() {
  return { replaceMisspelling: vi.fn(), addToDictionary: vi.fn() };
}

describe('spellingMenuTemplate', () => {
  it('offers no menu when the right-clicked word is spelled correctly', () => {
    expect(spellingMenuTemplate({ misspelledWord: '', dictionarySuggestions: [] }, actions())).toEqual([]);
  });

  it('lists each suggestion, and choosing one replaces the misspelling with it', () => {
    const a = actions();
    const template = spellingMenuTemplate({ misspelledWord: 'teh', dictionarySuggestions: ['the', 'ten'] }, a);
    expect(template.map((item) => item.label ?? item.type)).toEqual(['the', 'ten', 'separator', 'Add to dictionary']);
    template[1]!.click!({} as never, undefined, {} as never);
    expect(a.replaceMisspelling).toHaveBeenCalledWith('ten');
  });

  it('says there are no suggestions when the spellchecker has none', () => {
    const template = spellingMenuTemplate({ misspelledWord: 'qwzx', dictionarySuggestions: [] }, actions());
    expect(template[0]).toMatchObject({ label: 'No suggestions', enabled: false });
  });

  it('adds the misspelled word itself to the dictionary', () => {
    const a = actions();
    const template = spellingMenuTemplate({ misspelledWord: 'QuKi', dictionarySuggestions: ['Quick'] }, a);
    template.at(-1)!.click!({} as never, undefined, {} as never);
    expect(a.addToDictionary).toHaveBeenCalledWith('QuKi');
  });
});
