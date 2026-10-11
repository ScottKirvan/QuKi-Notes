import { EditorView } from "@codemirror/view";
import type { Extension } from "@codemirror/state";

export const FONT_SIZES = [
  { id: "small", label: "Small", px: 14 },
  { id: "normal", label: "Normal", px: 16 },
  { id: "large", label: "Large", px: 19 },
  { id: "extra-large", label: "Extra large", px: 22 },
] as const;

export type FontSize = (typeof FONT_SIZES)[number]["id"];

export const DEFAULT_FONT_SIZE: FontSize = "normal";

export function parseFontSize(raw: string | null): FontSize {
  return FONT_SIZES.find((size) => size.id === raw)?.id ?? DEFAULT_FONT_SIZE;
}

export function fontSizePx(size: FontSize): number {
  return FONT_SIZES.find((step) => step.id === size)!.px;
}

const themes = new Map<FontSize, Extension>();

/** The editor's text size; everything else in the editor is sized in em, so it scales with this. */
export function editorFontSizeTheme(size: FontSize): Extension {
  let theme = themes.get(size);
  if (!theme) {
    theme = EditorView.theme({ "&": { fontSize: `${fontSizePx(size)}px` } });
    themes.set(size, theme);
  }
  return theme;
}
