# GitHub issues review — old Flutter tracker vs. the TypeScript rewrite

Reviewed 2026-09-20 against `github.com/ScottKirvan/QuKi-Notes/issues`: 123 issues total (72 open, 51 closed at review time). Read every title and body. No changes made — this is read-only research.

**A correction made after an earlier draft of this doc, from Scott directly:** an issue's *title* is a useful index of what was reported. An issue's *body* — the described root cause, the proposed mechanism, any "confirmed via X" narrative — is prose, the same unreliable class as a code comment, not ground truth. An issue existing does not confirm the story inside it, even when the story is detailed and specific (issue numbers, named apps) — that specificity is exactly what makes a wrong narrative convincing. Every "Resolved" verdict below rests on reading the rewrite's actual code or tests, not on trusting an old issue's account of what was wrong or why. Where a verdict's only real basis is "an issue with a matching title exists," that's called out as weaker evidence, not treated as confirmation.

**Verdicts:**
- **Resolved** — the rewrite's architecture or this session's work directly addresses it; reasonably confident.
- **Obsolete** — Flutter/Dart-implementation-specific; the described bug can't recur verbatim in the new stack. Some still carry a residual "same class of bug, different code" risk, noted where real.
- **Blocked** — depends on the list/task/blockquote live-reveal gap already in `rewrite_TODO.md`; can't be assessed until that's built.
- **Gap** — a real feature or behavior, still genuinely missing in the rewrite.
- **Check** — plausibly resolved by the new architecture, but not independently verified — worth a quick pass.
- **Decision** — a product/roadmap call for Scott, not an engineering verdict.

---

## Most important findings

**#345 is the one to read in full before building list-marker reveal.** The issue itself is agent-written (standard feature-request template), but it embeds a direct quote from Scott: the old whole-line reveal (cursor anywhere on a line reveals the *entire* raw line, including indentation) was "so jarring that it leads to screw ups when the user types" — an explicitly reversed design decision, not a rough edge. That quoted decision is treated as fact here; the issue's own surrounding narrative (its proposed implementation mechanism, its framing of scope) is not — same caution as everywhere else in this doc. The good news: BEHAVIOR_SPEC.md's current rule 3 (marker-only reveal — "past the marker, the line behaves exactly like an unadorned paragraph") is already the architectural fix for the core complaint, and it's already correctly implemented and tested for headings in the rewrite. What's *not* yet resolved: #345's concrete failure mode was specifically indentation snapping, which depends on the separate "indentation renders as grouped runs" feature — confirmed absent from the reveal engine (see `rewrite_TODO.md`). When the list/checkbox/blockquote reveal work gets scoped, it needs to satisfy both rule 3 *and* #345's indentation point together, or the exact bug Scott already flagged as wrong will resurface.

**#92, #337, #338 exist with titles matching the `SharePlugin.kt` comment's account — that shows the narrative was written down twice, not that it's true.** I'd earlier flagged that comment's specific citations (issue numbers, a named failing app) as unverifiable from local files alone. Finding issues with matching titles (#92 "share cancelled" even on success; #337/#338 Bluesky and Google Save share failures) is not independent confirmation — the issue bodies are the same class of prose as the comment, quite possibly written by the same agent in the same session. What actually justifies the rewrite's plain-2-arg-chooser design is the reasoning on its own merits, checked against real code and a real device this session: the app never reads the share result, so a result-tracking chooser is unused complexity regardless of whether any specific app ever mishandled it, and the plain chooser was independently confirmed to work end-to-end. The design doesn't need the Bluesky story to be true to be correct.

**#340 and #72/#234/#235/#263/#265/#344/#272** are the "big five" defects that motivated the rewrite in the first place (keyboard-driven mode unreliability, toolbar-covers-content, image rendering never working, the sidecar/database design) — all directly, deliberately addressed by this rewrite's architecture and this session's work, not incidentally.

