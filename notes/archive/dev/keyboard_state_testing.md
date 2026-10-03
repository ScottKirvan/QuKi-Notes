# Keyboard-state testing procedure (mobile only)

**Purpose**: a set of open issues (#340, #263, #235, #265, #328, #177, #239, #234, plus an unfiled cursor-follows-scroll concern) may share the same root cause — the app's tracking of real keyboard visibility going stale or wrong. This procedure walks through each scenario in isolation so actual behavior can be recorded neutrally, without assuming which issues are duplicates, which are already fixed, and which are genuinely distinct. **Do not trust any doc claiming something here already shipped/fixed** — this project has repeatedly had "Complete"-labeled work that didn't actually work when retested. Record what you actually see, not what's expected.

**Scope**: Android/mobile only, per request. Not testing desktop.

**How to use this doc**: for each scenario, follow the steps, then fill in the "Actual behavior" line with what you observed — keyboard shown/hidden, toolbar visible/hidden, cursor visible/hidden, and anything else that seems off. Screenshots welcome where useful (as they were for the earlier black-bar finding). No need to diagnose *why* — just record *what happened*.

---

## Group A — Cold launch and basic mode transitions

### A1. Cold launch → existing QuKi
1. Fully close the app (swipe away from recents, not just background).
2. Relaunch it.
3. Tap into an existing QuKi from the list (or if it opens directly to one, that's the note being tested).

**Expected per shipped design**: opens in reading mode — no keyboard, no formatting toolbar, no visible cursor.

**Relates to**: #239 (origin of this design), #263 (residual visibility after this kind of load)

**Actual behavior**:

---

### A2. Cold launch → new/blank QuKi
1. Fully close the app.
2. Relaunch it, landing on a genuinely new/blank note (or tap + for a new one if it doesn't land there directly).

**Expected**: per the recent removal of the non-functional auto-focus code (PR #346), the keyboard is **not** expected to auto-open here anymore — this was a deliberate removal, not a regression, pending the future splash-screen work (#342). Record what actually happens anyway, since "not expected to work" isn't the same as "confirmed not to happen."

**Relates to**: #239, historical #72

**Actual behavior**:

---

### A3. Dismiss keyboard manually (T-button or back/away)
1. From a note in edit mode (keyboard visible), dismiss the keyboard — try both the T-button (if that's how it's dismissed) and tapping outside the text area / back gesture, as separate sub-tests if they differ.
2. Observe immediately after dismissal, and again a few seconds later.

**Expected**: transitions cleanly to reading mode — toolbar hides, cursor hides, keyboard fully gone.

**Relates to**: #235, #263

**Actual behavior (T-button)**:

**Actual behavior (tap-away / back)**:

---

### A4. Tap into note body while in reading mode
1. Starting from a note in reading mode (per A1), tap directly into the body text.

**Expected**: switches to edit mode — keyboard opens, cursor appears at the tapped location, toolbar appears.

**Relates to**: #239, #328

**Actual behavior**:

---

## Group B — Interactions that should stay in reading mode

### B1. Long-press/double-tap to select text while in reading mode
1. Starting from a note in reading mode, long-press a word (or double-tap it).
2. Watch closely for whether the keyboard flashes open at all, even briefly, before or during the selection appearing.

**Expected** (per the recently-merged PR #350 fix): selection appears, **no keyboard opens at any point**, handles/toolbar behave per whatever's currently implemented.

**Relates to**: #328, #340 — this is a direct reverification of a fix that was already device-tested once; worth confirming it's still holding.

**Actual behavior**:

---

### B2. Tap a checkbox while in reading mode
1. Starting from a note in reading mode containing at least one checkbox (nested and non-nested if you have both handy), tap a checkbox.

**Expected** (per PR #350/#358): toggles the checkbox, stays in reading mode, no keyboard.

**Relates to**: #340 (adjacent — confirms the checkbox fix effort didn't regress)

**Actual behavior (non-nested)**:

**Actual behavior (nested)**:

---

## Group C — Specific known triggers

### C1. Delete a QuKi from the list, return to editor
1. From the QuKis list screen, swipe-delete a QuKi (or however delete is triggered).
2. Observe the editor screen immediately after.

**Expected**: no keyboard should pop up as a side effect of the deletion/navigation.

**Relates to**: #265

**Actual behavior**:

---

### C2. Formatting toolbar visibility on a freshly-opened, unfocused note
1. Open an existing note (lands in reading mode per A1) and, without tapping anything, just look.

**Expected**: FormattingToolbar is not visible at all.

**Relates to**: #235

**Actual behavior**:

---

### C3. Toolbar obscuring the last line
1. Open (or create) a note with enough lines to fill the screen while in edit mode (toolbar visible).
2. Scroll to the very last line and check whether it's fully visible above the toolbar, or partially/fully hidden behind it.

**Expected**: the last line should be fully scrollable into view, not stuck behind the toolbar.

**Relates to**: #234

**Actual behavior**:

---

### C4. Cursor stays visible while typing near the bottom of the viewport
1. In edit mode, type continuously (or navigate with arrow keys / Enter) until the cursor would reach the bottom portion of the visible screen — near where the toolbar or keyboard begins.

**Expected**: the editor auto-scrolls to keep the cursor visible, never letting it go behind the toolbar/keyboard or off-screen.

**Relates to**: not yet filed — this is the "cursor-follows-scroll" concern, plausibly tied to the same `viewInsets`/viewport math as #340.

**Actual behavior**:

---

## Group D — Stress / cross-screen scenarios

### D1. Rapid dismiss/reopen cycles
1. In edit mode, dismiss the keyboard, tap back in to reopen it, dismiss again — repeat this 5-6 times somewhat quickly.
2. Watch for any desync: toolbar showing/hiding at the wrong times, cursor visible when it shouldn't be (or vice versa), anything visually "stuck" between states.

**Expected**: every cycle transitions cleanly, no drift or stuck states.

**Relates to**: #340 (general reliability), #177

**Actual behavior**:

---

### D2. Navigate to QuKis list while keyboard is open, then back
1. In the editor with the keyboard open (edit mode), tap the QuKis list icon to navigate away.
2. On the QuKis list screen, check specifically for a black bar at the bottom (the keyboard-shaped gap found previously — see #340's comment history for a reference screenshot of this).
3. Tap back into the editor (any note) and check its state.

**Expected**: no black bar on the list screen; the editor returns to a sensible state (reading mode for an existing note).

**Relates to**: #340 (this is the scenario that produced the original black-bar finding — worth confirming it's reproducible on demand, not a one-off)

**Actual behavior (list screen)**:

**Actual behavior (back in editor)**:

---

### D3. Background and foreground the app with keyboard open
1. In the editor with the keyboard open, press Home (or switch to another app) to background QuKi-Notes.
2. Wait a few seconds, then bring QuKi-Notes back to the foreground.

**Expected**: keyboard/toolbar/cursor state should make sense on return — either still in edit mode with keyboard back up, or cleanly transitioned to reading mode. Not stuck in between.

**Relates to**: #340, #177

**Actual behavior**:

---

## Notes / anything else observed

Use this space for anything that came up that doesn't fit a specific scenario above — a device-specific quirk, an order-dependent effect (e.g. "only happens the second time, not the first"), etc.
