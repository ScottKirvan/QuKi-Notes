# Google Play Signing Setup

Audience: **Scott**. One-time setup to get a real release keystore, upload to Google Play, and wire the secrets into GitHub Actions so every tagged release signs correctly.

This doc is in two parts:
1. **Keystore + GitHub secrets** — unblocks CI signing immediately (needed before the next release)
2. **Google Play first upload** — first-time submission walkthrough

---

## Part 1 — Keystore and GitHub Actions secrets

### Why you need this

Every APK released so far has been signed with a randomly-generated debug key from whichever GitHub Actions runner built it. Each runner gets a fresh key, so v0.8.1 and v0.9.1 have different certs — Android rejects the upgrade. The fix in `build.gradle.kts` (PR pending from DevOps session) reads a real keystore from CI secrets, but those secrets don't exist yet.

> **Important**: Once you sign a release APK with your real keystore, you are permanently committed to that keystore for sideloaded installs. Losing it means losing the ability to push upgrades to users who installed outside the Play Store. Back it up in at minimum two places (e.g., a password manager and an encrypted cloud backup).

---

### Step 1 — Generate the keystore

Run this on your Windows dev box (requires Java — the Android SDK includes it):

```powershell
# Use the keytool that ships with the Android SDK
# Adjust the path if your SDK is installed elsewhere
$KEYTOOL = "$env:LOCALAPPDATA\Android\Sdk\jdk\bin\keytool.exe"

& $KEYTOOL -genkeypair `
  -v `
  -keystore quki-notes-release.jks `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias quki-notes
```

You will be prompted for:
- A **keystore password** — pick something strong; save it in your password manager
- Your name / org / city / country — these appear in the cert; use whatever you like (they are not shown to users)
- A **key password** — can be the same as the keystore password; save it too

This creates `quki-notes-release.jks` in the current directory.

**Back this file up immediately** — copy it to your password manager's file vault or an encrypted backup location. If you lose it, you cannot update sideloaded installs.

---

### Step 2 — Encode the keystore for GitHub secrets

GitHub secrets are strings, so you need to base64-encode the binary `.jks` file:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("quki-notes-release.jks")) | Set-Clipboard
```

This puts the base64 string on your clipboard.

---

### Step 3 — Add secrets to the GitHub repository

Go to: **GitHub → ScottKirvan/QuKi-Notes → Settings → Secrets and variables → Actions → New repository secret**

Add all four:

| Secret name | Value |
|---|---|
| `KEYSTORE_BASE64` | The base64 string you just copied |
| `STORE_PASSWORD` | The keystore password you chose |
| `KEY_ALIAS` | `quki-notes` (whatever alias you used in Step 1) |
| `KEY_PASSWORD` | The key password you chose |

---

### Step 4 — Merge the DevOps fix PR

The DevOps session has a pending fix that wires `build.gradle.kts` to read these secrets. Merge that PR after the secrets are populated. The next tagged release will sign with your real keystore.

---

### Step 5 — Verify the first properly-signed release

After the next release tag fires the build workflow:

1. Open the GitHub Actions run for `build-android.yml`
2. Check the "Decode keystore" step — it should complete silently
3. Download the APK from the release
4. Install it over your existing install — if upgrade succeeds without an "App not installed" error, signing is working correctly

---

### Handling existing users (sideloaded installs)

Anyone who installed v0.8.1 or v0.9.1 from GitHub Releases will see the cert mismatch and need to **uninstall first, then reinstall**. They will lose locally stored QuKis unless they back them up first (there is no export feature yet — this is a known limitation pre-beta).

For beta testers you've already sent builds to: warn them ahead of time. A clean install is required for the transition to properly-signed builds.

---

## Part 2 — Google Play first upload

### Before you start

You need:
- A **Google Play Developer account** ($25 one-time fee) — https://play.google.com/console/signup
- A signed **AAB** (Android App Bundle) — the `build-android.yml` CI workflow produces both an APK and an AAB; use the AAB for Play Store submission
- App metadata: icon, screenshots, short description, full description

---

### Step 1 — Create the app in Play Console

1. Sign in to [Google Play Console](https://play.google.com/console)
2. Click **Create app**
3. Fill in:
   - **App name**: `QuKi-Notes`
   - **Default language**: English (United States)
   - **App or game**: App
   - **Free or paid**: Free
4. Accept the declarations and click **Create app**

---

### Step 2 — Set up Google Play App Signing (strongly recommended)

Google Play App Signing means Google re-signs your APK/AAB with a Google-managed key before delivering it to users. You upload with your own keystore (the "upload key"), and Google's key is what devices verify. This means:

- If your upload keystore is lost or compromised, Google can reset it
- You keep the ability to push updates even if your upload key is lost
- The downside: sideloaded APKs and Play Store installs have **different signing certs** — a user who sideloaded cannot upgrade via Play Store (and vice versa) without uninstalling first

To opt in:
1. In Play Console → your app → **Setup → App signing**
2. Choose **"Use Google-managed key"** (recommended for a new app)
3. Google generates and manages the app signing key; your `quki-notes-release.jks` becomes the upload key only

> If you never plan to distribute APKs outside the Play Store, this is the right choice. If sideloaded installs and Play Store installs need to share upgrade paths, you can opt out of Play App Signing and manage your key yourself — but you lose the key-reset safety net.

---

### Step 3 — Complete the store listing

Under **Grow → Store presence → Main store listing**:

- **App icon**: 512×512 PNG, no alpha
- **Feature graphic**: 1024×500 PNG or JPEG (shown at top of store listing)
- **Screenshots**: at least 2 phone screenshots (1080×1920 or similar)
- **Short description**: max 80 characters — e.g., *"Capture a thought. Send it somewhere. Nothing to organize."*
- **Full description**: max 4000 characters — you can adapt the README intro

Under **App content** you will also need to complete:
- Privacy policy URL (required — even for apps with no data collection; host a simple one)
- Content rating questionnaire
- Data safety form (QuKi-Notes collects no data; this form will be short)

---

### Step 4 — Create a release

1. Go to **Testing → Internal testing** (start here before open/closed beta or production)
2. Click **Create new release**
3. Upload the `.aab` file from your GitHub Release artifacts
4. Play Console will confirm the signing cert — if Google Play App Signing is enabled, it will show both the upload cert and the delivery cert
5. Add release notes (plain text, not markdown)
6. Click **Save** then **Review release**

---

### Step 5 — Add internal testers

Under **Internal testing → Testers**:
- Add tester Google accounts (up to 100)
- Or create an opt-in link to share

Internal test builds are available within minutes, skip most review, and are not publicly listed. This is the right track for beta testers you invite directly.

---

### Step 6 — Promote to production when ready

Once internal testing is stable:
1. Open Testing → Internal testing → your release → **Promote release → Production**
2. Set rollout percentage (start at 10–20% for a staged rollout)
3. Submit for review — first submissions typically take 1–3 days

---

## Appendix — Keystore backup checklist

- [ ] `quki-notes-release.jks` saved in password manager file vault
- [ ] `quki-notes-release.jks` backed up to encrypted cloud storage (separate from password manager)
- [ ] Keystore password and key password saved in password manager
- [ ] Key alias (`quki-notes`) noted alongside the passwords
- [ ] GitHub Actions secrets populated (all four)
- [ ] DevOps signing fix PR merged

---

*Last updated: 2026-06-05*