**A cluster of "full codebase review" findings (#380–#395)** are AI-generated review findings against the *Flutter* implementation specifically (reentrancy guards on Dart controllers, non-atomic `SharedPreferences` writes, `Timer` leaks in a Flutter `GestureDetector`). Most are structurally obsolete — the described code doesn't exist in the rewrite. A few name a *class* of bug worth independently checking against the new TypeScript code rather than assuming the rewrite is immune just because the specific Dart bug can't recur — flagged individually below.

---

## Full table

| # | Title | Verdict | Note |
|---|---|---|---|
| 24 | Snackbars do not auto-dismiss | Obsolete | Flutter `SnackBar` default duration bug. Rewrite's `toast.ts` always takes an explicit `durationMs`. |
| 25 | Paragraphs double-spaced in editor | Resolved | Old `\n\n` join/split round-trip bug. Rewrite persists `doc.toString()` directly, no lossy transform step. |
| 26 | Root editor has back arrow | Resolved | Rewrite's editor is architecturally the root view; never pushed. |
| 27 | WYSIWYG markdown rendering — MVP | Resolved | The reveal engine, for what it covers (headings, inline, images/hr). |
| 28 | Editor nav redesign — icons, Send terminology | Resolved | Matches current app-bar design exactly. |
| 29 | Recently Deleted / Trash with retention | Resolved | STORAGE_CONTRACT trash + 30-day auto-purge, built and wired. |
| 32 | Auto-capitalizes first letter of line | Check | Flutter IME config bug. Platform-default behavior now; worth a quick Android real-device check. |
| 36 | Tapping a QuKi pushes new editor | Resolved | `openQuKiInEditor` loads into the single root editor by design. |
| 37 | Default purple theme instead of Primer | Resolved | Theme corrected this session (BEHAVIOR_SPEC §11, `style.css`). |
| 38 | Nav transitions should reflect direction | Gap | Minor polish, not built. |
| 56 | Release APKs signed with debug key | Resolved (partial) | Matching title exists in the old tracker; not proof the described incident happened exactly as told, but the risk itself doesn't depend on that story — a real keystore/secrets are still needed regardless. Env-var wiring done. |
| 71 | List formatting lost switching notes | Resolved | Old `\n\n` join/split bug; rewrite has no such transform. |
| 72 | Keyboard not visible on cold launch | Resolved | `editMode.ts` + `shouldFocusOnOpen`; the rewrite's whole reason to exist. |
| 73 | Notes may not save when sharing rapidly | **Check** | Real risk worth checking against the new `handleSharedText`: does a second `sharedTextReceived` event racing an in-flight `store.save` from the first lose data? Not tested. |
| 74 | Auto-capitalization persists after fix attempt | Obsolete | Same as #32, Flutter IME config. |
| 75 | Opening a note bumps `modifiedAt` | Resolved | `openQuKiInEditor` only calls `store.read`, never writes. |
| 76 | Cursor not visible on Windows | Check | Different renderer entirely (CodeMirror caret vs. Flutter). Likely moot; worth a glance on a real Electron window. |
| 77 | Tab/indent not working on lists | Resolved | `toolbar/indentDedent.ts`, 41 tests, wired to Tab/Shift-Tab. |
| 78 | Keyboard dismiss button should toggle | Resolved (different mechanism) | Mode-toggle + real keyboard events now drive this, not a manual toggle button. |
| 79 | Auto-start new note after idle | Gap | Not built. |
| 80 | Replace hamburger with icon toolbar | Resolved | Rewrite never had a hamburger menu. |
| 81 | Insert/edit hyperlinks | Gap | No "insert link" UI; existing links render via `LinkWidget` but there's no authoring affordance. |
| 82 | Replace code button with checkbox button | Resolved | Toolbar has both — all 10 buttons present. |
| 83 | Spell check / autocorrect / swipe-type | Obsolete | Platform/OS IME feature, not app logic. |
| 84 | Runtime plugin loading vs. compile-time registry | Obsolete/Decision | Rewrite's transport model is much simpler; likely moot unless Scott wants it revisited. |
| 85 | Smart send button (disable/auto-fire) | Resolved (different design) | Rewrite only ever has one destination per platform; simpler than the old multi-transport problem. |
| 86 | Disable QuKi list icon when empty | Resolved | `quKiListBtn.disabled = list.length === 0`, confirmed in `main.ts`. |
| 87 | List/Settings should slide partial-width, dimmed | Gap | Screens are full push/pop views currently. |
| 88 | Release build mode for `just android` | Obsolete | Flutter tooling; rewrite uses npm scripts + Gradle directly. |
| 92 | Share Sheet "share cancelled" even on success | Resolved | Matching title exists in the old tracker, but that's not confirmation of the story (see top-of-doc note). The rewrite's plain-2-arg-chooser design stands on its own reasoning — unused result-tracking removed, end-to-end delivery independently tested on a real device. |
| 129 | Cursor placement jumps to end of line | Check | CodeMirror's native caret placement is architecturally different; worth a real Android touch-precision check. |
| 130 | Checkbox toggle unacceptably slow | Blocked | No checkbox widget exists yet. |
| 131 | Checkbox vertical alignment off | Blocked | Same. |
| 132 | Keyboard dismiss button doesn't re-raise | Resolved (different mechanism) | Real keyboard events now drive mode, not a manual toggle. |
| 133 | Share-in QuKi doesn't appear in list | Resolved | `handleSharedText` calls `store.save` + `refreshQuKisButton`; independently verified on a real device this session. |
| 134 | Storage location choice at first launch | Resolved | Setup screens built for both Electron and Android. |
| 135 | Find in page (search within note) | Gap | Only list-level search exists; no within-note search. |
| 136 | Word/character count | Gap | Not built. |
| 138 | `flutter_markdown` crash on bare task continuation | Obsolete | Flutter-package-specific crash. Worth a cheap sanity check once list rendering exists. |
| 174 | Checkboxes don't render with leading spaces | Blocked | No checkbox widget yet. |
| 175 | Dash mid-sentence switches list continuation mode | Blocked | Depends on list rendering existing; CodeMirror's own continuation logic may behave differently — check once built. |
| 176 | Tapping empty space below content has no effect | Check | CodeMirror typically places the caret at document end on a click past content; likely resolved, not confirmed. |
| 177 | Keyboard matrix — continued device testing | Obsolete | Flutter-specific tracking issue; the underlying "test keyboard across devices" practice continues regardless. |
| 178 | Adjustable font size | Gap | Not built. |
| 179 | Text selection within large blocks | Check | CodeMirror is a flat text editor, not block-based — architecturally sidesteps this, not independently confirmed. |
| 180 | Select across blocks | Resolved (architecturally) | Same reasoning — no block boundaries exist to stop at. |
| 181 | Tap-hold flyout for toolbar buttons | Gap | Not built. |
| 182 | Empty note placeholder/watermark | Gap | Not built. |
| 183 | Help modal | Gap | `helpBtn` exists, wired, explicitly disabled — no dialog yet (still open in the rewrite too, per its own comment in `main.ts`). |
| 184 | Termux-style arrow-key bar | Gap | Not built, niche. |
| 188 | Share-in launches new instance instead of routing | Resolved | `handleOnNewIntent` + `singleTask`; independently verified on a real device this session (already-running path correctly reused). |
| 198 | Checkboxes render as literal brackets | Blocked | No checkbox widget yet. |
| 199 | Ordered list shows literal number, not position | Gap (requirement) | Not testable yet (no list rendering), but BEHAVIOR_SPEC already documents block-relative renumbering as a requirement — good, already on the record for whenever this gets built. |
| 219 | Typing `**` hides wrong asterisk elsewhere in doc | Check | Reveal engine reads a real per-position syntax tree, not a global scan — architecturally unlikely to recur, not independently tested. |
| 234 | FormattingToolbar obscures last line | Resolved | Exactly what the keyboard-aware toolbar chunk fixed; verified on a real device. |
| 235 | Toolbar visible when editor has no focus | Resolved | Verified in the toolbar chunks' review. |
| 236 | Cursor placed after closing delimiter, not between | Resolved | `wrapSelection` places the caret between delimiters on empty selection; unit-tested. |
| 237 | Blockquote rendering — no indent, bad continuation | Blocked | No blockquote handling in the reveal engine yet. |
| 238 | Text selection UX — no handles, no double/triple-click | Resolved (architecturally) | Native platform selection now, not a custom-built `SelectionHandle` widget. Double-click-word-select already exercised in a real e2e test. Worth a real Android confirmation. |
| 239 | Reading mode (T icon, no keyboard for existing notes) | Resolved | `editMode.ts`, `shouldFocusOnOpen`, mode-toggle icon states — all built and reviewed this session. |
| 240 | Nested inline formats inside list lines | Blocked (partially) | Inline formatting works regardless of list context already; full resolution needs list rendering to exist. |
| 241 | Nested and indented lists | Blocked | Indent/dedent *text* logic works (toolbar); *visual* nested rendering doesn't exist. |
| 242 | Nested blockquotes | Blocked | Same, blockquote rendering doesn't exist. |
| 243 | GitHub callouts (`> [!NOTE]` etc.) | Gap | Not built; depends on blockquote rendering first. |
| 244 | Fenced code blocks | Gap | Explicitly named as a deliberate deferred addition in `quki-rewrite-path.md` itself — already on the record. |
| 245 | GFM tables | Gap | Same — explicitly deferred in `quki-rewrite-path.md`. |
| 246 | Images — external URL | Gap | `imageResolver.ts` only reads local backend paths; no fetch-URL path. Low priority in the old tracker too. |
| 247 | Images — clipboard paste | **Resolved** | Actually done in the rewrite (`pasteImage.ts`) despite being open in the old Flutter tracker — the rewrite got here first. |
| 248 | Toolbar active-format highlighting at cursor | Gap (partial) | Not built for most buttons; heading's icon-tracks-level is a partial version of the same idea. |
| 249 | Sticky plain-text-mode preference | Gap | `plainTextMode` is a live CodeMirror state field; no evidence it's persisted across reloads. Likely still resets, matching the original bug. |
| 250 | Cursor/arrow-key nav improvements | Resolved (architecturally) | CodeMirror's default nav is standard; likely a structural improvement over the old custom implementation. |
| 251 | Nav bar redesign (dup of #28) | Resolved | Same as #28. |
| 252 | Default notes on install (welcome/cheatsheet) | Gap | Not built. |
| 253 | Help modal (dup of #183) | Gap | Same as #183. |
| 254 | HTML rendering in markdown | Gap (nuance) | BEHAVIOR_SPEC's HTML rule is about *not misparsing* HTML-like text as markdown (implemented, tested) — actual HTML rendering (e.g. `<b>` really bolding) is a different, still-unbuilt claim. |
| 255 | Definition lists | Gap | Not built, niche. |
| 256 | Syntax highlighting in code blocks | Gap | Depends on #244 (fenced code) existing first. |
| 261 | Share-in opens list instead of editor | Resolved | `handleSharedText` calls `popToRoot()`; independently verified on device. |
| 263 | Reading mode: toolbar/cursor visible after dismiss | Resolved | Directly what `editMode.ts` fixes — the rewrite's founding defect. |
| 264 | Bold formatting intermittently produces `*word**` | Resolved (architecturally) | `wrapSelection` is a pure, deterministic string op — no async/racy path for this to happen. |
| 265 | Keyboard opens after deleting QuKi from list | Check | `deleteQuKi` doesn't call `view.focus()`; likely resolved, not independently spot-checked. |
| 266 | Tapping checkbox in reading mode scrolls+opens keyboard | Blocked | No checkbox widget yet — but a direct, actionable warning for when it's built. |
| 267 | Checkboxes render inconsistent size/color | Blocked | Same. |
| 268 | QuKi list layout polish | Decision | Visual fit-and-finish; Scott's call. |
| 269 | Search results should show matching snippet | Gap | List search currently shows only the preview, not a match snippet. |
| 272 | Notes without `.meta` sidecar silently ignored | **Resolved** | This is the core premise the whole storage rewrite is built around — dedicated tests exist for exactly this. |
| 285 | Optional GitHub-strict paragraph reflow | Decision | Product decision about newline handling, not an engineering gap. |
| 305 | Indented paragraph GFM lazy-continuation | Check | Depends on CodeMirror's GFM parser's own lazy-continuation handling — connects to the "unverified parsing rules" item already in `rewrite_TODO.md`. |
| 316 | Linux HTML clipboard paste blocked by dependency conflict | Obsolete | Flutter-specific dependency version conflict; doesn't exist in the new stack. |
| 328 | Text selection doesn't work in reading mode | Check | Reading mode in the rewrite doesn't disable the whole gesture surface the way Flutter's custom system did — different situation, not confirmed either way. |
| 329 | No draggable handle for precise cursor placement | Resolved (architecturally) | Native platform selection handles exist without custom code, same as #238. |
| 335 | Tapping checkbox reveals raw source, becomes untappable | Blocked | No checkbox widget yet. |
| 336 | Selecting text in reading mode opens keyboard | Check | Same open question as #328. |
| 337 | Sharing to Bluesky doesn't work | Resolved (design, not the story) | Matching title exists, not proof the described cause is accurate. Generic chooser mechanism tested working end-to-end on a real device this session; Bluesky itself wasn't available on the emulator to re-test directly. |
| 338 | Share to "Save" errors, asks for a link | Resolved (design, not the story) | Same reasoning as #337. |
| 339 | Share to Google Voice — unclear behavior | Gap | Edge case, not investigated either version. |
| 340 | Keyboard open/close detection fundamentally unreliable | **Resolved** | The rewrite's founding defect — `editMode.ts`'s real Capacitor Keyboard signal replaces the `didChangeMetrics()` proxy this issue describes. |
| 341 | Sponsor/Ko-fi links in Settings | Decision | Content decision, not built. |
| 342 | Startup splash screen | Gap | Not built, cosmetic. |
| 343 | Revisit sync (Phase 4) timing | Decision | Explicit roadmap call for Scott. |
| 344 | Block-level image rendering has never worked | **Resolved** | Found and fixed earlier this session (image path resolution / blob-URL cache work). |
| 345 | Stop collapsing list markers on cursor entry | **See top-of-doc note** | Scott's own reversed design decision. BEHAVIOR_SPEC's current marker-only reveal rule is the architectural fix and is already correctly built for headings — but the indentation-run-grouping piece #345 specifically calls out is still missing. Needs to be satisfied together when list reveal is built. |
| 349 | Tapping a link in reading mode likely opens keyboard | Check | `LinkWidget` already exists (unlike checkboxes) — worth confirming this specific class of bug doesn't recur for links, since the underlying widget is real now. |
| 351/352 | Checkbox tap target too small, hard to hit | Blocked | No checkbox widget yet — direct sizing guidance for when it's built. |
| 354 | Nested checkbox toggle silently no-ops | Blocked | Same; also a concrete warning (don't hardcode marker offset assuming no leading whitespace). |
| 368 | Trash auto-purge — 30-day retention | Resolved | `store.purgeExpiredTrash()`, wired at launch. |
| 371 | Windows: physical keyboard typing does nothing | Check | Not encountered in this session's Electron work, but not specifically re-tested either — worth a quick real Windows check. |
| 377 | Heading `#` stays visible in fully-unfocused reading mode | Check | Reveal engine uses an invalid-caret convention for plain-text mode (rule 6) — worth confirming reading mode (not plain-text mode) collapses headings correctly when nothing has focus at all. |
| 380 | Changing storage location creates a second live EditorScreen | Obsolete (adjacent bug already caught) | Flutter-specific navigation bug. A related-but-different bug in the same area (`PreferencesStore.setStorageLocation` overwriting the whole file) was independently found and fixed earlier this session — different bug, same neighborhood. |
| 381 | No reentrancy guard on auto-save, can corrupt/revert content | **Check** | Flutter-specific code, but the *class* of bug is worth auditing against `AutoSaveController` directly — partially covered by existing tests ("pending save cannot resurrect a deleted QuKi") but not a full reentrancy audit. |
| 382 | Selection-handle drag leaks Timer/magnifier on cancel | Obsolete | No custom `SelectionHandle` widget exists in the rewrite — native selection only. |
| 383 | Selection-handle drag state not invalidated on doc swap | Obsolete | Same reasoning. |
| 384 | Delete can race with in-flight autosave, resurrecting outside trash | **Check** | Same reasoning as #381 — worth confirming `deleteQuKi`'s ordering fully closes this for the new code, not just assumed from the old bug being Flutter-specific. |
| 385 | Write path lacks retry hardening applied to delete/restore path | Check (low confidence in original premise) | Note: this project's own CLAUDE.md flags that the *original* antivirus-interference justification for this retry logic was never actually tested — worth being skeptical of the premise, not just the Flutter code, if this ever comes up again. |
| 386 | Index `refresh()` can overwrite a concurrent correct update | **Check** | Worth confirming `store.list()`/`QuKiStore`'s scan logic doesn't have an equivalent race in the new code. |
| 387 | PR #376 resume fix gated on an already-proven-unreliable signal | Obsolete | Specific to the abandoned Flutter `didChangeMetrics()` mechanism `editMode.ts` replaces entirely. |
| 388 | No reentrancy guard on storage-setup resumed-lifecycle handler | Obsolete | Flutter-specific; Electron's setup flow uses a different, already-reviewed mechanism. |
| 389 | Unawaited save on app pause/detach, no completion guarantee | Check | Worth confirming Electron's window-close/app-quit path flushes auto-save reliably; not specifically re-tested this session. |
| 390 | Window-bounds persistence writes four values non-atomically | **Check** | Directly relevant — worth confirming the rewrite's `PreferencesStore` writes window x/y/width/height atomically, not piecemeal. Not specifically audited. |
| 391 | Dead code cleanup from a full Flutter review | Obsolete | Fresh codebase, no legacy accumulation yet to clean up. |
| 394 | `didChangeMetrics()` stale second call after resume | Obsolete | Specific to the abandoned Flutter keyboard-metrics mechanism. |
| 395 | Keyboard sometimes takes seconds to reappear after resume | Obsolete (mechanism), Check (symptom) | Mechanism doesn't exist in the rewrite, but the underlying "keyboard responsiveness after backgrounding" symptom is the kind of thing worth watching for on a real device over time. |

---

## Quick counts

- **Resolved** (confident): ~35
- **Obsolete** (Flutter-specific, low residual risk): ~20
- **Blocked** on the list/task/blockquote reveal gap: ~15
- **Gap** (real feature, not built): ~25
- **Check** (plausibly fine, not independently verified): ~20
- **Decision** (Scott's call, not an engineering question): ~8

Numbers are approximate — several issues legitimately span two categories (noted inline above).
