# Theme audit — findings

Snapshot of 2026-09-20. Findings and open decisions for making QuKi Notes themeable with Obsidian themes, with GitHubDHC as the default. This is not one of the sources of truth in `README.md`; it records what was found so the work can be sequenced.

Tags: **[V]** verified by reading the code or running something at the time of writing. **[A]** reported by a research agent, not independently re-checked. **[I]** inferred, not tested.

## Decided (Scott, 2026-09-20)

- GitHubDHC ships as the default theme. Users can drop in their own Obsidian theme; the aim is that as much of the Obsidian theme library as possible works.
- The app's CSS becomes variable-compatible: it consumes Obsidian's CSS variable names, so a theme restyles the whole interface (editor, QuKi list, settings, trash, dialogs), not just the editor.
- Themes load **variables only** for now: a theme is reduced to its custom-property declarations and its other rules are ignored. To be tried and evaluated.
- A theme lives in the QuKi folder at `.quki/themes/` so it travels with the folder. The layout inside (proposed: `<name>/theme.css`, as in Obsidian) is unconfirmed.
- Export includes the whole `.quki/` directory, whatever ends up in it (themes, settings, plugins, scripts, ...).
- The look changing to match GitHubDHC is accepted. Flutter is not the style authority.
- Buttons are Lucide SVG icons by design.

## The app today

- **[V]** Style is 8 colour custom properties (`--surface`, `--surface-subtle`, `--text`, `--text-muted`, `--accent`, `--accent-emphasis`, `--border`, `--danger`). None uses an Obsidian name. Dark mode is `@media (prefers-color-scheme: dark)` only; nothing sets `theme-dark` / `theme-light`. Settings shows a static, non-interactive "Theme: System" row.
- **[V]** No Content Security Policy exists anywhere in the repo. The hosted PWA's response headers are unknown; the repo has no web deploy config.
- **[V]** The root scan of the QuKi folder keeps only `.md` names (`core/src/quKiStore.ts`), so a `.quki/` directory is already ignored by the list, search and trash. Only the contract's wording needs to change.
- **[V]** Export is a fixed, flat list: root `*.md`, `.meta/*.json`, `.trash/*.md`, `.trash/.meta/*.json`, `media/*` (`core/src/export.ts`). The storage interface cannot tell files from directories (`listDir` returns names only; `FileStat` has no directory flag), so exporting a whole `.quki/` tree needs an interface change across the Node, Capacitor and OPFS backends. **[A]** The Electron proxy, the CLI and the MCP server call export too.
- **[V]** Some controls are text characters, not Lucide icons: the `←` back buttons (list, settings, setup, trash) and the 🗑 emoji on the swipe-to-delete backgrounds. Several buttons show words: "New", "Settings", "Empty Trash", "Grant access". (Addressed on `fix/lucide-icons-back-and-swipe`.)
- **[A]** The editor's quote and list geometry (16px indent, 3px bar, 24px marker gutter, 6px line inset) is computed in TypeScript (`reveal/decorations.ts`), so making it theme-driven is a code change, not only CSS.

## How Obsidian themes are built

- **[V]** GitHubDHC defines about 600 variables (425 in `body`, 93 in `.theme-dark`, 80 in `.theme-light`), then about 950 lines of rules written for Obsidian's own markup. Its global element rules (`button:not(.mod-cta):not(...)`, `h1`, `h2`, `table`) would restyle QuKi's own buttons and headings if a theme were loaded whole. That is why variables-only was chosen.
- **[V]** In GitHubDHC, `--background-secondary` equals `--background-primary`, so QuKi's "subtle surface" should map to `--background-primary-alt`, not the obvious choice.
- **[V]** None of the 11 themes sampled uses `prefers-color-scheme`; all key on `.theme-dark` / `.theme-light`. The app therefore has to set those classes on the body.
- **[A]** Sample: the 6 most-downloaded community themes (Minimal, Things, AnuPpuccin, Blue Topaz, Obsidian Nord, Atom), plus GitHubDHC and four extras. Download counts came from `releases.obsidian.md/stats/theme`. Tools were a CSS parser and a hand-written list of Obsidian class names; the error is estimated at a few percentage points.
  - Palette-style themes (Nord, Atom, Wasp, GitHubDHC, Typewriter) keep most of their character on variables alone: 91–100% of their colour values sit in variable definitions.
  - Designed and component-heavy themes (Minimal, Things, AnuPpuccin, Blue Topaz, ITS, Obsidianite) keep a base palette but lose the structure that distinguishes them. Minimal, AnuPpuccin and Blue Topaz are 65% of the top-six downloads. Expect "recoloured", not "reproduced", for these.
  - Only 32 documented variables are set by 5 or more of the 7 main themes, and none is a font, radius or size. The app must supply its own defaults for everything a theme leaves unset (GitHubDHC leaves at least 14 documented variables undefined).
  - 10 of 11 themes embed fonts as `data:` URIs; none uses a remote `@font-face` or `@import`; one has a single remote image. Typewriter's look is mostly its embedded fonts (about 886 KB).
  - Some themes keep their colour schemes behind body-class modifiers (Minimal has about 15 `.minimal-*-light/dark` schemes). Reading only the base scopes gives their default scheme.
  - Distribution: each repo has `theme.css` and `manifest.json` (Atom has neither a manifest nor a release). Most also carry an `obsidian.css`. Files run up to 1.28 MB. Most embed Style Settings YAML in a comment.
  - Only 21 Obsidian classes are targeted by 7 or more of the 11 themes. This matters only if theme rules are ever loaded; under variables-only it does not.

