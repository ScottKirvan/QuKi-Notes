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
  return EditorView.domEventHandlers({
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

      // Captured synchronously, before any await, so the insertion lands
      // where the cursor was at paste time even if it moves before the
      // async write finishes.
      const { from, to } = view.state.selection.main;
      const extension = extensionForImageMime(item.type);

      void (async () => {
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
          changes: { from, to, insert: markdown },
          selection: { anchor: from + markdown.length },
        });
      })();

      return true;
    },
  });
}
