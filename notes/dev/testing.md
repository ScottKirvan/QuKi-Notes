# Testing Strategy

Tests ship **with the code**, not as a later cleanup phase. Every feature PR includes its tests. Every bug fix includes a regression test written **before** the fix.

This file is the operational spec. The policy decision lives in `decisions.md` → ADR-13.

---

## Test layers

| Layer           | Tool                        | What goes here                                                                                                                                               |
| --------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Unit            | `flutter_test` + `mocktail` | Pure logic, services with substitutable deps, DAOs (against in-memory drift), serializers, transport plugins' core logic                                     |
| Widget          | `flutter_test`              | UI behavior where the widget has non-trivial state or transforms input (formatting toolbar, transport picker sheet, image-paste handler)                                |
| Integration     | `integration_test/`         | End-to-end flows across DB + UI on a real device or emulator (QuKi CRUD round-trip, paste→render→save→reopen, send success/failure)                          |
| Drift migration | `drift_dev schema verify`   | Schema snapshots in `test/db/schemas/`. Required for every `schemaVersion` bump per ADR-8                                                                    |

---

## What must have a test

- Every transport plugin's `transport()` happy path + at least one failure path (retryable + non-retryable)
- Every transport plugin's `settingsView` validation (rejecting bad input, persisting good input)
- The save controller's debounce/periodic/lifecycle triggers
- The 24h delete-sweep behavior (boundary cases)
- Image paste validation (size limits, MIME type whitelist)
- Image-ref diff at save time (detecting removed `![](../images/...)` references for cascade delete)
- Filename generation (`YYYY-MM-DD-{uuid8}.{ext}` for images and `.md` for transport-derived QuKi filenames)
- Markdown round-trip through `super_editor` for every GFM feature in the toolbar (resolves OQ-1)
- Every `MigrationStrategy.onUpgrade` step (per ADR-8)
- When sync ships (v1.1+): sync state machine transitions, conflict resolver, rate-limit throttle, OAuth device flow polling

## What does NOT need a test

- Pure-render widgets with no state or logic (e.g. a `Text` wrapper)
- Third-party glue with no behavior of our own added (e.g. `url_launcher` invocation)
- Generated code (`*.g.dart` files, drift output)
- Flutter framework internals
- Trivial getters/setters

If you're unsure: write the test. The cost of one unit test is much smaller than the cost of one production bug.

---

## Test layout

Mirror `lib/`:

```
test/
├── core/
│   ├── database/
│   │   ├── qukis_dao_test.dart
│   │   ├── images_dao_test.dart
│   │   └── ...
│   ├── transports/
│   │   ├── transport_registry_test.dart
│   │   ├── save_controller_test.dart
│   │   └── plugins/
│   │       ├── clipboard_transport_test.dart
│   │       └── ...
│   └── settings/
├── features/
│   ├── editor/
│   ├── stream/
│   └── settings/
├── shared/
└── db/
    └── schemas/        ← drift snapshots, do not edit by hand
integration_test/
├── quki_crud_flow_test.dart
└── ...
```

**File naming:** `foo.dart` → `foo_test.dart` in the mirrored test path.

---

## Mocking discipline

- **`mocktail`** is the only mock library used. No `mockito` (deprecated codegen approach).
- **Mock services, not data.** Services (transports, future `GitHubClient`, future `SyncBackend`) are mocked; `Quki` / `Image` data classes are constructed directly.
- **Database tests use real drift** with `NativeDatabase.memory()` — never mock drift. The DAO layer is the boundary; mock it only when testing something built on top of it.
- **Network**: never make real HTTP in unit/widget tests. `dio` (when used by a transport) is mocked at the client wrapper level. Integration tests may hit a sandbox endpoint in v1.1+ when transports/sync need it (deferred — for MVP, no network in any test).

---

## Bug-fix protocol (mandatory)

Every PR with `fix:` in the conventional commit title MUST follow this protocol:

1. **Reproduce the bug** in a test. The test fails on the current `main`.
   - Add the test in the file that mirrors the buggy code (e.g. a sync bug → `test/core/sync/...`).
   - Test name explicitly states the bug: `test('fires push after 30s periodic flush — regression: bug #42', () { ... })`.
2. **Commit the failing test on its own**, optionally with a `// FIXME: failing — fixes #42` comment. CI will be red. This is intentional and proves the test catches the bug.
3. **Implement the fix.** Now the test passes.
4. **Verify locally**: `just test` is green.
5. **PR body** must include:
   - Link to the issue / description of the bug
   - File:line of the regression test
   - One sentence on root cause (not just the symptom)

