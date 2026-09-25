import type { ChangeSet } from "@codemirror/state";
import { EditorView } from "@codemirror/view";

/**
 * Paste-to-import, image half: STORAGE_CONTRACT.md rule 12 ("Paste is the
 * primary way images arrive. A pasted image is written into media/ under a
 * generated name and the link is inserted at the cursor") and the
 * web-specific section ("Images paste in the same way [as text]"). Text
 * paste needs no new code here — CodeMirror's default paste already
 * inserts plain text as an ordinary document change, and the existing
 * auto-save path (persistence.ts's AutoSaveController) creates a new QuKi
 * on first save regardless of how the text got into the editor.
 *
 * Split into pure decision logic (unit-tested in pasteImage.test.ts) and
 * DOM/CodeMirror wiring (exercised by e2e/imagePaste.e2e.ts, since it needs
 * a real browser paste event and real OPFS) — the same split
 * screens/swipeGesture.ts (pure) / screens/swipeToDelete.ts (DOM) uses.
 */

export const IMAGE_MIME_TO_EXTENSION: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
};

export interface PasteItemLike {
  kind: string;
  type: string;
}

/**
 * PROPOSAL (unconfirmed — not specified by STORAGE_CONTRACT.md or
 * BEHAVIOR_SPEC.md): when the clipboard carries both an image and text —
 * for example some sources attach a text/plain fallback (a filename or
 * caption) alongside the image bytes — the image wins and the text payload
 * is discarded entirely, rather than being inserted alongside the link.
 * Scans in DOM item order and returns the first recognised image file
 * item regardless of where a text item sits relative to it.
 */
export function findImagePasteItem<T extends PasteItemLike>(items: Iterable<T>): T | null {
  for (const item of items) {
    if (item.kind === "file" && item.type in IMAGE_MIME_TO_EXTENSION) {
      return item;
    }
  }
  return null;
}

/** Total by design (falls back to "png") even though every caller only ever passes a MIME type findImagePasteItem already matched. */
export function extensionForImageMime(mimeType: string): string {
  return IMAGE_MIME_TO_EXTENSION[mimeType] ?? "png";
}

export interface ImagePasteHost {
  writeImage: (bytes: Uint8Array, extension: string) => Promise<{ relativePath: string }>;
  onError: (error: unknown) => void;
}

/**
 * Maps a paste's still-pending insertion range forward through one document
 * change - a bug found on-device (Scott, 2026-09-25): pasting several
 * images in quick succession, or just a slow writeImage(), lost or
 * mis-placed earlier images' links, because the original code captured
 * `{from, to}` once, synchronously, and used that same fixed pair after the
 * async file-read-and-write gap with no regard for whatever the document
 * had done in the meantime - including another pending paste's own insert
 * landing at that exact position.
 *
 * Two cases, handled differently:
 *
 * - The change doesn't touch this range at all (ordinary typing elsewhere,
 *   or an insertion entirely before/after it): map both ends independently
 *   with `mapPos(pos, 1)`, which correctly shifts a still-valid selection
 *   forward or leaves it alone.
 * - The change touches or overlaps this range - typically another pending
 *   paste's own insert landing at/inside the exact spot this one was also
 *   targeting. Whatever this range meant to replace may already be gone,
 *   so mapping `from` and `to` independently is unsafe: `mapPos`
 *   resolves a position sitting exactly at the START of an overlapping
 *   replacement to a point BEFORE its inserted content regardless of
 *   `assoc` (only a position at the END of one moves after it), so
 *   independent mapping here would make `from` and `to` straddle the other
 *   change's entire inserted text - replacing it outright on this paste's
 *   own dispatch. Collapse to a single cursor instead, positioned right
 *   after whichever touching change inserted the most, so this paste
 *   appends after it rather than colliding with it.
 */
export function mapPasteRange(range: { from: number; to: number }, change: ChangeSet): { from: number; to: number } {
  if (change.touchesRange(range.from, range.to)) {
    let after = range.to;
    change.iterChanges((fromA: number, toA: number, _fromB: number, toB: number) => {
      if (toA >= range.from && fromA <= range.to) after = Math.max(after, toB);
    });
    return { from: after, to: after };
  }
  return { from: change.mapPos(range.from, 1), to: change.mapPos(range.to, 1) };
}

/**
 * A CodeMirror extension: intercepts a paste that carries an image and
 * writes it into the shared media/ folder, then inserts the generated
 * `![](media/<name>)` link as literal text at the cursor position the
 * paste occurred at. Plain-text paste (no image item present) is left
 * completely untouched — the handler returns false and CodeMirror's
 * default paste handling proceeds exactly as before.
 *
 * media/ is a shared folder at the storage root (StorageBackend.writeImage
 * / OpfsBackend), not per-QuKi, so this works identically whether the
 * current QuKi has never been saved (id: null) or already exists on disk.
 */
export function createImagePastePlugin(host: ImagePasteHost) {
  // Every in-flight paste's insertion range, kept current against the live
  // document by trackChanges below (see mapPasteRange) until its own
  // dispatch removes it. A plain mutable object per paste, not a value -
  // trackChanges updates it in place as changes land.
  const pending = new Set<{ from: number; to: number }>();

  const trackChanges = EditorView.updateListener.of((update) => {
    if (!update.docChanged || pending.size === 0) return;
    for (const range of pending) {
      const mapped = mapPasteRange(range, update.changes);
      range.from = mapped.from;
      range.to = mapped.to;
    }
  });

  const handlePaste = EditorView.domEventHandlers({
    paste(event, view) {
      const dataTransfer = event.clipboardData;
      if (!dataTransfer) return false;

      const item = findImagePasteItem(dataTransfer.items);
      if (!item) return false;

      // Prevent the default paste (which would otherwise insert nothing
      // useful for an image, or whatever plain-text fallback happened to
      // ride along) before doing anything async.
      event.preventDefault();

      const file = item.getAsFile();
      if (!file) return true;

      // Captured synchronously, at paste time - then kept current by
      // trackChanges above across the async gap below, rather than used as
      // a fixed pair the way the pre-fix version did.
      const { from, to } = view.state.selection.main;
      const range = { from, to };
      pending.add(range);
      const extension = extensionForImageMime(item.type);

      void (async () => {
        try {
          let bytes: Uint8Array;
          try {
            bytes = new Uint8Array(await file.arrayBuffer());
          } catch (error) {
            console.error("QuKi image paste (reading clipboard file) failed unexpectedly:", error);
            host.onError(error);
            return;
          }

          let result: { relativePath: string };
          try {
            result = await host.writeImage(bytes, extension);
          } catch (error) {
            console.error("QuKi image paste (writeImage) failed unexpectedly:", error);
            host.onError(error);
            return;
          }

          const markdown = `![](${result.relativePath})`;
          view.dispatch({
            changes: { from: range.from, to: range.to, insert: markdown },
            selection: { anchor: range.from + markdown.length },
          });
        } finally {
          pending.delete(range);
        }
      })();

      return true;
    },
  });

  return [handlePaste, trackChanges];
}
