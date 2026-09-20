# QuKi Notes — Storage Contract

**Status:** normative. Supersedes the v0.24.1 storage implementation and any prior spec language describing QuKi Notes storage.

**How to use this:** paste it at the top of any task touching storage, the QuKi list, search, images, or trash. It is written as constraints, not description. Where a rule and an existing implementation disagree, the rule wins and the implementation is the defect.

**Vocabulary:** *QuKi Notes* is the application. A *QuKi* is the thing it captures. The app has two pages — the QuKi editor and the QuKi list.

---

## The law

**The folder is the index.** The set of `.md` files in the QuKi folder is the complete set of QuKis. Nothing else decides what exists.

---

## Rules

1. **Any `.md` file in the folder is a QuKi**, whether QuKi Notes created it or not. Putting a file there is a supported way to add one, and it must appear with no further action.

2. **No component maintains a separate list of what exists.** Not a sidecar, not a manifest, not a long-lived in-memory list that gets mutated instead of re-read.

3. **Identity is the filename.** Renaming the file renames the QuKi. That is correct behavior, not corruption.

4. **No naming scheme is required, and QuKi Notes never renames a file it did not create.** Generated QuKis get an opaque id for a filename; a file placed in the folder keeps the name it arrived with, permanently. A folder containing both is correct and must not be normalized. A QuKi is not philosophically a file — the filename is an address, not a title. Titles belong to the content, and to the save dialog if export is ever built.

5. **`modifiedAt` comes from the filesystem** — never from a stored copy. A QuKi edited by any other program sorts correctly with no involvement from QuKi Notes.

   *Known future exception:* some sync clients rewrite modification times on download. If that is ever observed in practice, a cached timestamp may be promoted to truth **for synced folders only**, as a documented exception with the reason recorded here. It is not a default.

6. **The sidecar may describe a QuKi. It may never determine which QuKis there are.** This is the only permanent prohibition. Sidecar fields fall into exactly three categories:

   - **Derived** — title, preview, word count, body hash. Rebuildable by re-reading the file, disposable, invalidated by filename plus mtime plus size. **No derived fields are implemented today** and none should be added until the collection is large enough to need them. At current scale (low hundreds) reading every file is imperceptible.
   - **Intrinsic** — `createdAt`, `deletedAt`, and later manual sort position, pin state, tags. Not derivable from the file, authoritative, and losing it is real loss. This category is expected to grow.
   - **Existence** — which QuKis there are. **Banned.** This was the v0.24.1 defect and it is the only thing the sidecar may never do.

   Today the sidecar holds two fields: `createdAt` and `deletedAt`. That is the whole schema.

7. **A missing, stale or corrupt sidecar never hides a file.** Intrinsic data may be lost — that is real loss, and the sidecar is therefore worth backing up and syncing — but the QuKi still appears in the list and still opens, with intrinsic fields falling back to defaults.

8. **QuKi Notes never writes into a `.md` file it did not create**, except to save the user's own edits. No frontmatter injection, no id stamping, no reformatting on read. A file placed in the folder and never edited stays byte-identical.

9. **The folder is flat.** Subfolders are not scanned for QuKis. `.meta/`, `.trash/` and `media/` are structural and are never treated as content. When grouping arrives it arrives as an explicit design change with its own spec — this rule is a current scope limit, not a permanent position.

---

## Images

10. **Images live in one shared `media/` folder at the root of the QuKi folder**, and are linked with an ordinary relative path: `![alt](media/filename.png)`. The link must resolve correctly in any other markdown reader — the QuKi stays portable, which matters because the contract explicitly invites other programs to open these files.

11. **Images are not QuKis.** `media/` is never scanned for content. Only `.md` files in the root are QuKis.

12. **Paste is the primary way images arrive.** A pasted image is written into `media/` under a generated name and the link is inserted at the cursor.

13. **Orphaned images are deleted when the QuKi that referenced them is permanently deleted** — but only if no other QuKi references them, **and the reference check includes QuKis in the trash.** A trashed QuKi that is later restored must come back with its images intact. This behavior is a user-facing setting, defaulting to delete.

