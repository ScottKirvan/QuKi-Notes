# Bootstrap — Phase 0

> **One-shot doc.** This is the **first** implementation session's task list. Once the bootstrap PR is merged, this file becomes reference-only.

Audience: **Implementation Claude (Sonnet)**, with Scott observing.

Goal: a single PR that lands a green-CI scaffold matching `design_spec.md`'s Project Structure. After merge, Phase 1 actual feature work begins on subsequent PRs.

---

## Pre-flight (do these in order, stop if any fail)

1. **Read `manifesto.md` first**, then the rest of the required-reading list in `CLAUDE.md` → "Notes for Implementation Claude". Especially `design_spec.md` → Project Structure, Tech Stack, Phases, and `dependencies.md` for the full package list.

2. **Verify Scott has done the setup:**
   - `flutter --version` works
   - `flutter doctor` is green (Android device + Windows desktop; Linux desktop is a nice-to-have at bootstrap, required by Phase 3)
   - `gh auth status` shows logged-in
   - `just --version` works
   - The empty repo exists on GitHub and is cloned locally as the working directory

3. **Confirm with Scott:**
   - **No GitHub OAuth `client_id` needed at bootstrap** — MVP has no OAuth (ADR-9 deferred). Skip OQ-3 discussion until Phase 4 (sync) or whenever the first OAuth-needing transport ships.
   - The `--org` reverse-DNS prefix for Android/iOS bundle IDs. **Default proposal: `com.quki`** → bundle ID will be `com.quki.quki_notes`. Confirm or override.

4. **Branch:**

   ```bash
   git checkout main
   git pull
   git checkout -b chore/phase0-bootstrap-scaffold
   ```

---

## Steps

### Step 1 — Generate Flutter project

From repo root (where `notes/`, `CLAUDE.md`, `.editorconfig` already live):

```bash
flutter create . \
  --platforms=android,windows,linux,ios,macos \
  --org com.quki \
  --project-name quki_notes \
  --description "QuKi-Notes — capture and send ephemeral notes."
```

This adds `lib/`, `android/`, `windows/`, `linux/`, `ios/`, `macos/`, `test/`, `pubspec.yaml`, etc. alongside the existing planning docs.

iOS and macOS scaffolds are created so the codebase compiles for them; they're **not** wired to CI per `CLAUDE.md`. Linux is active (Phase 3 target) and **is** wired to CI.

### Step 2 — Configure `pubspec.yaml`

Replace the generated file. Use `dependencies.md` as the source of truth for which packages belong in Phase 1. Concretely:

- `name: quki_notes`
- `description: QuKi-Notes — capture and send ephemeral notes.`
- `publish_to: 'none'`
- `version: 0.1.0+1`
- `environment.sdk: '>=3.5.0 <4.0.0'` (or current stable)
- `dependencies:` — every Phase 1 runtime entry in `dependencies.md`
- `dev_dependencies:` — every Phase 1 dev entry in `dependencies.md`
- Use `^x.y.z` constraints pinned to the latest stable at the time of bootstrap

Run:

```bash
flutter pub get
```

### Step 3 — Create the `lib/` folder structure

Match `design_spec.md` → Project Structure exactly:

```
lib/
├── main.dart
├── app.dart
├── core/                ← MUST remain Flutter-free (ADR-16)
│   ├── database/
│   ├── transports/
│   ├── auth/
│   └── settings/
├── features/
│   ├── editor/
│   ├── stream/
│   ├── onboarding/
│   └── settings/
├── ui/                  ← cross-cutting Flutter widgets, theme
└── shared/
    └── models/          ← pure Dart (CLI-safe per ADR-16)
```

Add a `.gitkeep` in each empty directory so they survive the commit.

`core/sync/` and `core/mcp/` are **not** created at bootstrap — they land with their respective plugin axes in v1.1+ and v2.0+ respectively. Creating empty stubs would be premature and conflict with manifesto framing.

### Step 4 — Minimal "hello world" app

