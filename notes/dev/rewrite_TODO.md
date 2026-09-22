# Rewrite TODO

Updated 2026-09-21. Unsequenced — just a record of what's open.

## Landed since 2026-09-20 (for context)

- #413 list, task and blockquote reveal, drawn checkboxes with tap-to-toggle; #415 indentation layout and wrapped-row alignment (works in Chromium and the real Electron 33; not tried on a real Android WebView or Safari); #418 Lucide icons for back/swipe/New/Settings, borderless 36×36 icon buttons; #419 About box with a build stamp (commit, branch, build time); #420/#421 storage contract amended for `.quki/`; #422 colours use Obsidian variable names with GitHubDHC defaults, light/dark via body classes, selection visible and no current-line highlight; #423 sans-serif body text, monospace code, no heading underline. Also in the repo: the GitHubDHC reference stylesheet (#416) and the theme audit (#417, `notes/dev/theme-audit-findings.md`).

## Data loss — not urgent, deferred

- [ ] Save is too slow, and new QuKis can get lost (Scott, direct report). Not breaking — Scott has explicitly deferred this until the Rendering / Editor items are done. Relates to the GitHub issues review's "Check" items on auto-save reentrancy/timing (#73, #381, #384, #386) — worth investigating alongside those.

## Rendering / editor

