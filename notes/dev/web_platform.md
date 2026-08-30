# Web Platform Support — Feature Spec (Draft, For Discussion)

**Status**: draft — not locked, not yet an ADR, not briefed to any Implementation session. Written for review and process discussion, per the project owner's request. Revised after initial review: scope sharpened from "a web app for any browser" to specifically **an installable iOS PWA stopgap**. Nothing here should be treated as decided until confirmed.

---

## 1. Problem / motivation

iOS builds are deferred (locked decisions table: "codebase supports; builds deferred"). Real native iOS is not happening soon. The project owner wants a **stopgap specifically for iOS** in the meantime: a web app installable to the iOS home screen (PWA "Add to Home Screen"), with the ability to share content **out** of it to other apps — functionally standing in for a native iOS app until either real iOS builds happen or Sync (v1.1+, ADR-17/18) arrives and changes the picture.

This is **not** a general "QuKi-Notes but in any browser" effort. Windows already has a good native solution — there's no goal here to give desktop Chrome users a competing or parallel experience. The target is narrow and specific: iOS users, via an installed web app, with share-out.

Desktop/other-browser access is a side effect of building for the web platform at all, not a design goal — it should work (same storage backend, nothing iOS-specific about the underlying app), but it isn't what this is for.

---

## 2. Goals

