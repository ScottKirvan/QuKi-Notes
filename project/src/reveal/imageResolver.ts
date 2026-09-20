import { Facet } from "@codemirror/state";

/**
 * Resolves a markdown image link's path (e.g. "media/<name>.png", exactly
 * as it appears in `![alt](media/<name>.png)`) to the file's raw bytes.
 * Injected from main.ts, where the real OpfsBackend lives — the reveal
 * engine itself has no storage awareness and only ever sees this function.
 */
export type ImageResolver = (relPath: string) => Promise<Uint8Array>;

/**
 * No resolver configured (e.g. in a test EditorState that never registers
 * this facet) combines to null rather than throwing — ImageWidget treats
 * that as "can't resolve" and falls back to its broken-image state, the
 * same path a real read failure takes.
 */
export const imageResolver = Facet.define<ImageResolver, ImageResolver | null>({
  combine: (values) => (values.length > 0 ? values[values.length - 1]! : null),
});