---

## Trash

14. **Trash is a 30-day hold, then delete.** The purge runs automatically at app launch. An "empty trash" action also exists for clearing it on demand.

15. **`deletedAt` is intrinsic data in the trash sidecar.** It cannot be derived: moving a file preserves its mtime, so a trashed file's timestamp is its last edit, not its deletion.

---

## Saving

16. **An empty body is never written.** Deleting all the text in a QuKi does not save an empty file — the last non-empty content stays on disk. This is current behavior (`save()` returns early on `body.isEmpty`) and it is intentional: it prevents a stray select-all-delete from destroying a QuKi. Preserve it deliberately rather than dropping it as an oversight.

17. **The save baseline is the file, not memory.** Today the controller skips a write when the new body equals the last body *it* wrote — an in-memory value that knows nothing about the file. Under this contract other programs edit these files, so the controller must also record the file's modification time when it loads or writes a QuKi, compare it at the top of every save, and branch to a conflict path when it doesn't match. A save must never overwrite a file that changed underneath it.

18. **A failed save is surfaced, not just logged.** Writes currently fail silently — caught, logged, and swallowed, with the caller never informed. With a real folder, other programs, and real permissions, the user has to find out. Retry behavior stays as it is: the last-saved baseline is not updated on failure, so the next change retries naturally.

19. **A QuKi's file is created on its first save, not when the editor opens.** This is where rule 4 assigns the name. The seam already exists — the save callback receives a null id and returns the new one.

---

## Storage backends

The contract holds identically across all three. Only the route for getting a file into the folder changes.

| Backend | Used by | Folder |
|---|---|---|
| Node `fs` | Electron — Windows, Linux | A real folder the user chose at onboarding |
| Capacitor filesystem | Android | A real folder, via all-files access |
| OPFS | Web — all browsers | Origin-private, persistent, not user-visible |

Storage is an interface with these implementations behind it. The core module talks to the interface and never to a concrete filesystem.

**The web app uses OPFS only.** It does not offer a folder picker and does not use the File System Access API — the target audience is macOS and iOS, where that API doesn't exist. Because there is no folder to choose, the web app has no storage-location onboarding step; it simply starts.

**Getting content into the web app is paste.** Text pasted in becomes a new QuKi with a generated name, exactly like any other generated QuKi. Images paste in the same way. Web Share Target may be added later where an installed PWA supports it, but is not assumed.

**On iOS, OPFS is evictable.** WebKit evicts by least-recently-used under quota pressure, storage pressure, or site-inactivity rules. `navigator.storage.persist()` can exempt an origin and the heuristic that most reliably grants it is being installed to the home screen — which is why the web app is installable as a day-one requirement. Durability there is ultimately a sync question, not a storage one.

---

## The core API

Two requirements that exist for the API surface rather than for any current screen:

**Export everything.** A single call that produces the complete library — QuKis, sidecars and media — in one portable bundle. It is the backup story, and it is also the migration path: web-app users on OPFS move to a desktop folder this way, and iOS users move off the web app when a native iOS app exists. No UI has to call it on day one, but it belongs in the API from the start.

**Share is one action with no picker.** It does the platform-appropriate thing: the system share sheet via `navigator.share()` on Windows, Android and macOS; copy to clipboard on Linux, which has no cross-desktop share mechanism. There is no transport abstraction and no transport registry. Additional destinations, if ever wanted, are added through the API.

---

## Migration from v0.24.1

The existing folder opens as-is. Onboarding points the new app at the same folder; nothing is converted, renamed or rewritten.

- Existing sidecars already hold `createdAt`, which is kept.
- `modifiedAt` moves from the sidecar to the filesystem. Anything whose sidecar timestamp had drifted from real mtime — most likely files edited outside the app — will shift position in the list. This is the correction working, not a regression.
- Existing trashed QuKis have no `deletedAt`. They are stamped at first launch of the new version, so the 30-day clock starts then rather than purging anything on day one.
- Existing opaque filenames are left exactly as they are. Rule 4 permits them.

---

## Will be proposed — reject