- A Flutter Web build of QuKi-Notes, installable to the iOS home screen as a PWA (proper manifest, icons, standalone display mode — whatever Safari's "Add to Home Screen" actually requires to feel like an app, not a bookmark).
- **Share-out from the PWA** via the Web Share API (`navigator.share()`) — a real transport, following the existing `TransportPlugin` pattern, not a stretch goal. This is one of the two things the project owner explicitly named as "what we're going for."
- Local persistence via **IndexedDB only.** No File System Access API path — dropped per the project owner's direction (Windows already covers the "real files" use case; iOS can't get FSA at all regardless of browser, so building it would only ever benefit desktop Chrome, which isn't the target). One storage backend for every browser, no feature-detection branching.
- No accounts, no backend, no server-side persistence. Nothing here reopens ADR-9 (no auth in MVP) or ADR-17/18 (no sync yet).

---

## 3. Non-goals — explicitly out of scope this phase

- **Sync.** No cross-device continuity beyond what one browser's own IndexedDB naturally gives you. Separate, later phase (ADR-17/18).
- **File System Access API / "real files on web."** Deliberately dropped, not deferred — Windows already solves this; building it would mainly serve desktop Chrome, which isn't this effort's target.
- **Share-in equivalent** (a PWA registering as a Web Share Target). Not named as a goal by the project owner — only share-**out** was. Deferred unless explicitly added later.
- **Image paste/storage on web.** Already blocked on mobile (#247, CargoKit); no new work here either. Existing image references are not expected to render under IndexedDB storage this phase.
- **Desktop-browser polish.** The app should run in desktop browsers (same codebase, same IndexedDB backend), but no dedicated design/testing effort is spent making that experience great — iOS is the target, desktop is "works, not tuned."

---

## 4. Storage: IndexedDB only

`QuKiStorage` (`lib/core/storage/quki_storage.dart`) and its siblings (`QuKiIndex`, `TrashIndex`, `QuKiSearch`) are built directly on `dart:io`'s `File`/`Directory` APIs, which don't exist on web at compile time, not just at runtime. Nothing about the current storage layer runs on web unmodified — but with FSA dropped, this is now a two-way split, not three:

1. **`NativeFileStorageBackend`** — today's existing `dart:io` logic, extracted behind a shared interface with **zero behavior change** on Android/Windows/Linux. Pure refactor.
2. **`IndexedDbStorageBackend`** (new) — the only web backend. Notes + `.meta` sidecars stored as IndexedDB records instead of real files.

No runtime feature-detection needed on web — every web build uses IndexedDB, full stop. Non-web platforms are entirely unaffected.

### Open questions

- Interface shape: `dart:io`'s file-handle model doesn't map 1:1 onto IndexedDB's transaction/object-store model — needs real design.
- Does `.trash/`, the `.meta/{uuid}.json` sidecar convention, and the 30-day auto-purge (ADR-38) map cleanly onto IndexedDB records, or need adaptation?
- What does the user get told about IndexedDB's real limitations — no exportable files, at risk from clearing browser/site data, tied to one browser on one device? This matters more now, not less, since iOS is the *primary* target and iOS Safari has its own storage-eviction behavior for infrequently-used sites that's worth being upfront about, not silent about.
- Is there any first-launch messaging needed at all, given ADR-27/28's existing Filesystem-vs-App-storage choice has no real equivalent here (there's only one option)?

---

## 5. Share-out: Web Share API

New goal, not previously scoped. `navigator.share()` is the web platform's equivalent of Android's `ACTION_SEND` chooser — it hands off text (and optionally files/URLs) to whatever the OS/browser offers as share targets. On iOS Safari (and installed PWAs), this surfaces the native iOS share sheet — the actual mechanism that makes "share out of the installed app" work at all.

This should follow the existing `TransportPlugin` pattern (`lib/core/transports/`) — a new `WebShareTransport`, structurally parallel to `ShareSheetTransport`, registered only on web. Given this whole project's recent, extensive experience with Android's share mechanism having real, non-obvious failure modes (`share_plus`'s hidden `startActivityForResult` behavior, `FLAG_ACTIVITY_NEW_TASK`, silent `startActivity()` failures — see `notes/dev/android_share_sheet.md`), **do not assume `navigator.share()` "just works" on iOS Safari without on-device verification.** Web Share API has its own real constraints worth confirming early, not late:
- Requires a secure context (HTTPS) — should be fine for a hosted PWA, but worth stating.
- Requires a direct user-gesture call chain (can't be called from an arbitrary async callback with too much delay/indirection) — echoes this project's *own* recent lesson about async gaps before a native share call causing real, hard-to-repro failures. Worth deliberately keeping the call chain from tap to `navigator.share()` as short as possible from the start, not retrofitting it after an intermittent bug shows up again.
- `navigator.canShare()` should gate whether the Send UI even offers this transport, rather than offering it and failing silently on unsupported browsers.

---

## 6. The other real risk: does the editor actually work on iOS Safari specifically

`markdown_live_editor` is a from-scratch `RenderObject` + `TextInputClient` (ADR-31), not a stock `TextField`. This project has an extensive, documented history of real pain getting text input/focus/keyboard behavior right on just Android and Windows (`notes/dev/keyboard_focus_state.md`, the ADR-36 selection effort, repeated cold-launch-focus failures in root `CLAUDE.md`'s Known Bugs).

With the scope now specifically iOS, the spike target sharpens too: **this needs validating on actual iOS Safari (a real iPhone or the iOS Simulator), not just "a browser" or desktop Chrome.** WebKit/Safari is widely known as the most divergent browser engine for exactly this category of behavior (IME composition, on-screen-keyboard viewport handling, selection/caret quirks) — it is not a safe stand-in to test only on desktop Chrome and assume iOS Safari behaves the same. This is now the single most important platform to get a real signal from before investing further.

---

## 7. Proposed staging

| Phase | What | Gate |
|---|---|---|
| **0 — Spike** | Minimal harness proving `markdown_live_editor` works on **real iOS Safari** (typing, IME composition, selection, the custom paint path) — plus a throwaway `navigator.share()` call from the same harness to confirm the Web Share API path is viable at all on iOS. | Go/no-go for the rest of this effort. |
| **1 — Storage abstraction** | Extract the backend interface from today's `dart:io` implementation. Zero behavior change on existing platforms, proven by the existing test suite passing unmodified. | Pure refactor; low risk. |
| **2 — IndexedDB backend** | Implement `IndexedDbStorageBackend` and wire it in for web builds only. Answer §4's open questions first. | — |
| **3 — Web Share transport + PWA installability** | `WebShareTransport` (§5). PWA manifest/icons/display-mode for a real "Add to Home Screen" experience on iOS. | — |
| **4 — Web build wiring** | Enable the Flutter web build target in CI/build tooling. Audit every existing platform guard for a missing web case (transports registry currently has none at all; share-in's `Platform.isAndroid` check is irrelevant here but shouldn't accidentally activate). | — |
| **5 — Real device testing** | iOS Safari (installed PWA, not just browser tab) is the primary, non-negotiable test target — matching this project's established "device-tested, not just compiles" standard. Desktop browser as a secondary sanity check only. | — |

---

## 8. What this needs to become before implementation

- A locked ADR ("Web platform — IndexedDB-only storage, PWA + share-out as an iOS stopgap") once this is discussed and confirmed.
- A locked-decisions-table entry for the new platform (today's table only lists Android/Windows/Linux active, iPadOS/iOS/macOS deferred — Web doesn't exist in it).
- Real answers to §4 and §6's open questions before any Implementation brief — pushing them into a brief unanswered just relocates the same unresolved design questions onto whoever implements it.