Replace the generated `lib/main.dart` and add `lib/app.dart`:

- `main.dart`: standard `void main() { runApp(ProviderScope(child: QuKiNotesApp())); }`
- `app.dart`: `ConsumerWidget` named `QuKiNotesApp` returning a `MaterialApp` with `themeMode: ThemeMode.system` (per ADR-12), a light + dark theme, and a `Scaffold` with the text "QuKi-Notes — Phase 0 scaffold".

This proves Riverpod is wired, theme works, and the app boots. **Do not implement any actual features in this PR** — that's Phase 1.

### Step 5 — `justfile`

Create at repo root with the recipes from `design_spec.md` → Local Development Tasks. At minimum:

```just
default:
    @just --list

android:
    flutter run -d android

windows:
    flutter run -d windows

linux:
    flutter run -d linux

test:
    flutter test

lint:
    flutter analyze
    dart format --output=none --set-exit-if-changed lib/ test/

gen:
    dart run build_runner build --delete-conflicting-outputs

build-android-debug:
    flutter build apk --debug

build-android-release:
    flutter build apk --release

build-windows:
    flutter build windows --release

build-linux:
    flutter build linux --release

docs:
    cd docs && npm run dev
```

### Step 6 — `.github/workflows/`

Create:

**`ci.yml`** — runs on every PR:
- Trigger: `pull_request` to any branch + `push` to `main`
- Runner: `ubuntu-latest`
- Steps: checkout, setup-flutter (use `subosito/flutter-action@v2` pinned), `flutter pub get`, `flutter analyze`, `dart format --output=none --set-exit-if-changed lib/ test/`, `flutter test`

**`build-android.yml`** — triggered on `push` of tags matching `v*`:
- Runner: `ubuntu-latest`
- Outputs: signed APK + AAB → attached to GitHub Release matching the tag
- Signing keystore from GitHub Actions secrets (placeholder vars — see comment in file; Scott populates secrets out-of-band)

**`build-windows.yml`** — same trigger:
- Runner: `windows-latest`
- Output: zipped Windows release build → attached to GitHub Release