These are the conventional shapes an implementer reaches for. Each satisfies a naive reading of the rules while breaking them.

- ❌ A manifest, catalog, index or registry file listing all QuKis — under any name, for any stated reason.
- ❌ Requiring a sidecar to exist before a file is listed.
- ❌ Skipping, hiding or erroring on a file whose sidecar is missing, stale, or fails to parse.
- ❌ Storing `modifiedAt`, title or preview as truth rather than as invalidatable derived data.
- ❌ Adding derived cache fields "for performance" before the collection is large enough to need them.
- ❌ Normalizing, slugifying or otherwise rewriting filenames that QuKi Notes did not generate.
- ❌ An in-memory list mutated by add/update/remove calls in place of re-reading the folder.
- ❌ Writing an id into the file itself — frontmatter, HTML comment, or otherwise — so intrinsic data survives renames.
- ❌ Per-QuKi media folders, or absolute paths in image links.
- ❌ Deleting orphaned images without checking the trash for references.
- ❌ Recursing into subfolders, or treating `media/` as content.
- ❌ Introducing a database of any kind, in any sense of the word — including "just a lightweight index for performance," "an in-memory cache of the listing," or SQLite.

---

## Acceptance test

Both must pass. They define done for any storage change.

**Test 1 — the folder is the truth.**
Place any `.md` file in the QuKi folder by whatever route the backend supports. It appears in the list immediately, with the correct modified time, having never had a sidecar.

**Test 2 — the sidecar never gates existence.**
Delete the entire sidecar directory while the app is running. Every QuKi still appears and still opens. Intrinsic data is gone and intrinsic fields fall back to defaults, but nothing vanishes from the list and nothing errors.

If either fails, something is acting as a registry. Find it and remove it.

---

## Vocabulary

The word **database** does not appear in QuKi Notes specs, in either the broad sense (any organized store, a filesystem included) or the narrow one (a registry with a schema). It is banned because those two readings produced this document. Say **the folder**, **the files**, or **the sidecar** — each names one specific thing whose behavior can be checked.

The same caution applies to any term broader in the author's usage than in an implementer's: *index*, *node*, *graph*, *store*, *model*, *scene*. Pin the meaning at first use or choose a narrower word.

**If an implementation is defended as matching the spec and is nonetheless wrong, the word is the bug.** Fix the wording before arguing about the code — an argument about code against a spec that supports the code cannot be won.

---

## Notes for the implementer

**Read the code, not the comments.** Comments in this codebase are unreliable. Worked example: `_loadImage()`'s comment claims `../images/foo.jpg` "resolves to `<storageRoot>/../images/` which matches the ADR-4 images directory at `<storageRoot>/images/`" — two different paths asserted as equal in one sentence. What the code does is `p.normalize(p.join(basePath, rawPath))`, landing in a *sibling* of the storage root, outside the user's chosen folder. That is why images don't render, and it is independent justification for rule 10's `media/` at the root. Verify every behavior against what executes.

**Current state at v0.24.1**, read from the source. The folder scan is already correct — it enumerates every `.md` file. The defect is a single guard in `_readMeta()`: a missing sidecar returns `null`, and the scan discards nulls. Identity is also already the filename (`basenameWithoutExtension`); opaque ids appear only in `create()`, which rule 4 permits. The full fix is small.

**Port the atomic write. Do not port the rename retry.** `_writeAtomic()`'s temp-then-rename is correct and standard, and carries across unchanged.

`_renameIfExists()`'s five-attempt retry loop should not. Three things in the code argue against it: the same rename happens in `_writeAtomic` on *every save* with no retry at all, so a defense present only on the delete path is a reaction to one incident rather than a general finding; on exhaustion it returns normally, so a genuinely failed delete reports success and leaves an orphaned file the list no longer references; and it retries the rename rather than the `exists()` check, so it doesn't address the check-then-act race its own comment blames. The causal story attached to it was never tested.

Rename failures are surfaced, not retried into silence. If a real transient appears under Node, handle it then, with evidence.

**Scale.** The reference library is roughly 100 active QuKis and a similar number in trash. Design for that, not for a hypothetical ten thousand.
