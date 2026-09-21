# Rewrite TODO

Updated 2026-09-20. Unsequenced — just a record of what's open.

## Data loss — not urgent, deferred

- [ ] Save is too slow, and new QuKis can get lost (Scott, direct report). Not breaking — Scott has explicitly deferred this until the Rendering / Editor items are done. Relates to the GitHub issues review's "Check" items on auto-save reentrancy/timing (#73, #381, #384, #386) — worth investigating alongside those.

## Rendering / editor

- [x] List/task/blockquote markers never collapse or reveal — only headings, images/hr, and inline formatting (bold/italic/strike/code/links) go through the reveal engine (`reveal/extractElements.ts`).
- [x] No checkbox widget — no visual checkbox, no tap-to-toggle.
- [x] Enter-continues/exits-a-list works (CodeMirror's own default keymap) — but the list still doesn't render, so it just doesn't look like anything.
- [ ] Indentation layout (BEHAVIOR_SPEC §12 "How indentation renders") — implemented as per-line decorations in `reveal/decorations.ts` (no explicit runs structure): collapsed list/task/ordered items indent by depth and hang wrapped rows under their content, and a revealed line shows raw source at depth zero. Covered by unit tests and `e2e/listReveal.e2e.ts` in desktop Chromium only — needs Scott's on-device check on Android. Known gap: an item whose indentation jumps two or more levels at once, or a lone indented item with no parent (e.g. toolbar Indent on a lone `- item`), is not a list item to the parser and stays raw text, where Flutter treats it as nested.
- [ ] Markdown parsing rules (heading-needs-space, intraword `*` vs `_`, block-relative ordered-list renumbering, etc.) rely on CodeMirror's stock GFM parser — never checked against Flutter's specific rules, no test coverage for the edge cases.
- [ ] Font is incorrect.
- [ ] Button style is incorrect.
- [ ] Some buttons show words instead of icons.
- [ ] Enter on an empty list item that follows another item doesn't exit the list (BEHAVIOR_SPEC §4 "List auto-continue"): `- item⏎⏎- ` stays as `- item\n\n- ` instead of removing the marker; same for `- [ ] ` and `1. `. Only a lone `- ` exits. Reproduces with CodeMirror's bare `insertNewlineContinueMarkup`. Found during list-reveal review; the item above wrongly said exit works.
- [ ] Mode-toggle button (`#btn-mode-toggle`) may ignore real mouse clicks: in headless Chromium a mouse click didn't toggle plain-text mode but `element.click()` did. Unconfirmed guess: the icon `replaceChildren` on focus loss swallows the click. Not investigated; base commit not checked.
- [ ] A lone indented list item with no parent item (`\t- x`, which toolbar Indent produces on a lone `- item`) is an indented code block to the parser and doesn't collapse; the Flutter app treats it as nested depth 1. Parsing-rule audit territory.

## Android

- [X] Release signing: env vars wired (`STORE_FILE`/`STORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD`), real keystore/secrets still needed. Until then every build is debug-signed, and a mismatched real cert would break the Flutter migration path on update.
- [ ] Send's success toast always says "Copied to clipboard.", even on Android where it's a real share-sheet send now.
- [ ] Heading-cycle multi-line behavior is `[Proposed — unconfirmed]` — try it by hand with a reversed, mixed-level selection.
- [ ] Send tested into Messages only; no second target, no full completed send (no contacts on emulator).
- [ ] Share-in's failure-toast path never actually triggered/observed; both paths tested via explicit intent, not the real chooser UI.
- [ ] Toolbar not tested on a physical device, or with predictive text active.
- [ ] app icon need to be updated.
- [ ] 

## Desktop

- [ ] Windows Send is still clipboard-fallback (accepted deficiency, not a bug).
- [ ] Electron off-screen multi-monitor window-bounds test — deferred by Scott, still open.

## Repo housekeeping

- [ ] Rewrite `README.md` — currently describes the Flutter app and its toolchain.
- [ ] Rewrite `CONTRIBUTING.md` — currently references Flutter/Dart toolchain and setup.

## Manual acceptance ("Before committing" checklist, Scott's own)

- [ ] Reveal at the span level — predates this session, not witnessed directly.
- [ ] Checkbox swap mid-typing — blocked on the checkbox-widget gap above.
- [x] Paste an image — tested, unit + e2e.
- [ ] Sidecar-deletion acceptance test — core-level test exists, manual walkthrough not separately confirmed.
- [x] Toolbar pinned, keyboard up — done on emulator, not a physical Pixel.
- [ ] "Your worst QuKi" stress test — not attempted.
