# Web Platform Support — Feature Spec (Draft, For Discussion)

**Status**: draft — not locked, not yet an ADR, not briefed to any Implementation session. Written for review and process discussion, per the project owner's request. Nothing here should be treated as decided until confirmed.

---

## 1. Problem / motivation

QuKi-Notes has no web-reachable version today. The project owner wants one now, explicitly as a **pre-sync stopgap**: real cross-device Sync (v1.1+, ADR-17/18) is coming soon but is not part of this phase and must not be blocked by it. A web version gives access from any machine with a browser in the meantime, and "will make more sense" once Sync exists to unify it with the native apps.

iOS/Safari's limitations here are a known, accepted gap for this phase — not a problem to solve now. This is a deliberate pressure-relief valve, not the final cross-platform story.

---

## 2. Goals

- A working Flutter Web build of QuKi-Notes, reachable via a browser.
- Full local persistence via the **File System Access API** on browsers that support it (Chromium-based desktop browsers) — preserving ADR-25's actual philosophy (individual files, user's own folder, no vault) for those users.
- A working **IndexedDB fallback** for browsers without File System Access API support, so the app is still usable everywhere — understood upfront as a strictly weaker, more fragile persistence model (browser storage, not a real inspectable folder, at risk from a user clearing site data).
- No accounts, no backend, no server-side persistence of note content. Nothing here reopens ADR-9 (no auth in MVP) or ADR-17/18 (no sync yet).

---

## 3. Non-goals — explicitly out of scope this phase

