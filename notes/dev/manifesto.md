# QuKi Manifesto

> Normative. Every other doc in this folder should be consistent with this one. When the spec drifts from the manifesto, the spec is wrong.

---

## Origin — Why This Exists

QuKi-Notes is **not** "Drafts for Android". It is a personal capture environment, built because nothing on the market hits the four constraints that matter most to ephemeral note capture:

1. **Velocity** — open the app, type, done. No "+ New", no template picker, no title field, no folder choice. A copious notetaker (Scott captures many QuKis per day) cannot afford one second of friction per capture.
2. **Open data** — markdown body, plain SQLite on disk, no proprietary serialization, no cloud lock-in, no "export your data" button needed because the data was never locked up in the first place. "No closed formats" is a hard requirement, no just a preference.
3. **Information-first UI** — minimal chrome. The QuKi is the interface; the app gets out of the way.
4. **Extensible dispatch** — the value of a QuKi is realized when it gets used or goes somewhere else (a short-term todo list, a daily log, a chat, a task tracker, a wiki entry, a draft). That "somewhere else" is highly personal, so it must be customizable; a **plug-in**. Hard-coded integrations age badly; transports are the answer.

Reference points (none of which fit):

- **iOS Drafts** — closest historical match (Scott customized it heavily with iOS automations) but it's iOS-only and closed source... the vibe is that insufferable, arrogant Apple-bro attitude. Not viable post-migration to Pixel.
- **Obsidian** — a *vault*. Wrong shape. Treats notes as durable knowledge artefacts to be linked and curated. QuKis are the opposite: ephemeral by framing, organized only by recency.  Obsidian is a great app, but it's a destination for QuKis, not an origin.
- **Apple/Google Notes, OneNote, Evernote, etc.** — proprietary formats, cloud-coupled, "rich" features, etc.  All things that add friction at capture time.
- **Plain text files + a launcher hotkey** — close, but no transport story, no cross-device story, no image paste, no mobile share-in.

QuKi-Notes exists in the gap: the velocity of Drafts, the openness of MIT licensing and plain markdown, the extensibility of a plugin model, the mobile-and-desktop reach of Flutter, on a stack of strict, function-first controls end-to-end.

This origin shapes every decision below. When in doubt, ask: *does this serve velocity, openness, information-first, or extensible dispatch?* If none of the four — push back.

---

## What a QuKi Is

A **QuKi** is a short note, a picture, a thought, a temporary list, a rough draft — captured in the moment.

QuKis live in the now. They are not filed, tagged, organized, foldered, or curated. They surface what's current and let older entries age off the top of the list.

A QuKi's job is **temporary**. Its purpose is to be there for you, frictionlessly, on whatever device is in your hand, and then to either:

1. Get **sent** somewhere (a daily log, a GitHub issue, a Slack message, an email draft) via a transport, or
2. Drift quietly down the list as something newer takes its place.

A QuKi is, under the hood, a markdown file with optional attached images. That is an implementation detail. The user never thinks about files.

---

## What QuKi-Notes Is

**QuKi-Notes** is the app — the capture surface and the transport hub. One blank editor on launch. No friction.

- **QuKi** — a single ephemeral note.
- **QuKi-Notes** — the application.
- **Transport** — a plugin that dispatches a QuKi somewhere. User-facing action: **Send...** (in the editor menu). Internal/code term: transport. Transports are architecturally bidirectional (output now; input/templating is a later version).

---

## What QuKi-Notes Is NOT

This is the load-bearing list. If a feature request violates one of these, push back.

- **Not a vault.** No folders. No tags. No backlinks. No graph view. No daily-notes-with-templates.
- **Not an organizer.** No projects, no tasks system, no kanban, no calendar.
- **Not a knowledge base.** No wiki linking, no second-brain rituals, no PARA / Zettelkasten ceremony.
- **Not a backup system.** Sync exists (opt-in, post-MVP) to move QuKis across **your own** devices — not to guarantee durability against device loss. If you lose your phone before a toss, the QuKi is gone, and that's fine — that's what a QuKi is.
- **Not a publishing tool.** Markdown output is a transport implementation detail, not a feature.
- **Not Obsidian.** Obsidian gets a glue plugin so you can toss to a vault; QuKi-Notes is not trying to be Obsidian-lite.

If you find yourself building "lightweight folders" or "a tagging system you can opt out of" — stop. That's a vault. Go use Obsidian. That's why the glue plugin exists.

---

## Tonality

The product voice is **calm, present-tense, slightly dry**. Not aggressively minimalist. Not zen-app preachy. Not productivity-bro.

- Use "QuKi" as a noun in user-facing copy. Plural: **QuKis**.
- The capture screen has no "title", no "untitled note", no "new document". It's just a blank field.
- The list view screen title is **QuKis**. Not "stream", "library", "inbox", or "documents". "Stream" is acceptable as internal/code terminology only.
- The user-facing send action is **Send...** — it appears in the editor's hamburger menu (≡). Internal code uses "toss"/"transport" — this distinction is intentional and does not need to align with UI copy.
- Error states are matter-of-fact. "Send failed — try again" not "Oops! Something went wrong 😅".
- No emoji in UI strings unless the user typed them.

**Editor navigation**: the editor is the **permanent root** of all navigation. It never has a back button under any circumstance. Its chrome never changes regardless of which QuKi is loaded.

- Top-left: **QuKis icon** — pushes the QuKis list on top of the editor.
- Top-right: **hamburger menu ≡** — contains **Send...**, **QuKis**, **Settings**.

