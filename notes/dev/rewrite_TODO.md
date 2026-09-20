# Rewrite TODO

Updated 2026-09-20. Unsequenced — just a record of what's open.

## Data loss — highest priority

- [ ] Save is too slow, and new QuKis can get lost (Scott, direct report). Relates to the GitHub issues review's "Check" items on auto-save reentrancy/timing (#73, #381, #384, #386) — worth investigating alongside those.

## Rendering / editor

- [ ] List/task/blockquote markers never collapse or reveal — only headings, images/hr, and inline formatting (bold/italic/strike/code/links) go through the reveal engine (`reveal/extractElements.ts`).
- [ ] No checkbox widget — no visual checkbox, no tap-to-toggle.
- [ ] Enter-continues/exits-a-list works (CodeMirror's own default keymap) — but the list still doesn't render, so it just doesn't look like anything.
- [ ] Indentation visual grouping ("same-depth lines laid out as one run", BEHAVIOR_SPEC §12) — no matching code found in `reveal/`. Tab/toolbar indent itself is separate, well-tested code and likely unaffected.
- [ ] Markdown parsing rules (heading-needs-space, intraword `*` vs `_`, block-relative ordered-list renumbering, etc.) rely on CodeMirror's stock GFM parser — never checked against Flutter's specific rules, no test coverage for the edge cases.
- [ ] Font is incorrect.
- [ ] Button style is incorrect.
- [ ] Some buttons show words instead of icons.

## Android

- [ ] Release signing: env vars wired (`STORE_FILE`/`STORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD`), real keystore/secrets still needed. Until then every build is debug-signed, and a mismatched real cert would break the Flutter migration path on update.
- [ ] Send's success toast always says "Copied to clipboard.", even on Android where it's a real share-sheet send now.
- [ ] Heading-cycle multi-line behavior is `[Proposed — unconfirmed]` — try it by hand with a reversed, mixed-level selection.
- [ ] Send tested into Messages only; no second target, no full completed send (no contacts on emulator).
- [ ] Share-in's failure-toast path never actually triggered/observed; both paths tested via explicit intent, not the real chooser UI.
- [ ] Toolbar not tested on a physical device, or with predictive text active.

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
