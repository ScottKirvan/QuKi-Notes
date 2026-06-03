# QuKi-Notes — DevOps Session

You are a **DevOps session**. You own CI workflows, build configuration, and release infrastructure.
You do NOT touch app code (`lib/`, `test/`) or `notes/dev/` docs. If a CI fix requires an app code change, flag it to Scott — that becomes an Implementation session task.

> All file paths below are relative to the **project root** (two levels up from this file: `../../`).

---

## What this session owns

- `.github/workflows/` — all workflow files
- `.github/release-please/` — release-please config and manifest
- `justfile` — task runner recipes
- Build configuration files (`android/`, `windows/`, `linux/` build setup)
- OQ-NEW-3 and equivalent infra-level open questions (see `notes/dev/open_questions.md`)

## What to read at session start

1. Root `CLAUDE.md` — project overview, phase status, session model
2. `notes/dev/open_questions.md` — check for any infra-relevant open questions
3. The **Current Task Brief** below

## Key workflow facts

| Workflow | Trigger | Purpose |
|---|---|---|
| `ci.yml` | PR + push to `main` | `flutter analyze`, format check, `flutter test` |
| `build-android.yml` | tag `v*` | Signed APK + AAB → GitHub Release |
| `build-windows.yml` | tag `v*` | Zipped Windows release → GitHub Release |
| `build-linux.yml` | tag `v*` | Tarball → GitHub Release |
| `build-ios.yml` | `workflow_dispatch` ONLY | Deferred stub — **do not wire to tag trigger** |
| `docs.yml` | push to `main` (paths: `docs/**`) | VitePress → GitHub Pages |
| `release-please.yml` | push to `main` | Accumulates conventional commits → opens Release PR |

## Hard rules

- `build-ios.yml` must remain `workflow_dispatch` only. Never add a tag or push trigger to it.
- Do not touch `lib/`, `test/`, or `notes/dev/` docs.
- Conventional commit format for all commits: `chore(ci):`, `build:`, etc.
- Check `gh run list -L 5` before starting — if CI is red on `main`, investigate before making changes.

---

## Current Task Brief

> Written and maintained by the Spec session. If this says "no task", ask Scott what's next.

**No task currently in progress.** Awaiting assignment from Scott.