- [x] List/task/blockquote markers never collapse or reveal — only headings, images/hr, and inline formatting (bold/italic/strike/code/links) go through the reveal engine (`reveal/extractElements.ts`).
- [x] No checkbox widget — no visual checkbox, no tap-to-toggle.
- [x] Enter-continues/exits-a-list works (CodeMirror's own default keymap) — but the list still doesn't render, so it just doesn't look like anything.
- [x] Indentation layout (BEHAVIOR_SPEC §12 "How indentation renders") — implemented as per-line decorations in `reveal/decorations.ts` (no explicit runs structure): collapsed list/task/ordered items indent by depth and hang wrapped rows under their content, and a revealed line shows raw source at depth zero. Any list-style line shown raw (revealed, or looking like an item the parser did not make one) hangs its wrapped rows under the text after the marker with a measured float on the line's `::before` whose shape starts at the second row, so the first row and its tab stops are untouched (`reveal/hangingIndent.ts`, `reveal/hangFloat.ts`, `style.css`); it needs no `text-indent: hanging`, so it works in the desktop app's Electron 33 (Chromium 130) and in older WebViews. Plain-text mode adds no decorations, so raw lines there wrap to the margin. Covered by unit tests, `e2e/listReveal.e2e.ts` and `e2e/hangingIndent.e2e.ts` in Playwright's Chromium, and `e2e/hangingIndentElectron.e2e.ts` in the real Electron app (`npm run test:e2e:electron`) — the Android WebView itself is unchecked and needs Scott's on-device check. Known gap: an item whose indentation jumps two or more levels at once, or a lone indented item with no parent (e.g. toolbar Indent on a lone `- item`), is not a list item to the parser and stays raw text, where Flutter treats it as nested.
- [ ] Markdown parsing rules (heading-needs-space, intraword `*` vs `_`, block-relative ordered-list renumbering, etc.) rely on CodeMirror's stock GFM parser — never checked against Flutter's specific rules, no test coverage for the edge cases.
- [x] Font is incorrect — body text is now GitHubDHC's sans-serif, code keeps the monospace stack, headings are bold without an underline (#423). Plain-text mode stays monospace (implementer's call; Scott can override).
- [x] Button style is incorrect — icon-only buttons are borderless 36×36 with a hover/pressed tint and a focus ring (#418); the word buttons (Empty Trash, Grant access, dialog buttons) keep their bordered look, and the rest of the button styling follows the theme work below.
- [x] Some buttons show words instead of icons — New and Settings are icons now (#418). Empty Trash and Grant access stay as words on purpose (Scott's decision).
- [x] Enter on an empty list item that follows another item doesn't exit the list (BEHAVIOR_SPEC §4 "List auto-continue"): `- item⏎⏎- ` stays as `- item\n\n- ` instead of removing the marker; same for `- [ ] ` and `1. `. Only a lone `- ` exits. Reproduces with CodeMirror's bare `insertNewlineContinueMarkup`. Found during list-reveal review; the item above wrongly said exit works.
- [x] Mode-toggle button (`#btn-mode-toggle`) may ignore real mouse clicks: in headless Chromium a mouse click didn't toggle plain-text mode but `element.click()` did. Unconfirmed guess: the icon `replaceChildren` on focus loss swallows the click. Not investigated; base commit not checked.
- [ ] Help dialog: the About box exists (opened from the editor's Help button, #419), but BEHAVIOR_SPEC §7's four link rows (Documentation, Discord, GitHub, Buy me a coffee) are not built, and the list screen's header has no Help button. The Android hardware Back button doesn't close any dialog.
- [o] Quote text sits about 10px right of plain text (the quote line's padding replaces CodeMirror's 6px line inset), where the old app's indent was 16px. Decide together with the blockquote theme variables.
- [x] Some raw list lines in plain-text mode still wrap to the margin (plain-text mode adds no decorations, by spec §12 rule 6).
- [ ] `main.ts` still has its own `setButtonIcon`, which duplicates `screens/icons.ts`'s `setIconButton`.
- [o] A lone indented list item with no parent item (`\t- x`, which toolbar Indent produces on a lone `- item`) is an indented code block to the parser and doesn't collapse; the Flutter app treats it as nested depth 1. Parsing-rule audit territory.

## Theming (variable-compatible with Obsidian, GitHubDHC as the default)

Decided: the app's CSS uses Obsidian's variable names so a theme restyles the whole interface; GitHubDHC ships as the default; a user's theme lives in `.quki/themes/`, travels with the QuKi folder, and is loaded variables-only (plus `@font-face`, default colour scheme only). Details and evidence: `notes/dev/theme-audit-findings.md`.

- [x] Default sans-serif stack: GitHubDHC's `--font-sans` had a missing comma after `-apple-system`. Fixed upstream (ScottKirvan/GitHubDHC #36, merged); the QuKi side (refresh the reference copy in `notes/dev/reference/`, fix our default stack) is in progress.
- [ ] Theme loader: read `.quki/themes/`, reduce a theme to its custom-property declarations and `@font-face`, ship GitHubDHC through the same path. The loader must re-emit a theme's variables under `body.theme-dark` / `body.theme-light` — the app's defaults sit there (specificity 0,1,1), so a theme's own `body {}` or `.theme-dark {}` rules would lose. The defaults are concrete values, so a theme that sets only `--color-base-*` won't move the app's derived variables.
- [ ] Theme picker in Settings (today a static "Theme: System" row) and where the choice is stored (`.quki/`); on web, an in-app import, because OPFS isn't user-visible (`[Proposed — unconfirmed]` in the contract).
- [ ] Export must include the whole `.quki/` directory (contract updated in #421). Blocked on the storage interface: `listDir` returns names only and `FileStat` has no directory flag, so it needs an interface change across the Node, Capacitor and OPFS backends, plus the Electron proxy and the CLI and MCP callers.
- [ ] Non-colour values to Obsidian variables: about 70 hard-coded values (font sizes, radii, spacing), and the editor's quote and list geometry that lives in `reveal/decorations.ts` (quote bar 3px / 16px indent, list indent 16px, marker gutter 24px, 6px line inset). Headings h4–h6 have no CSS at all.
- [ ] Native surfaces don't follow the theme: the Electron window opens white, Android's status/navigation bars and splash, the PWA manifest and `theme-color`.
- [x] Decide on a Content Security Policy (none exists anywhere; lower urgency under variables-only, since themes barely carry remote resources).
- [ ] Colour weaknesses to revisit after on-device testing: light-mode hover/pressed tints are very faint; the light-mode selection is soft (about 1.3:1 against the page); black text on the red Delete button in light is about 3.9:1; the plain confirm dialog is almost the page colour in dark (no border).
- [ ] The nine syntax-highlight colours in `main.ts` are hard-coded and currently unreachable (no fenced code blocks yet); map them to `--code-*` variables when fenced code lands (BEHAVIOR_SPEC §12 puts tables and fenced code in scope).
- [x] Update BEHAVIOR_SPEC §11: GitHubDHC is now the palette authority (light muted text is `#424a53`, not `#59636e`), and the dark selection colour comes from github.com.

## Android

- [X] Release signing: env vars wired (`STORE_FILE`/`STORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD`), real keystore/secrets still needed. Until then every build is debug-signed, and a mismatched real cert would break the Flutter migration path on update.
- [x] Send's success toast always says "Copied to clipboard.", even on Android where it's a real share-sheet send now.
- [ ] Heading-cycle multi-line behavior is `[Proposed — unconfirmed]` — try it by hand with a reversed, mixed-level selection.
- [x] Send tested into Messages only; no second target, no full completed send (no contacts on emulator).
- [x] Share-in's failure-toast path never actually triggered/observed; both paths tested via explicit intent, not the real chooser UI.
- [ ] Toolbar positioning is wrong
- [ ] app icon need to be updated.
- [ ] 

## Desktop

- [x] Windows Send is still clipboard-fallback.
- [x] Electron off-screen multi-monitor window-bounds test — deferred by Scott, still open.

## Repo housekeeping

- [ ] Rewrite `README.md` — currently describes the Flutter app and its toolchain.
- [ ] Rewrite `CONTRIBUTING.md` — currently references Flutter/Dart toolchain and setup.

## Manual acceptance ("Before committing" checklist, Scott's own)

- [x] Reveal at the span level — predates this session, not witnessed directly.
- [x] Checkbox swap mid-typing — no longer blocked (the checkbox widget landed in #413); still to be tried by hand.
- [x] Paste an image — tested, unit + e2e.
- [x] Sidecar-deletion acceptance test — core-level test exists, manual walkthrough not separately confirmed.
- [x] Toolbar pinned, keyboard up — done on emulator, not a physical Pixel.
- [x] "Your worst QuKi" stress test — not attempted.