## Mapping the app's variables

- **[A]** The 8 app properties match `BEHAVIOR_SPEC.md` §11 exactly. Under GitHubDHC: `--surface` → `--background-primary`, `--surface-subtle` → `--background-primary-alt`, `--text` → `--text-normal`, `--border` → `--background-modifier-border`, `--danger` → `--text-error`, `--accent-emphasis` → `--text-accent-hover`. `--accent` does two jobs (link text and fills) and Obsidian has two variables for them (`--text-accent`, `--interactive-accent`; in GitHubDHC dark the latter is grey).
- **[A]** In light mode GitHubDHC's muted text is `#424a53`, where §11 says `#59636e`. GitHubDHC is now the authority, so §11's light column may need correcting.
- **[A]** About 70 non-colour values (about 55 in CSS, 17 in TypeScript) need converting: roughly 25 map directly, 20 approximately, 10 have no Obsidian equivalent.
- **[I]** Defaults must be declared on `body` / `.theme-*`, not `:root`, or a theme that overrides only base colours will not re-resolve the chained defaults.
- **[A]** Adopting GitHubDHC's values changes the look: headings 1.6/1.35/1.15em → 2/1.5/1.25em; bold 700 → 600; quote bar 3px → 4px and quote text no longer muted; rule 1px → 4px; list indent 16px → 32px; checkbox 20px → 15px; light inline-code background darker; shadows removed.

## Platforms

- **[A]** A theme file can be read through the existing `exists` + `readText` on all three backends; no core change to read. The earliest common point is right after the backend is built in `src/main.ts`, before the trash purge. The setup and permission overlays, and first paint, always use the bundled CSS, so the default theme must be compiled in.
- **[A]** Native surfaces do not follow a theme: Electron's window opens white (no `backgroundColor`), Android's status/navigation bars follow the phone's night mode, the Android splash is a white image, and the PWA manifest and `theme-color` meta tag are static light values.
- **[A]** Nothing watches the folder, so a changed theme is seen at the next startup. On web (OPFS), storage is not user-visible, so a theme needs an in-app import. Changing folder location in Electron does not reload theme state.
- **[A]** Injecting a `<style>` element should work on all three platforms. A relative `url(...)` in a theme resolves against the app, not the QuKi folder, so theme font files would need loading through `readBinary` as blob URLs, as images are.

## Contract changes needed (`STORAGE_CONTRACT.md`)

- Rule 9: name `.quki/` as structural, never scanned for QuKis.
- "Export everything": define it as QuKis, sidecars, media and the whole `.quki/` directory.
- Note that a theme's Obsidian `manifest.json` is unrelated to the banned "manifest listing all QuKis", and avoid storing it under that name if the word causes confusion.
- Keep themes out of `.meta/`: Acceptance Test 2 deletes that whole directory.

## Open decisions

1. Should the loader keep a theme's `@font-face` rules as well as its variables? They are `data:` URIs, so no remote risk; without them some themes lose their look.
2. Which selectors count as the variable layer? Proposed: `body`, `:root`, `.theme-dark`, `.theme-light` only.
3. Whether to add a Content Security Policy. Lower urgency under variables-only.
4. Whether native surfaces (Electron window, Android bars and splash, PWA manifest) should follow the theme.
5. Where the active theme choice is stored (`.quki/` is the natural place).
6. Later: consent and sandboxing before `.quki/` may hold scripts or plugins, since content that syncs into the folder could then run code.

## Proposed sequence [Proposed — unconfirmed]

1. Contract amendment (docs).
2. Variable layer: map the app's colours to Obsidian's names, add the defaults layer and the `theme-dark` / `theme-light` bridge, ship GitHubDHC through the same loader path.
3. Theme loader: read `.quki/themes/`, in-app import for web, theme picker in Settings.
4. Editor geometry driven by variables; h4–h6 headings.
5. Export of the whole `.quki/` tree (storage-interface change).
6. Native surfaces.

## Caveats

Nothing was rendered; the look changes and the judgement of how much of each theme survives are inferred. The theme sample is the head of the distribution (779 community themes are listed). No real Android WebView, Electron window or hosted PWA was exercised.
