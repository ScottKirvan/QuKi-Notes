# Open Questions

Genuinely unresolved items. When implementation forces an answer, **move the entry to `decisions.md`** with the resolution and link the PR that settled it.

Do not implement past one of these without proposing a resolution in the PR body.

---

## ~~OQ-1: WYSIWYG markdown rendering~~ — **Resolved (v0.9.1, PR #54)**

**Resolution**: Stayed on `super_editor`. Two-part fix:
1. `_parseBody` / `_extractBody` replaced with `deserializeMarkdownToDocument` / `serializeDocumentToMarkdown` (both built into `super_editor`; `super_editor_markdown` companion package deprecated and merged upstream). `MarkdownSyntax.normal` used for GFM compatibility.
2. Custom `EditReaction` subclasses added in `lib/features/editor/markdown_inline_reactions.dart`: bold (`**x**`), italic (`_x_`, `*x*`), inline code (`` `x` ``), task list (`- [ ] `). Block reactions (headings, lists, blockquote) were already provided by `createDefaultDocumentEditor`. ADR-24.

Fenced code block rendering deferred (Scott decision — not a priority for quick-capture use case).

---

## ~~OQ-2: super_editor image node integration~~ — **Removed**

**Resolution**: `super_editor` was replaced by the single-buffer `markdown_live_editor` package (ADR-30, v0.15.1). The `super_editor`-specific integration question is moot. Image paste (Phase 1.4) remains blocked by CargoKit being archived; when that work is unblocked, the integration point will be in `markdown_live_editor`'s `buildTextSpan()` via a `WidgetSpan` for `![](...)` lines, or a post-processing step. A new OQ will be opened at that time.

---

## OQ-3: GitHub OAuth App `client_id` distribution (deferred)

Defers to whichever plugin first needs GitHub OAuth (likely the GitHub sync plugin in Phase 4, or a GitHub-flavoured transport before that).

When that PR lands, decide:

- (a) Committed as a constant in the plugin
- (b) Injected via `--dart-define=QUKI_GH_CLIENT_ID=...` at build time
- (c) Read from `assets/config.json` at runtime

`client_id` is not secret per the OAuth spec; (a) is acceptable unless the repo goes public AND a different OAuth App is needed per fork.

**Surface during:** First PR that introduces an OAuth-needing plugin.

---

## OQ-4: Initial-sync progress UX threshold (deferred to sync work)

Bulk-pull progress banner: always, or only above some threshold? Decision belongs with the first sync plugin in Phase 4.

**Likely resolution:** time-based — show banner if sync hasn't completed within 1–2 seconds.

---


## OQ-NEW-4: Linux `flutter_secure_storage` keyring matrix

`flutter_secure_storage` on Linux uses `libsecret`, which requires a Secret Service implementation (GNOME Keyring, KeePassXC's secret-service, KWallet bridge). On a vanilla server install or a headless WM there may be no Secret Service running.

**Risk:** plugins that store tokens (any OAuth-using transport, any sync backend) fail to initialize on Linux when no keyring is available.

**Options:**
- (a) Hard fail with clear error directing user to install + start gnome-keyring (or equivalent).
- (b) Fall back to an encrypted-at-rest file in the app docs dir (security ≈ zero against local-user attacker but workable for a personal app).
- (c) Refuse to install plugins that need secrets when keyring is absent.

**Surface during:** First plugin that calls `flutter_secure_storage` on Linux.

---

## ~~OQ-6: Link tap behavior in rendered mode (ADR-31)~~ — **Resolved 2026-07-04**

**Resolution**: Tap navigates (opens the URL). Reveal-and-edit is triggered by cursor entering the element via keyboard: arrow-key in from either side, or backspace in from the right. Cursor landing at the start or end boundary of the source range also reveals — consistent with the boundary rule for all other element types.

**Reasoning**: QuKi-Notes is a scratchpad and pastebin as much as a capture surface; following links (e.g., a parts list with product URLs) is a primary workflow. Navigate-on-tap matches that use case and matches the expectation of every other reading surface. Keyboard-entry is the natural and frictionless path to edit mode; no special gesture is needed. Obsidian's split-behavior (click-navigates, edge-tap/modifier-click reveals) was considered but the keyboard-only reveal path is simpler and sufficient.

**Recorded in**: ADR-31 links bullet, `notes/dev/decisions.md`.

---

## Resolved / Removed

- **OQ-5: Workflow JSON schema validation** — **Removed.** Workflow JSON DSL dropped entirely per ADR-14. Transports are Dart code; no JSON schema to validate.

- **OQ-NEW-1: Which built-in QuKi-Toss ships first?** — **Resolved (Phase 2, v0.5.0).** Both ClipboardToss and ShareSheetToss shipped in the same Phase 2 PR. Clipboard proved the loader + UI first (zero deps, zero auth); Share Sheet followed immediately. Append-to-GitHub-file deferred until the OAuth helper exists (Phase 4+). No new ADR needed — consistent with the "likely resolution" stated at spec time.

- **OQ-NEW-2: Plugin discovery model** — **Resolved (Phase 2, v0.5.0).** Built-in compile-time registry only (`lib/core/transports/registry.dart`). Every transport ships in the same APK; new transports require a new app version. Re-evaluate if third parties start writing transports post-v1.

- **OQ-NEW-3: Linux distribution format** — **Resolved (Phase 3, `build-linux.yml`).** Tarball (`quki-notes-linux.tar.gz`). Promote to AppImage only if Linux usage justifies it; Flatpak/Snap only if a user explicitly requests it.

---

**Last Updated**: 2026-07-04
