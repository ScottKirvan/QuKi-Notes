# QuKi Manifesto

> Normative. Every other doc in this folder should be consistent with this one. When the spec drifts from the manifesto, the spec is wrong.

---

## Origin — Why This Exists

QuKi-Notes is **not** "Drafts for Android". It is a personal capture environment, built because nothing on the market hits the four constraints that matter most to ephemeral note capture:

1. **Velocity** — open the app, type, done. No "+ New", no template picker, no title field, no folder choice. A copious notetaker (Scott captures many QuKis per day) cannot afford one second of friction per capture.
2. **Open data** — individual `.md` files on disk, no proprietary serialization, no cloud lock-in, no "export your data" button needed because the data was never locked up in the first place. A non-technical user can browse the app's documents folder and read every QuKi as a plain text file. "No closed formats" is a hard requirement, not just a preference.
3. **Information-first UI** — minimal chrome. The QuKi is the interface; the app gets out of the way.
4. **Extensibility** — what you do with a QuKi is personal. You might use it right there in the app. It might fade into the list as newer thoughts arrive. When you do want to send it somewhere else (a daily log, a chat, a GitHub issue, a wiki entry), that destination must be customizable; a **plug-in**. Hard-coded integrations age badly; transports are the answer.

Reference points (none of which fit):

- **iOS Drafts** — closest historical match (Scott customized it heavily with iOS automations) but it's iOS-only and closed source... the vibe is that insufferable, arrogant Apple-bro attitude. Not viable post-migration to Pixel.
- **Obsidian** — a *vault*. Wrong shape. Treats notes as durable knowledge artefacts to be linked and curated. QuKis are the opposite: ephemeral by framing, organized only by recency. Obsidian is a great app, but it's a destination for QuKis, not an origin.
- **Apple/Google Notes, OneNote, Evernote, etc.** — proprietary formats, cloud-coupled, "rich" features, etc. All things that add friction at capture time.
- **Plain text files + a launcher hotkey** — close, but no transport story, no cross-device story, no image paste, no mobile share-in.

QuKi-Notes exists in the gap: the velocity of Drafts, the openness of MIT licensing and plain markdown, the extensibility of a plugin model, the mobile-and-desktop reach of Flutter, on a stack of strict, function-first controls end-to-end.

This origin shapes every decision below. When in doubt, ask: *does this serve velocity, openness, information-first, or extensibility?* If none of the four — push back.

---

## What a QuKi Is

A **QuKi** is a short note, a picture, a thought, a temporary list, a rough draft — captured in the moment.

QuKis live in the now. They are not filed, tagged, organized, foldered, or curated. They surface what's current and let older entries age off the top of the list.

A QuKi's job is **temporary**. Its purpose is to be there for you, frictionlessly, on whatever device is in your hand, and then to either:

1. Get **sent** somewhere via a transport, or
2. Drift quietly down the list as something newer takes its place.

---

## What QuKi-Notes Is

**QuKi-Notes** is the app — the capture surface. One blank editor on launch. No friction. Transports are there when you want them.

For vocabulary (QuKi, Transport, Send vs toss, stream vs QuKis) see `design_spec.md` → Vocabulary.

---

## What QuKi-Notes Is NOT

This is the load-bearing list. If a feature request violates one of these, push back.

- **Not a vault.** No folders. No tags. No backlinks. No graph view. No daily-notes-with-templates.
- **Not an organizer.** No projects, no tasks system, no kanban, no calendar.
- **Not a knowledge base.** No wiki linking, no second-brain rituals, no PARA / Zettelkasten ceremony.
- **Not a backup system.** Sync exists (opt-in, post-MVP) to move QuKis across **your own** devices — not to guarantee durability against device loss. If you lose your phone before sending a QuKi anywhere, the QuKi is gone, and that's fine — that's what a QuKi is.
- **Not a publishing tool.** Markdown output is a transport implementation detail, not a feature.
- **Not Obsidian.** Obsidian gets a glue plugin so you can send to a vault; QuKi-Notes is not trying to be Obsidian-lite.

If you find yourself building "lightweight folders" or "a tagging system you can opt out of" — stop. That's a vault. Go use Obsidian. That's why the glue plugin exists.

---

## Tonality

The product voice is **calm, present-tense, slightly dry**. Not aggressively minimalist. Not zen-app preachy. Not productivity-bro.

- Error states are matter-of-fact. "Send failed — try again" not "Oops! Something went wrong 😅".
- No emoji in UI strings unless the user typed them.
- User-facing copy follows the vocabulary in `design_spec.md`. The distinction between user-facing terms and internal/code terms is intentional.

---

## The Three Plugin Axes

QuKi-Notes is a **capture-first** app with three independent plugin layers:

| Layer | What it does | Status |
|---|---|---|
| **Transports** | Deliver a QuKi somewhere. Stateless per fire. | **MVP** — shipped |
| **Sync** | Move QuKis across your own devices. Opt-in. | **v1.1+** |
| **MCP** | Expose QuKi-Notes to AI agents over Model Context Protocol. | **v2.0+** |

These axes are independent. The app functions with any combination.

---

## Ephemerality Model

QuKis are **framed as ephemeral but never auto-deleted** without explicit user action — "Gmail-style": you don't delete, you just stop seeing it as newer things push it down.

Sending a QuKi doesn't remove it. The local copy remains in the list. The user controls deletion; deleted QuKis are recoverable until the user permanently purges them.

The point: the app's behavior reinforces the ephemeral framing without enforcing destruction.

For storage and deletion implementation details see `decisions.md` → ADR-25 and `design_spec.md`.

---

## Platform Priority

1. **Android** — primary daily-driver target.
2. **Windows** — desktop companion.
3. **Linux** — third active target.
4. **iPadOS / iOS / macOS** — codebase supports them via Flutter; builds deferred.

Single Flutter codebase. No platform-specific rewrites. Code must remain compatible with deferred platforms from day one — no regressions to fix when they activate.

---

## MVP Scope

MVP proves the four pillars work together on a single device: capture without friction, data that's always yours, minimal chrome, and at least one working transport. See `design_spec.md` for the full feature list and deferred items.

---

## Implementation Rules

Implementation hard rules live in `session_protocol.md`. Read that at the start of every implementation session.

---

## When To Re-Read This

- At the start of every session.
- Before any PR that touches user-facing copy, the editor, the stream UI, or settings.
- Whenever a feature suggestion sounds like "but what if we also…" — check it against the "Is NOT" list first.

---

**Last Updated**: 2026-06-18
