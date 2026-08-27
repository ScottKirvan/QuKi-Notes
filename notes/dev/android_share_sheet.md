# Android Share Sheet — Bypass share_plus's Result-Tracking Chooser (Design Spec)

**Status**: proposed design from a research pass — not yet an ADR, not yet briefed to Implementation. Root cause is source-confirmed; the fix itself is not yet device-verified.

This is not an ADR yet because the fix is unverified on-device. Once implemented and confirmed, this should collapse into a short ADR entry in `decisions.md` per the usual pattern, with this file kept (or trimmed) as the supporting detail doc — matching how `selection.md`/`block_indentation.md` relate to their ADRs.

---

## 1. Problem

Sharing a QuKi out via the Share Sheet transport to Bluesky does not work: Bluesky's app simply opens (to its normal feed), rather than opening compose pre-filled with the QuKi's content.

This was initially assumed to be a Bluesky-side bug (a known upstream issue, [bluesky-social/social-app#8513](https://github.com/bluesky-social/social-app/issues/8513), describes Android share not working unless Bluesky is already backgrounded). That assumption was **disproven by a direct A/B test on the same device**: Notepad Free, a minimal plain-text app, shares to Bluesky successfully using the system share sheet. QuKi-Notes does not. Since the receiving app and device are identical in both cases, the difference has to be in how the two *sending* apps build and launch their share intent.

Three previously filed issues sit in the same territory — #337 (Bluesky, this issue), #338 ("Save"/Google icon errors and asks for a link), #339 (Google Voice, unclear behavior) — all filed as "root cause not yet investigated." Only #337 has been root-caused here. #338/#339 remain open; see §6.

---

## 2. Root cause (confirmed by reading `share_plus` v10.0.0's Android source)

`ShareSheetTransport.transport()` (`lib/core/transports/plugins/share_sheet_transport.dart`) calls `Share.share(markdown)`. On Android, `share_plus`'s `Share.kt` does **not** use the plain, single-purpose chooser call a minimal native app would use. It unconditionally (on any SDK ≥ Lollipop MR1, i.e. effectively always) builds a **result-tracking** chooser:

```kotlin
// packages/share_plus/share_plus/android/.../Share.kt
val chooserIntent = Intent.createChooser(
    shareIntent,
    title,
    PendingIntent.getBroadcast(
        context, 0,
        Intent(context, SharePlusPendingIntent::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or immutabilityIntentFlags
    ).intentSender
)
...
activity!!.startActivityForResult(chooserIntent, ShareSuccessManager.ACTIVITY_CODE)
```

This is the 3-argument `Intent.createChooser(Intent, CharSequence, IntentSender)` overload (API 22+), paired with `startActivityForResult` rather than `startActivity`. Its entire purpose is letting the plugin report back *which app the user picked* (`ShareResultStatus`) via a `BroadcastReceiver` (`SharePlusPendingIntent`) that Android invokes once a target is chosen.

**QuKi-Notes never uses that result.** `ShareSheetTransport.transport()` ignores whatever `Share.share()` returns and unconditionally returns `TransportResult(success: true, message: 'Shared.')` — a deliberate workaround already in place for #92 (share_plus firing a false "dismissed" status even on success). In other words: the one feature this mechanism exists to provide is actively discarded by this app, and the mechanism itself has *already* been caught misbehaving once (#92) before this investigation.

**Why it plausibly breaks Bluesky specifically**: `startActivityForResult` ties the launched chooser into the calling activity's own task semantics. QuKi-Notes' `MainActivity` carries non-default task configuration — `android:launchMode="singleTask"` and `android:taskAffinity=""` (`android/app/src/main/AndroidManifest.xml`, added for the share-*in* fix, #188/#259). Bluesky's Android share handling is implemented via an Expo module that inspects the incoming intent itself (not a plain declarative `<intent-filter>` Activity) to decide whether to route to its compose screen — exactly the kind of custom intent-inspection logic most likely to be sensitive to being launched via `startActivityForResult` from a task with unusual affinity, versus a plain `startActivity` call landing on it the ordinary way (which is what Notepad Free almost certainly does).

This is a plausible, source-grounded mechanism, not a confirmed root cause down to the exact line — confirming the precise failure point would need an on-device intent trace (`adb logcat` / `am` monitor around the moment the chooser resolves). It is the strongest, most specific lead found, and directly explains the "works elsewhere, fails only here" pattern the A/B test showed.

---

## 3. Design goals

- Restore reliable `ACTION_SEND` delivery on Android — target apps should receive the share the same way they would from any ordinary native sender.
- Don't regress Windows or Linux. `ShareSheetTransport` is registered with **no platform guard** (`registry_provider.dart:12`) — `share_plus` is currently the only Share Sheet implementation on all three platforms, not just Android.
- Minimal new maintenance surface. Fix the mechanism that's actually implicated (Android's result-tracking chooser call) rather than taking on a full cross-platform replacement of a working, maintained dependency.

---

## 4. Proposed solution

Add a small Android-only platform channel that performs the plain, no-result chooser call:

```kotlin
val intent = Intent(Intent.ACTION_SEND).apply {
    type = "text/plain"
    putExtra(Intent.EXTRA_TEXT, text)
}
activity.startActivity(Intent.createChooser(intent, null))
```

— the 2-argument `createChooser` overload, launched via plain `startActivity`, with no `PendingIntent`, no `BroadcastReceiver`, no `startActivityForResult`. This is the same shape a minimal native app (Notepad Free) uses.

Wire `ShareSheetTransport` to call this channel when `Platform.isAndroid`, and keep calling `share_plus`'s `Share.share()` everywhere else (Windows, Linux) where this failure mode has no evidence of applying and a bespoke native implementation would be new maintenance surface with no known problem to fix.

**Sketch of the pieces** (not a final API — for whoever briefs/implements this):

- New Kotlin file under `android/app/src/main/kotlin/...` — a `MethodChannel` handler exposing one method (e.g. `shareText`), registered in `MainActivity`.
- A small Dart wrapper (e.g. `AndroidShareChannel`) invoking that method.
- `ShareSheetTransport.transport()` branches on `Platform.isAndroid`: the new channel on Android, `Share.share(markdown)` unchanged elsewhere.
- No result handling needed on either path — `TransportResult(success: true)` is returned unconditionally today and that doesn't need to change; nothing currently surfaces a real failure/cancel state to the user regardless of platform.

---

## 5. Scope

**In scope**:
- New Android platform channel (Kotlin) + `MainActivity` registration.
- `lib/core/transports/plugins/share_sheet_transport.dart` — platform branch.

**Explicitly out of scope**:
- Replacing `share_plus` on Windows/Linux — no evidence of the same bug there; the implicated mechanism is Android-specific in `share_plus`'s own source.
- Image/file attachment sharing — `ShareSheetTransport` doesn't send images today (`editor_screen.dart` passes `images: const []`) and QuKi-Notes has no working path to attach a real image to a note yet (#247 blocked, #344 rendering never worked) — unrelated to this fix.
- `share_handler.dart` (share-**in**) — that path consumes the Android manifest's own `<intent-filter>` declarations directly; it doesn't go through `share_plus` and isn't affected by this change either way.
- Fixing #338 ("Save") or #339 (Google Voice) — see §6, not expected to be touched by this change.

---

## 6. What this does *not* fix

#338 and #339 remain open and are not expected to be resolved by this change. Android's share intent has no dedicated "URL" or "phone number" field — everything arrives at the receiver via the same `EXTRA_TEXT`, regardless of how the sender constructed or launched the chooser. If "Save" only accepts URL-shaped text, or Google Voice only expects phone-number-shaped text, that's the receiving app's own content-parsing decision downstream of intent delivery — switching *how* the intent is launched (this fix) doesn't change *what's inside* it. These two should stay open, independently investigated, rather than assumed fixed by this change.

---

## 7. Verification plan

This bug was found by real on-device comparison, not code review — code review of the original `_onTransport()`/`ShareSheetTransport` call site alone would not have surfaced it (it looks completely unremarkable; the problem is one layer down, inside the dependency). The fix needs the same standard:

1. On-device A/B: before/after this change, share a QuKi to Bluesky and confirm compose actually opens pre-filled — not just "the app opens."
2. Regression-check at least one target that already worked (e.g. Messages, Gmail, or the system Notes app) to confirm the plain chooser doesn't break anything currently functioning.
3. Confirm Windows/Linux Share Sheet transport is untouched (still routes through `share_plus`, no behavior change expected there).

---

## 8. Rejected alternatives

- **Full removal of `share_plus` across all platforms.** Rejected — would require hand-building the share sheet for Windows and Linux too, a real ongoing maintenance cost, with no evidence those platforms share this failure mode.
- **Forking/patching `share_plus` to drop the result callback unconditionally.** Rejected — ties QuKi-Notes to re-patching a vendored copy on every upstream version bump; a small, owned platform channel is simpler to reason about and maintain long-term.
- **Waiting on upstream `share_plus` for an opt-out flag.** No such flag exists today — `MethodCallHandler.kt` computes `isWithResult` unconditionally from SDK version; it isn't Dart-configurable. Not in QuKi-Notes' control, and no upstream issue/PR for it was found during this research.

---

## 9. Open questions

- Confirm `activity.startActivity()` (not `applicationContext`) is reliably non-null at the point Send fires. It should be — Send is only reachable from a running foreground `Activity` — but this should be a real guard/assertion during implementation, not an assumption carried over from this spec.
- Worth a quick incidental check during on-device verification (§7) whether this change happens to affect #339's "unclear behavior" — not expected to (see §6), but cheap to note either way while already testing on-device.