**QuKis list** (always pushed on top of the editor, never replaces it):
- Back button (top-left) → pops back to editor.
- Tap a row → loads that QuKi's content into the root editor + pops the list.
- `+ New` → clears the root editor to blank + pops the list.

The editor is **one widget**. Its content changes (blank QuKi, or a specific loaded QuKi); its chrome does not. There is no scenario where a second EditorScreen is pushed onto the navigation stack.

---

## The Three Plugin Axes

QuKi-Notes is a **capture + dispatch** app with three independent plugin layers:

| Layer        | What it does                                                                 | MVP status                            |
| ------------ | ---------------------------------------------------------------------------- | ------------------------------------- |
| **Transports** | Take a QuKi (text + images) and deliver it somewhere. Stateless per-fire. Architecturally bidirectional; input/templating is a later version. | **Yes** — at least one built-in transport (Send via clipboard + share sheet). |
| **Sync**     | Move QuKis between this user's own devices. Opt-in. Off by default.          | **No** — v1.1+ (plugin axis defined). |
| **MCP**      | Expose QuKi-Notes (read/list/append/toss) to AI agents over Model Context Protocol. | **No** — v2.0+ (axis reserved, not built). |

These are **separate axes**. A user can have transports without sync. Sync without transports. Both. Neither.

Core app responsibility: **plugin management** + the editor + the stream + file plumbing for plugins to consume. Plugins do the actual moving-data-around work.

---

## Ephemerality Model — "Gmail-Style"

QuKis are framed as ephemeral, but **nothing is auto-deleted** without explicit user action.

- Default storage: forever (local SQLite). Like Gmail — you don't delete, you just stop seeing it as older items push it down.
- The **QuKis list** surfaces newest-first. Older QuKis fall off the visible viewport but remain searchable.
- Search exists because sometimes you need to find that one thing from three weeks ago. Search is **not** organization. It's recall.
- A QuKi that's been **sent** is still a QuKi — sending copies, it doesn't move. The local copy lingers in the list.
- The user can delete a QuKi explicitly. Deleted QuKis move to **Recently Deleted** for a user-configurable retention period (default TBD) before permanent deletion. This is **data recovery**, not organization — Recently Deleted has no sorting, filtering, or filing. Hard-delete from Recently Deleted is permanent and immediate.

The point: the user is told "these are ephemeral, don't treat them as a vault" — and the app's behaviour reinforces that framing without enforcing destruction.

---

## Platform Priority

1. **Android** — primary daily-driver target.
2. **Windows** — desktop companion.
3. **Linux** — third active target (Flutter Linux desktop; quality risk tracked as an OQ).
4. **iPadOS / iOS / macOS** — codebase supports them via Flutter; builds deferred (macOS GitHub Actions runner cost).

Single Flutter codebase. No platform-specific rewrites. Deferred platforms only need a CI build job + device testing when reactivated.

---

## What's In MVP (v1.0)

- Single-device local capture (Android first, Windows + Linux follow).
- **Markdown WYSIWYG editor** — live rendering as you type. Typing `**text**` renders bold; `- [ ]` renders a task list item; `# ` renders a heading; etc. This is a hard requirement, not a nice-to-have.
- Image paste / share-in.
- QuKis list (newest-first, search, delete).
- **Recently Deleted** — data recovery screen; user-configurable retention; hard-delete from there is permanent.
- **At least one transport plugin** (built-in) — proves the plugin loader + the Send UX.
- Settings for transport configuration.
- No sync. No GitHub OAuth. No MCP.

That's it. Anything beyond this list is post-MVP unless explicitly promoted via an ADR.

---

## What's Out of MVP (Deferred)

- **Sync plugins** (any backend): v1.1+. GitHub is one possible backend, not the only one and not privileged. (`core/sync/` skeleton lands when the first sync plugin lands, not in MVP.)
- **MCP layer**: v2.0+. Architecture is sketched in the spec so v1 doesn't paint into a corner.
- **CLI**: lives in the repo as a sibling target sharing the core library. Not shipped as a separate package on first cut. Working hypothesis in `cli_design.md`.
- **Workflow DSL / JSON definitions / cross-device workflow files**: dropped. Workflows are **code** (transport plugins), not data files.
- **iOS / macOS / iPad builds**: deferred (codebase compiles, CI doesn't run them).

---

## Hard Rules for Implementation

- The word **"vault"** does not appear in user-facing copy or in code identifiers. (It can appear in docs when discussing what QuKi-Notes is NOT.)
- The word **"workflow"** is reserved for internal historical context only. It has no user-facing role.
- User-facing send action is **Send...** Internal/code terminology uses "toss" / "transport" — this distinction is intentional and does not need to align with UI copy.
- The list view screen title is **QuKis**. The word "stream" does not appear in UI copy; it is acceptable in internal code and docs.
- "Notes" the noun does appear (the app is called QuKi-**Notes**) but in code and prose prefer **QuKi** / **QuKis** for the entity.
- The root editor has no back arrow. A QuKis icon (top-left) and hamburger menu ≡ (top-right) are the only navigation affordances on the home editor.
- No analytics, no telemetry, no crash reporting. Ever. (See ADR-12.)
- OAuth tokens and full QuKi contents are never logged.
- Plugins (transport / sync / MCP) live behind explicit interfaces in `lib/core/`. The app does not call plugin internals directly.

---

## When To Re-Read This

- At the start of every implementation session.
- Before any PR that touches user-facing copy, the editor, the stream UI, or settings.
- Whenever a feature suggestion sounds like "but what if we also…" — check it against the "Is NOT" list first.

---

**Last Updated**: 2026-06-03
