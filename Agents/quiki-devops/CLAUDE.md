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

### Fix Android release signing — cert mismatch between v0.8.1 and v0.9.1

**Priority:** Blocking — upgrade installs from GitHub Releases are rejected by Android.

---

#### Root cause (fully diagnosed)

Two separate but compounding problems:

**Problem 1 — `build.gradle.kts` hardcodes debug signing for release builds.**

`android/app/build.gradle.kts` line 31:

```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        // Signing with the debug keys for now, so `flutter run --release` works.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

The CI workflow (`build-android.yml`) correctly decodes `KEYSTORE_BASE64` into
`android/app/keystore.jks` and exports `STORE_FILE`, `STORE_PASSWORD`, `KEY_ALIAS`,
`KEY_PASSWORD` as env vars — but Gradle never reads them. Every APK, from every
release, is signed with the debug key of whatever runner instance executed the build.

**Problem 2 — Android debug keystores are ephemeral and per-runner-instance.**

The Android debug keystore (`~/.android/debug.keystore`) is auto-generated fresh on
each clean GitHub Actions runner. v0.8.1 and v0.9.1 were built on different runner
instances → different debug certs → Android rejects the upgrade.

**Why didn't this surface earlier?** The `release:published` trigger was not properly
wired (the PAT fix landed at `b561790`, June 2 2026, which is after v0.8.1 at
`6ee2b21`). Earlier releases may have been manually dispatched or triggered via the
since-removed `push:tags` path. Once the trigger fired reliably for v0.9.1, the
mismatch became observable.

---

#### Fix required (Implementation session NOT needed — this is pure CI/build config)

Two changes, both in this session's ownership:

**Change A — Wire the keystore into `android/app/build.gradle.kts`.**

Replace the `buildTypes` block with a proper `signingConfigs` block that reads the
env vars the CI workflow already provides:

```kotlin
signingConfigs {
    create("release") {
        storeFile = file(System.getenv("STORE_FILE") ?: "keystore.jks")
        storePassword = System.getenv("STORE_PASSWORD")
        keyAlias = System.getenv("KEY_ALIAS")
        keyPassword = System.getenv("KEY_PASSWORD")
    }
}

buildTypes {
    release {
        val hasSigningEnv = System.getenv("STORE_PASSWORD") != null
        signingConfig = if (hasSigningEnv) {
            signingConfigs.getByName("release")
        } else {
            // Local dev: fall back to debug so `flutter run --release` still works.
            signingConfigs.getByName("debug")
        }
    }
}
```

This keeps local `flutter run --release` working (no env vars set) while ensuring CI
signs with the real keystore.

**Change B — Verify the four secrets are actually populated in GitHub repo settings.**

Before the next release, confirm in GitHub → Settings → Secrets and variables →
Actions that these secrets exist and are non-empty:

- `KEYSTORE_BASE64`
- `STORE_PASSWORD`
- `KEY_ALIAS`
- `KEY_PASSWORD`

If any are missing or empty, the "Decode keystore" step will write a zero-byte or
garbage file and Gradle will fail to sign (or silently fall back to debug). If the
secrets were never populated, every release to date used a random ephemeral debug key —
that must be treated as if the app was unsigned and users will need to uninstall before
installing the first properly-signed release.

---

#### Files to touch

| File | Change |
|---|---|
| `android/app/build.gradle.kts` | Add `signingConfigs` block; update `buildTypes.release` |
| `build-android.yml` | No change needed — env vars are already correct |

#### Files to NOT touch

`lib/`, `test/`, `notes/dev/` — none of this is app code.

#### Commit message

```
fix(android): wire release signing config to CI keystore env vars

build.gradle.kts was hardcoding signingConfigs.getByName("debug") for
release builds, causing every APK to be signed with the runner's ephemeral
debug key. Add a signingConfigs.release block that reads STORE_FILE,
STORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD from env, falling back to debug
only when env vars are absent (local dev). Fixes cert mismatch between
consecutive GitHub Releases.
```

#### Post-fix checklist

- [ ] Confirm secrets are populated in GitHub repo settings
- [ ] Merge the fix PR to main
- [ ] Let release-please create the next release normally (do NOT manually tag)
- [ ] Verify the build workflow run signs with the keystore (check the "Decode
      keystore" step — it should succeed silently; a failure there means
      `KEYSTORE_BASE64` is empty)
- [ ] Download the new APK and install over the previous one — upgrade should succeed
