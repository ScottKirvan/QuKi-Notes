# Development Environment Setup

Audience: **Scott**. One-time install for the dev box. Sonnet does not run any of this — it's the foundation Sonnet's PRs target.

Test targets:
- **Pixel 6 Pro** (Android) — primary
- **Windows 11** desktop build — local
- **Linux desktop** — third active target (Phase 3)

---

**Jump to platform:**
- [Windows 11 setup (sections 1–7)](#1-pre-flight-check)
- [Linux setup (section 8)](#8-linux-setup)

---

## 1. Pre-flight check

- Windows 11 Pro/Home (you're on Pro N — fine)
- ~30 GB free disk for Flutter + Android SDK + emulator images
- Admin rights (some installers require it)
- Stable internet (initial install pulls multi-GB downloads)

---

## 2. Install toolchain

### Git, GitHub CLI, just

If not already present:

```powershell
winget install --id Git.Git
winget install --id GitHub.cli
winget install --id Casey.Just
```

Then:

```powershell
gh auth login          # log in once, browser flow
git config --global user.name  "Scott Kirvan"
git config --global user.email "<your-github-email>"
```

### Flutter SDK

Recommended: install Flutter into a stable, non-system path you control.

```powershell
# pick a location you'll remember; avoid C:\Program Files (permission issues)
cd C:\
git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
```

Add `C:\src\flutter\bin` to your user `PATH` (Settings → System → About → Advanced system settings → Environment Variables → Path → Edit → New).

Verify:

```powershell
flutter --version          # should print something like 3.x.x stable
flutter precache           # downloads platform-specific tooling
```

To upgrade later: `cd C:\src\flutter && git pull`.

### Android Studio + SDK components

You already have Android Studio installed. Open **Settings → Languages & Frameworks → Android SDK** (or **SDK Manager** from the welcome screen):

**SDK Platforms tab** — install:
- Android **API 35** (Android 15) — current target for Pixel 6 Pro
- Android **API 34** (Android 14) — broader compatibility

**SDK Tools tab** — install (check "Show Package Details" to pin specific versions):
- Android SDK Build-Tools (latest)
- Android SDK Command-line Tools (latest)
- Android SDK Platform-Tools
- Android Emulator
- Android Emulator hypervisor driver (for AVD performance — Intel/AMD agnostic on modern Windows)
- Google USB Driver

Accept licenses from the command line:

```powershell
flutter doctor --android-licenses
# press 'y' through each prompt
```

### Visual Studio Build Tools (required for Windows desktop builds)

Flutter Windows targets need MSVC. Install **Visual Studio 2022 Build Tools** (the standalone variant — full Visual Studio not required):

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools
```

After install, run **Visual Studio Installer**, select the Build Tools entry → **Modify** → tick **Desktop development with C++**. Apply.

### Enable Windows desktop in Flutter

```powershell
flutter config --enable-windows-desktop
```

### Verify everything

```powershell
flutter doctor -v
```

You want every section green except possibly the "Connected device" line until you plug in your phone. If anything is red, fix it before continuing — `flutter doctor` is the source of truth.

---

## 3. Pixel 6 Pro setup

### Enable Developer Options

On the phone:
1. **Settings → About phone → Build number** — tap 7 times.
2. **Settings → System → Developer options** — should now exist.

### Enable debugging

Inside Developer options:
- **USB debugging** — ON
- **Wireless debugging** — ON (Android 11+; useful so you can leave the cable out)

### USB connect (first time)

1. Plug Pixel 6 Pro into the dev box via USB-C.
2. Phone prompts "Allow USB debugging?" — tick "Always allow from this computer", tap Allow.
3. Verify:

   ```powershell
   flutter devices
   ```

   You should see the Pixel listed.

### Wireless connect (after first USB pair)

In Developer options → **Wireless debugging → Pair device with pairing code**. Note the IP:port + 6-digit code.

```powershell
adb pair <ip>:<port>     # enter the 6-digit code
adb connect <ip>:<port>  # use the OTHER port shown on the main Wireless debugging screen
flutter devices
```

Once paired, future sessions just need the `adb connect` (or it auto-reconnects when on the same Wi-Fi).

### Emulator (backup)

In Android Studio: **Tools → Device Manager → Create Virtual Device → Pixel 6 Pro → API 35 system image**. Useful when you can't have the physical phone handy.

---

## 4. VSCode setup

### Extensions

Install (from VSCode extension marketplace):

- **Dart-Code.dart-code** — Dart language support
- **Dart-Code.flutter** — Flutter debug/run integration
- **skellock.just** — `justfile` syntax highlighting
- **Anthropic.claude-code** — Claude Code (you already have it)

### Recommended workspace settings

Once the project is bootstrapped (first Sonnet PR), commit `.vscode/settings.json`:

```json
{
  "dart.lineLength": 100,
  "editor.formatOnSave": true,
  "editor.rulers": [100],
  "files.eol": "\n",
  "files.insertFinalNewline": true,
  "files.trimTrailingWhitespace": true,
  "[markdown]": {
    "files.trimTrailingWhitespace": false
  }
}
```

The bootstrap PR adds this — you don't need to create it manually.

### Claude Code login

If not already authed: open Claude Code panel in VSCode → run `/login` → browser flow.

---

## 5. Daily development workflow

### Starting a session

```powershell
cd <path-to-quki-notes-repo>
git pull
gh pr list                  # see what's open
gh run list -L 3            # confirm main CI is green
```

Open VSCode in the repo. Open Claude Code panel.

### Running the app

With Pixel connected:

```powershell
just android
# or directly: flutter run -d <device-id>
```

Hot keys inside `flutter run`:
- `r` — hot reload (preserve state)
- `R` — hot restart (rebuild state)
- `q` — quit

Windows desktop:

```powershell
just windows
```

### Reviewing a Sonnet PR

```powershell
gh pr checkout <pr-number>
just lint
just test
just android                # smoke test on device
# eyeball the diff in VSCode's Source Control panel or `gh pr diff`
```

If satisfied:

```powershell
gh pr merge <pr-number> --rebase --delete-branch
```

Each commit lands individually on `main` — release-please reads every commit message to decide version bumps. All commits in a PR must follow conventional commit format.

### Reviewing the release-please PR

When phase work accumulates and release-please opens a "Release PR":

```powershell
gh pr view <release-pr-number>    # eyeball the version bump + CHANGELOG
gh pr merge <release-pr-number> --rebase
```

Merging triggers tag creation → build workflows fire → APK, Windows build, and Linux tarball uploaded to the GitHub Release.

---

## 6. Sanity check (run once after setup)

```powershell
flutter doctor -v            # everything green
flutter devices              # Pixel + Windows listed
flutter create test_sanity   # creates a throwaway project
cd test_sanity
flutter run -d windows       # boots a "Flutter Demo" window
flutter run -d <pixel-id>    # boots the demo on the phone
cd ..
rmdir /s /q test_sanity      # clean up
```

If all four pass, the environment is ready and the first Sonnet bootstrap PR (`notes/dev/bootstrap.md`) can run.

After cloning (or re-cloning), activate the pre-commit format hook:

```powershell
just setup
```

This wires `.githooks/pre-commit` so `dart format` runs automatically before every commit. The hook is a no-op if `dart` is not on the PATH.

---

## 7. Things that will bite you (preemptive)

- **Windows path length**: enable long paths if `flutter create` complains. `git config --system core.longpaths true` + the Windows registry tweak.
- **Antivirus on the Flutter directory**: Defender real-time scan can make `flutter pub get` glacial. Add `C:\src\flutter` to exclusions.
- **Android emulator vs Hyper-V**: if you also run WSL2 or Docker Desktop, the emulator may need WHPX rather than HAXM. Modern installs default correctly; only revisit if AVD won't start.
- **Hot reload doesn't pick up `pubspec.yaml` changes**: stop with `q`, re-run `flutter run`. Same for native-side changes (Android manifest, Windows runner).
- **Wireless debugging drops on Wi-Fi network change**: re-run `adb connect <ip>:<port>` (port may have rotated; check the Wireless debugging screen).
- **Drift codegen failures after schema edits**: always run `just gen` after touching anything in `lib/core/database/`.
- **Kotlin cross-drive incremental compilation crash** (Pub cache on `C:` + project on `E:` or similar): the Kotlin Gradle Plugin's incremental compiler chokes on cross-volume paths and throws `IllegalArgumentException` during Android builds. The Phase 0 scaffold ships `android/gradle.properties` with `kotlin.incremental=false` to work around it. If you ever move the project + pub cache onto a single drive, you can flip incremental back on for faster Android builds.

---

## 8. Linux setup

These instructions assume a modern Debian/Ubuntu-based distro (Ubuntu 22.04 LTS, 24.04 LTS, or Pop!_OS). Adjust package names for Fedora/Arch as needed.

### 8.1 Pre-flight check

- ~20 GB free disk (Flutter + build tools; no Android SDK needed if you only build Linux desktop)
- `sudo` access
- Stable internet

### 8.2 Install toolchain

#### System dependencies

Flutter Linux desktop requires several dev libraries. Install them all up front:

```bash
sudo apt-get update
sudo apt-get install -y \
  curl git unzip xz-utils zip \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libglib2.0-dev libgdk-pixbuf2.0-dev \
  libpango1.0-dev libatk1.0-dev \
  libsecret-1-dev libjsoncpp-dev
```

`libsecret-1-dev` is needed for `flutter_secure_storage`. If you skip it the app builds but crashes at runtime on any secret read/write.

#### just

```bash
# Via cargo (recommended — gets the latest version):
cargo install just
# Or via package manager (may be older):
sudo apt-get install -y just
```

If cargo isn't installed: `sudo apt-get install -y cargo` first, or use the [prebuilt binary](https://github.com/casey/just/releases) from the releases page.

#### GitHub CLI

```bash
(type -p wget >/dev/null || (sudo apt-get update && sudo apt-get install wget -y)) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
     | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt-get update && sudo apt-get install gh -y
gh auth login
```

#### Flutter SDK

```bash
cd ~
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
```

Add to `~/.bashrc` (or `~/.zshrc`):

```bash
export PATH="$HOME/flutter/bin:$PATH"
```

Then reload and verify:

```bash
source ~/.bashrc
flutter --version
flutter precache
```

To upgrade later: `cd ~/flutter && git pull`.

#### Enable Linux desktop

```bash
flutter config --enable-linux-desktop
```

#### git config (if not already set globally)

```bash
git config --global user.name  "Scott Kirvan"
git config --global user.email "<your-github-email>"
```

### 8.3 Verify

```bash
flutter doctor -v
```

The **Linux toolchain** section should be green. The Android / Xcode sections will be red if you haven't installed Android Studio — that's fine if this box is Linux-desktop-only. Fix anything under Linux before continuing.

### 8.4 Clone the repo and activate hooks

```bash
git clone https://github.com/ScottKirvan/QuKi-Notes.git
cd QuKi-Notes
flutter pub get
just setup          # activates the pre-commit dart format hook
```

### 8.5 Daily workflow

```bash
cd ~/QuKi-Notes
git pull
gh pr list
gh run list -L 3    # confirm main CI is green
```

Run the app:

```bash
just linux
# or directly: flutter run -d linux
```

Hot keys inside `flutter run`: `r` hot reload, `R` hot restart, `q` quit.

Review a PR:

```bash
gh pr checkout <pr-number>
just lint
just test
just linux          # smoke test
gh pr merge <pr-number> --rebase --delete-branch
```

### 8.6 Sanity check (run once after setup)

```bash
flutter doctor -v
flutter create /tmp/test_sanity
cd /tmp/test_sanity
flutter run -d linux
cd ~
rm -rf /tmp/test_sanity
```

A "Flutter Demo" counter app should open. Close it, then you're good.

### 8.7 Things that will bite you (Linux)

- **Missing `libsecret`**: `flutter_secure_storage` links against `libsecret-1`. If not installed, the app builds but crashes on first secret access. Install `libsecret-1-dev` at setup time (included in the list above).
- **`ninja` not found**: CMake uses Ninja as the build backend. `sudo apt-get install ninja-build` if `flutter run -d linux` errors with "ninja: command not found".
- **`pkg-config` can't find GTK**: Usually means `libgtk-3-dev` isn't installed, or the `.pc` file paths aren't on `PKG_CONFIG_PATH`. Re-run the apt install block above.
- **Snap-installed Flutter**: Do not install Flutter via snap — it runs in a sandboxed environment that breaks `flutter pub get` and native builds. Use the git clone method above.
- **Font rendering differs from Windows**: Expected. Linux desktop uses system fonts; the app may look slightly different. This is cosmetic and not a bug.
- **`flutter doctor` reports "Unable to find bundled Java"**: Run `flutter config --android-studio-dir <path>` pointing at your Android Studio install, or ignore it if this box doesn't do Android builds.
- **Drift codegen failures after schema edits**: same as Windows — always run `just gen` after touching anything in `lib/core/database/`.