The regression test stays in the suite forever. **Never delete a regression test** without an ADR justifying it.

**Why two commits (failing test, then fix):** the diff explicitly shows the test catches the bug. If the test passed without the fix, it wouldn't be a valid regression test — it would be testing something the existing code already does, and a future regression could slip past it.

Keep the two commits separate — both land on `main` via rebase merge, and the dev-time discipline of "red test first" is non-negotiable.

---

## Flaky tests

**Zero tolerance.** A test that passes intermittently is worse than no test — it teaches the team to ignore CI red.

- A test failing once on retry: investigate immediately, don't ignore.
- A test that can't be made deterministic in one session: add `@Tags(['flaky'])`, open an issue, exclude from CI via `dart test --exclude-tags=flaky`. **Then fix it within the next session** — don't let flaky tests accumulate.
- A test that depends on real network or wall-clock time: refactor to inject the clock / network — never `Future.delayed` in a test.

---

## CI expectations

`ci.yml` runs:

```
flutter analyze
dart format --output=none --set-exit-if-changed lib/ test/
flutter test
```

All three must be green for merge. No exceptions, no `--no-verify`, no `[skip ci]` for fixes.

**Coverage**: no threshold enforced. Coverage thresholds are a perverse incentive (write tests to chase the number, not the risk). The PR review is the gatekeeper — "where's the test for this code path?" is the right question, not "is coverage above 80%?".

Integration tests are **not** run in CI for MVP (they require a device/emulator). The project owner runs them locally when merging significant Phase 1+ PRs:

```bash
flutter test integration_test/
```

---

## Phase-by-phase test focus

| Phase | Key tests to add |
|---|---|
| 0 (bootstrap) | Generated default widget test passes — proves CI toolchain works |
| 1 (local capture) | DAO tests (qukis + images), save controller triggers, 24h delete sweep, formatting toolbar widget tests, image paste validation, image-ref diff, super_editor round-trip |
| 2 (transports) | Transport registry tests, first built-in transport (likely clipboard) happy + failure paths, transport-picker-sheet widget test, settings view for each plugin |
| 3 (polish + Win + Linux) | Share-in handler, accessibility semantics, integration tests for full capture→send flows, platform-specific quirks (keyboard shortcuts, file path separators, libsecret on Linux) |
| 4 (sync, v1.1+) | First sync backend with mocked dio, sync state machine, conflict resolver, rate-limit throttle, OAuth device flow polling |
| 6 (MCP, v2.0+) | MCP server handler tests, JSON-RPC envelope round-trip, capability negotiation |

Tests come with code from Phase 1 onward — no "tests come later" phase.

---

## Known widget-test gotcha: `pumpWidget()` reuse silently keeps stale content

Found 2026-07-30 (during ADR-34 follow-up work) and empirically confirmed, not theoretical: calling `tester.pumpWidget()` more than once within a single `testWidgets` block, to compare two different `initialValue`s on `MarkdownEditor`/`QuikiEditor`, does **not** force a fresh mount if the two widget trees are structurally identical (same types, no distinguishing `Key`). `MarkdownEditorController`'s underlying `State` has no `didUpdateWidget` override, so Flutter treats the second `pumpWidget` call as an in-place update and the widget silently keeps rendering the **first** call's content — the test still runs and can still pass, but it's comparing the first document to itself, not genuinely exercising the second input.

**How to avoid it** (either is fine, both are already used correctly elsewhere in this suite):
- Give each `pumpWidget` call a distinguishing `Key` (e.g. `UniqueKey()` on the top-level `MaterialApp`) — forces a real unmount + remount every time. See `tab_render_width_test.dart` for the pattern.
- Force a teardown between calls by pumping an unrelated widget type in between (e.g. `await tester.pumpWidget(const SizedBox())`) — breaks `Widget.canUpdate()`'s compatibility check. See the toolbar/keystroke-equivalence tests in `indent_dedent_test.dart` for the pattern.

**Caught one real instance** of the un-mitigated version: a test in `block_indentation_test.dart` (ADR-34 marker-gutter-leak fix) compared two documents via two same-tree `pumpWidget` calls with no key — its "without list" half was vacuously comparing the first document to itself. The underlying fix was still correct (independently verified by code review and by a sibling single-pump test in the same group), but the test itself wasn't proving what it claimed. Fixed as a standalone follow-up once found — see git history for that PR.

If you're writing or reviewing a widget test that calls `pumpWidget` more than once to compare states, check for this specifically — it won't show up as a failure, only as a test that's weaker than it looks.