**`build-linux.yml`** — same trigger:
- Runner: `ubuntu-latest`
- Output: tarball of the linux release build → attached to GitHub Release. (Final distribution format — AppImage / Flatpak / Snap — deferred to OQ-NEW-3 at Phase 3.)
- Build deps: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`, `libsecret-1-dev` (for `flutter_secure_storage`).

**`build-ios.yml`** — stub:
- Trigger: `workflow_dispatch` **only** (manual). No tag trigger. Leave a top comment explaining it's deferred per `CLAUDE.md`.
- Body: a single placeholder `echo "iOS build deferred"` step

**`docs.yml`** — VitePress deploy:
- Trigger: `push` to `main` with paths filter on `docs/**`
- Runner: `ubuntu-latest`
- Steps: setup Node 20, `npm ci` in `docs/`, `npm run docs:build`, deploy `docs/.vitepress/dist` to GitHub Pages via `actions/deploy-pages`

### Step 7 — release-please

Use the **release-please action** (`googleapis/release-please-action@v4` or current major) via a workflow `release-please.yml`:

- Trigger: `push` to `main`
- Config: `release-type: dart`, `package-name: quki_notes`, `bump-minor-pre-major: true`
- Place workflow at `.github/workflows/release-please.yml`
- If using a separate config file: `release-please-config.json` + `.release-please-manifest.json` at repo root

The action opens/updates a Release PR as conventional commits accumulate.

### Step 8 — VitePress `docs/` scaffold

Minimum to make `docs.yml` succeed:

```
docs/
├── .vitepress/
│   └── config.ts          ← title, base path "/quki-notes/", sidebar with stubs
├── index.md               ← landing page; one paragraph + link to user guide
├── user-guide/
│   └── getting-started.md ← stub: "Coming soon"
├── package.json           ← "scripts": { "dev": "vitepress dev .", "docs:build": "vitepress build .", "docs:preview": "vitepress preview ." } + vitepress devDep
└── .gitignore             ← node_modules, .vitepress/dist, .vitepress/cache
```

`npm install` inside `docs/` to generate the lockfile; commit `package-lock.json`.

### Step 9 — Root meta files

- **`CHANGELOG.md`** — single section: `## Unreleased`. release-please will rewrite this.
- **`README.md`** — replace the flutter-generated one. Contents:
  - One-line description
  - Status: "Phase 0 scaffold — Phase 1 in progress"
  - Quick start: link to `notes/dev/dev_env_setup.md` and `CLAUDE.md`
  - Links to `notes/dev/design_spec.md`, `notes/dev/decisions.md`, `notes/dev/open_questions.md`
  - License: **MIT**. Also add a top-level `LICENSE` file with the standard MIT text, `Copyright (c) 2026 Scott Kirvan`.
- **`.vscode/settings.json`** — the workspace settings block from `dev_env_setup.md` §4
- **`.gitignore`** — `flutter create` generates one; append: `.vscode/launch.json` (user-local), `*.iml` (IntelliJ noise), `coverage/`, `**/.DS_Store`, `docs/.vitepress/cache/`, `docs/.vitepress/dist/`, `docs/node_modules/`

### Step 10 — Local verification (must all pass before commit)

```bash
just lint               # flutter analyze + dart format check
just test               # flutter test (the generated default widget test)
just android            # Pixel boots the scaffold; shows "QuKi-Notes — Phase 0 scaffold"
just windows            # Windows desktop window opens with the same text
# just linux            # only if Scott has a Linux env handy; otherwise rely on CI
cd docs && npm run docs:build && cd ..   # VitePress builds clean
```

If any of these fail, **stop and fix** before opening the PR. Do not push a red bootstrap.

### Step 11 — Commit + push + PR

```bash
git add .
git commit -m "chore: bootstrap project scaffold"
git push -u origin chore/phase0-bootstrap-scaffold
gh pr create --title "chore: bootstrap project scaffold" --body-file <(cat <<'EOF'
[fill using pr_template.md]
EOF
)
```

Use `pr_template.md` for the PR body. Test instructions = the §10 verification list.

---

## Acceptance criteria

- [ ] CI workflow (`ci.yml`) runs and is **green** on the PR
- [ ] App boots on Pixel 6 Pro showing the scaffold text
- [ ] App boots on Windows desktop showing the same text
- [ ] `lib/` folder tree matches `design_spec.md` → Project Structure (no `core/sync/`, no `core/mcp/`)
- [ ] `pubspec.yaml` declares every Phase 1 runtime + dev dependency from `dependencies.md`
- [ ] `justfile` has all recipes listed in Step 5 (including `linux`)
- [ ] All six build/CI workflows exist (`ci`, `build-android`, `build-windows`, `build-linux`, `build-ios` stub, `docs`); `build-ios.yml` has only a `workflow_dispatch` trigger
- [ ] release-please workflow exists and is configured for `dart`
- [ ] VitePress builds clean
- [ ] No features implemented — this is structure only

---

## What this PR does NOT do (deferred to Phase 1+)

- No drift schema (Phase 1, separate PR)
- No editor, no stream (Phase 1)
- No transports (Phase 2)
- No sync, no OAuth (Phase 4+)
- No MCP (v2.0+)
- No real UI beyond a placeholder Scaffold
- No real tests beyond the generated default widget test

If any of these creep in during bootstrap: stop and split.

---

## After merge

1. Scott squash-merges. The conventional commit `chore: bootstrap project scaffold` lands on `main`.
2. release-please opens its first Release PR (will sit dormant until `feat:` commits accumulate).
3. Phase 1 begins in the next session — start with the **drift schema v1** PR per `design_spec.md` → Phase 1 task list (`qukis` + `images` tables, no sync columns yet).
4. This bootstrap doc is now reference-only. Do not edit it; if the scaffold needs changes, open a follow-up PR with its own commit message.
