# AI Release Notes Generator — Missing Context Causes Wrong Content (DevOps)

**Status**: confirmed root cause, not yet fixed. For the DevOps session/owner — the broken code lives in a separate repo from QuKi-Notes; see Scope below.

---

## 1. What's wrong

The AI-generated draft release notes for v0.24.1 (`.github/tmp/pre-release-staging/release-notes.md` on branch `pre-release-staging/v0.24.1`) describe the wrong feature and invent symptoms that never happened.

**It says**:
> Sharing text into QuKi Notes from another app using the Android system share sheet now opens cleanly and delivers your note without crashing.
>
> Handled background activity exceptions when receiving shared notes on Android, preventing the app from freezing when launched as a share target.

**What actually shipped** (PRs #402, #404, closing issue #337): QuKi-Notes **sending** a note out via Send → Share Sheet to another app (e.g. Bluesky) was silently failing to deliver the content. Two fixes: (1) replaced `share_plus`'s result-tracking chooser with a plain no-result chooser, and (2) added `FLAG_ACTIVITY_NEW_TASK` + exception handling around the outgoing `startActivity()` call so a failure surfaces as a visible "Send failed" snackbar instead of vanishing silently.

The generated notes have the direction backwards (receiving vs. sending — `share_handler.dart`, the actual receiving code path, was never touched) and invent symptoms — "crashing" and "freezing" — that were never part of the bug report or the fix. Nothing in this work involved a crash or a freeze.

The third bullet in the same output (about the downloads page) is accurate — it correctly describes an unrelated, real commit. So this isn't a total failure of the generator; it's specifically that the share-sheet fix's context reached the model in a form it couldn't get right.

---

## 2. Root cause, traced through the actual pipeline

Path: `.github/workflows/pre-release-staging.yml` (this repo) → `uses: ScottKirvan/.github/.github/workflows/reusable-pre-release-staging.yml@main` (**a different repo** — this is where the actual bug is).

In the reusable workflow's "Fetch commit history and PR descriptions" step, two things go wrong:

**a) Only the commit *subject line* is collected, never the body.**

```sh
gh api "repos/$REPO/compare/$PREV_TAG...$BASE_BRANCH" \
  --jq '.commits[] | "- " + (.commit.message | split("\n") | .[0])' \
  > /tmp/commits.txt
```

`split("\n") | .[0]` discards everything after the first line. For this release, the real commits had detailed, unambiguous bodies — e.g. the #337 fix's body reads *"share_plus unconditionally launches Android shares via a result-tracking chooser... sharing to Bluesky opens its feed instead of compose, pre-filled with nothing"* — but the model never saw any of that. It only received bare lines like `fix: route Android Share Sheet through a plain no-result chooser (#337)`.

**b) The PR-body fetch fails silently, because it extracts *issue* numbers, not PR numbers.**

```sh
grep -oE '#[0-9]+' /tmp/commits.txt | tr -d '#' | sort -u | while IFS= read -r PR_NUM; do
  gh pr view "$PR_NUM" --repo "$REPO" --json title,body ... 2>/dev/null || true
done > /tmp/pr_bodies.txt
```

This regex-matches any `#NNN` in a commit subject and assumes it's a PR number. In this repo's actual convention, a `(#NNN)` suffix on a commit subject is the **issue** being closed, not the PR. The only number that appeared in any relevant commit subject was `#337` — which is an issue. Confirmed directly:

```
$ gh pr view 337 --repo ScottKirvan/QuKi-Notes
GraphQL: Could not resolve to a PullRequest with the number of 337.
```

The `2>/dev/null || true` swallows that failure. `/tmp/pr_bodies.txt` ends up empty (or missing this entry) with no error surfaced anywhere in the workflow run. The real PR bodies — which state plainly and repeatedly "Share Sheet transport," "Send," "sharing a QuKi to Bluesky" — never reached the model.

**Net effect**: the model's entire input for this fix was a handful of bare, bodyless commit subjects containing the words "share," "target," and "startActivity," with nothing disambiguating direction. It filled that gap from its own general knowledge of Android development, where "share + target + startActivity" overwhelmingly describes an app *receiving* a share (an app registered to handle incoming `ACTION_SEND` intents is idiomatically called a "share target") — which is exactly backwards from what was actually built, and it fabricated the crash/freeze framing to fit that invented narrative.

---

## 3. Scope

**Confirmed broken, needs fixing**: `reusable-pre-release-staging.yml` in the **`ScottKirvan/.github`** repository — not this one. This repo's own `.github/workflows/pre-release-staging.yml` just calls it; the bug is entirely upstream. Any fix has to land in `ScottKirvan/.github` to affect every project using this reusable workflow, not just QuKi-Notes.

**Two independent gaps, both in the same "Fetch commit history and PR descriptions" step**:
1. Commit collection truncates to the first line only.
2. PR-number extraction doesn't distinguish issue numbers from PR numbers, and the fetch failure is silent (no error surfaced, no fallback).

**Not investigated here, worth checking alongside a fix**: whether `gh pr view` should fall back to `gh issue view` when a number resolves to an issue instead of a PR (issue bodies often carry the same kind of context PR bodies do, and in this repo's convention, the number in a commit subject usually *is* an issue), and whether truncating commit bodies to some reasonable length (rather than all-or-nothing) is preferable to full inclusion, given prompt-size considerations across a release with many commits.

---

## 4. Not in scope for this doc

This doc is a problem report, not a fix brief — the actual code change belongs to whoever owns `ScottKirvan/.github`. No fix has been attempted or prescribed here beyond the two confirmed gaps above.