- **Sync.** This phase does not attempt any cross-device continuity beyond what a single browser's own storage naturally gives you. Sync is a separate, later phase (ADR-17/18) and this spec must not grow into a substitute for it.
- **iOS / mobile Safari.** Known limitation, accepted, not solved here. Worth being precise about *why*: File System Access API is unavailable on iOS **regardless of which browser brand you use** — Apple requires every iOS browser to use WebKit under the hood, so "Chrome on iPhone" does not get FSA either. This isn't "iOS is currently behind and might catch up soon" — it's a platform policy boundary. The IndexedDB fallback is what iOS gets, same as Firefox/desktop Safari.
- **Share-in equivalent** (e.g. a PWA registering as a Web Share Target). Deferred.
- **Share-out equivalent** (Web Share API). Not planned this phase; noted as a possible cheap follow-on, not committed to.
- **Image paste/storage on web.** Already blocked on mobile (#247, CargoKit); no new work here to unblock it for web either. Existing image references in notes are not expected to render correctly under either web backend this phase.
- **PWA installability / offline service worker.** Flutter's web build tooling may make some of this close to free, but it isn't a stated goal — mention only, not a requirement.

---

## 4. The real architectural gap: storage

`QuKiStorage` (`lib/core/storage/quki_storage.dart`) and its siblings (`QuKiIndex`, `TrashIndex`, `QuKiSearch`) are built directly on `dart:io`'s `File`/`Directory` APIs — write-to-temp-then-rename, real filesystem paths, real permission model (`MANAGE_EXTERNAL_STORAGE` on Android, a chosen folder on Windows/Linux). **`dart:io` does not exist on web at all** — this isn't a runtime capability gap, it's compile-time unavailable. Nothing about the current storage layer can run on web unmodified.

### Proposed shape

Extract a storage backend interface that `QuKiStorage` depends on, with three implementations:

1. **`NativeFileStorageBackend`** — today's existing `dart:io` logic, moved behind the interface with **zero behavior change** on Android/Windows/Linux. Pure refactor.
2. **`FileSystemAccessStorageBackend`** (new) — web, Chromium-only. Real directory handle via `showDirectoryPicker()`, real file read/write, as close to atomic write-then-rename semantics as the API actually allows (needs real investigation — FSA's write model is different enough from POSIX rename that this can't be assumed to map 1:1).
3. **`IndexedDbStorageBackend`** (new) — web fallback for everything without FSA (Firefox, Safari, iOS entirely). Notes + `.meta` sidecars stored as IndexedDB records instead of real files.

Runtime backend selection (web only): feature-detect FSA support (e.g. `window.showDirectoryPicker` existing) at startup. Present if supported, IndexedDB if not. Every non-web platform is entirely unaffected — always `NativeFileStorageBackend`, no new branching in code paths that already work today.

### Open questions this needs answered before implementation starts (not hand-waved into a brief)

- The actual interface shape. `dart:io`'s file-handle model and FSA's async-handle-with-permission-prompts model are not the same shape — this needs real design, not "make an abstract class with the same method names as today and hope."
- Does `.trash/`, the `.meta/{uuid}.json` sidecar convention, and the 30-day auto-purge (ADR-38) map cleanly onto both new backends, or do they need backend-specific handling?
- First-launch UX on web: does the FSA path get something like ADR-27/28's existing "pick Filesystem or App storage" choice? What does a user on the IndexedDB fallback get told about its limitations — permanence risk, no real file access, nothing to point a sync tool at later?
- FSA requires a user gesture to grant folder access and the grant can need re-confirming across sessions (browser-dependent) — does the app need a "reconnect to your folder" flow on every visit, and how disruptive is that to the "frictionless capture" philosophy the manifesto is built around?

---

## 5. The other real risk: does the editor actually work in a browser?

`markdown_live_editor` is a from-scratch `RenderObject` + `TextInputClient` (ADR-31), not a stock `TextField`. This project has an extensive, painful, well-documented history of getting text input/focus/keyboard behavior right on just Android and Windows (see `notes/dev/keyboard_focus_state.md`, the whole ADR-36 selection effort, and the repeated cold-launch-focus failures in root `CLAUDE.md`'s Known Bugs). Web is a **third**, browser-dependent input/IME model layered on top of that history, not a variation of one already solved.

This should be validated early, as a go/no-go gate — not discovered after the storage layer is built.

---

## 6. Proposed staging

| Phase | What | Gate |
|---|---|---|
| **0 — Spike** | Minimal harness proving `markdown_live_editor` actually works in a real browser: typing, IME composition, selection, the custom paint path. Throwaway-quality is fine. | Go/no-go for the rest of this effort. If this surfaces deep problems, the whole approach needs reconsidering before Phase 1 starts. |
| **1 — Storage abstraction** | Extract the backend interface from today's `dart:io` implementation. Zero behavior change on existing platforms — proven by the existing test suite continuing to pass unmodified. | Pure refactor; low risk. |
| **2 — Web storage backends** | Implement `FileSystemAccessStorageBackend` + `IndexedDbStorageBackend`, the runtime feature-detection/selection logic, and (if warranted per §4's open questions) a first-launch storage-choice UX for web. | Needs §4's open questions answered first. |
| **3 — Web build wiring** | Enable the Flutter web build target in CI/build tooling. Audit every existing platform guard (mobile/desktop distinction rules, the transports registry's current lack of any platform guard, share-in's `Platform.isAndroid` check, etc.) for a missing web case. Basic layout sanity for a resizable browser window vs. today's native window/mobile assumptions. | — |
| **4 — Browser testing pass** | Real testing, matching this project's established standard — not "it compiled." Chrome (FSA path) and at least one non-Chromium browser (Firefox, to exercise the IndexedDB fallback) minimum. Safari explicitly out of scope per §3. | — |

---

## 7. What this needs to become before implementation

- A locked ADR ("Web platform — dual storage backend, explicit pre-sync stopgap") once the shape above is discussed and confirmed — this doc is the pre-ADR research/proposal, matching how `android_share_sheet.md` and `selection.md` related to their own eventual ADRs.
- A `notes/dev/design_spec.md` / root `CLAUDE.md` locked-decisions-table entry for the new platform, once locked — today's table only lists Android/Windows/Linux (active) and iPadOS/iOS/macOS (deferred); Web doesn't exist in it yet.
- Real answers to §4 and §5's open questions before any Implementation brief gets written — briefing "build the storage abstraction" without those answered would just push the same unresolved design questions onto whoever implements it.
