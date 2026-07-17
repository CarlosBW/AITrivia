# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

TriviaIA (`trivia_ia_flutter`) is a Flutter trivia game backed by Firebase (Auth, Firestore, Cloud Messaging, Cloud Functions). It supports solo play, live and async PvP matches, weekly/seasonal leagues, daily challenges, achievements, and AI-generated topics. The codebase is in active development — not all features are finished.

## Commands

All Flutter/Dart commands run from the repo root; Cloud Functions commands run from `functions/`.

```bash
# Install dependencies
flutter pub get

# Static analysis (uses analysis_options.yaml / flutter_lints)
flutter analyze

# Run the app (pick a device)
flutter devices
flutter run -d chrome        # web
flutter run -d windows       # Windows desktop
flutter run                  # prompts for a connected device/emulator

# Tests (no test/ directory exists yet — add tests under test/, mirroring lib/ structure)
flutter test
flutter test test/path/to/some_test.dart          # single file
flutter test --plain-name "some test description"  # single test by name

# Regenerate Firebase config after changing Firebase project settings
flutterfire configure
```

Cloud Functions (`functions/`, TypeScript):

```bash
cd functions
npm run build        # tsc compile
npm run build:watch
npm run lint         # eslint
npm run serve        # build + firebase emulators:start --only functions
npm run shell         # build + firebase functions:shell
npm run deploy        # firebase deploy --only functions
npm run logs
```

Firebase deploy/predeploy automatically runs `lint` then `build` for functions (see `firebase.json`).

## Architecture

### Flutter app structure (`lib/`)

- `main.dart` — app entry point. Initializes Firebase, local notifications (`flutter_local_notifications`) and FCM, schedules a daily-challenge local reminder, wires up `AppLifecyclePresenceObserver` (marks the user online/offline in Firestore via `PresenceService` based on `AppLifecycleState`), and starts `SfxService` before calling `runApp`.
- `app/app.dart` — root `MaterialApp`; `home` is always `AuthGate`.
- `features/auth/auth_gate.dart` — gates the app on Firebase Auth state; `user_bootstrap.dart` handles first-time Firestore user document creation.
- `features/<domain>/` — one folder per feature area, containing screens only (no nested `widgets/`/`models/` subfolders): `home`, `solo` (level select/play), `versus` (both **live** real-time matchmaking/lobby/play and **async** turn-based matches — these are distinct systems, don't conflate them), `daily`, `weekly`, `leagues` (weekly league + season rewards), `achievements`, `ai_topics` (user-created AI-generated quiz topics), `social` (friends), `notifications`, `profile`, `navigation` (bottom-nav shell).
- `services/` — one class per domain, each a singleton via private constructor + static `instance` (see `AvatarService`, pattern used throughout) **or** instantiated directly holding `FirebaseFirestore.instance` / `FirebaseAuth.instance` (see `MatchService`). Services are the only layer that talks to Firestore/Auth directly — screens call into services rather than touching `cloud_firestore`/`firebase_auth` themselves. Key services: `match_service` (live + async PvP matchmaking, match lifecycle, queues in `live_search/{uid}`), `pvp_league_service` / `pvp_season_service` (ELO-based leagues, mirrored by Cloud Functions logic), `league_service` / `weekly_league_service` (weekly competitive leagues), `daily_challenge_service`, `achievement_service`, `economy_service` (in-game currency/rewards), `life_service` (play lives/energy), `player_level_service`, `friend_service`, `presence_service` (online/offline status), `notification_service`, `realtime_invite_service`, `frame_service` / `avatar_service` (cosmetic profile items), `weekly_topic_service`, `ai_topic_service`, `sfx_service`.
- `widgets/` — small shared widgets reused across features (e.g. `player_avatar_widget`, `no_lives_dialog`, `notification_bell_button`).
- Firestore collections are referenced ad hoc by string name inside services (e.g. `live_search`, users collection) rather than through a central schema/constants file — check the relevant service for the exact collection/field names before adding new reads/writes.

### Cloud Functions (`functions/src/index.ts`)

Single-file TypeScript Cloud Functions (v2 API), Firestore-triggered. Currently implements `finalizePvpMatch` (`onDocumentUpdated`), which owns server-side ELO rating calculation (`K_FACTOR = 32`, `DEFAULT_RATING = 1000`) and league assignment (`PVP_LEAGUES` bronze→master by rating band) when a match document is updated. The league thresholds and ELO logic here must stay consistent with `lib/services/pvp_league_service.dart` / `pvp_season_service.dart` on the client — changes to rating/league rules need to be mirrored on both sides.

### Firebase project wiring

- `firebase.json` maps Firebase app IDs per platform (android/ios/macos/web/windows) and points `lib/firebase_options.dart` generation at project `trivia-ia-app`.
- Cloud Functions predeploy always lints + builds before `firebase deploy`.

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding
**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First
**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes
**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution
**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Testing
**Tests are proof of correctness, not busywork. Write them before claiming something works.**

- Every bug fix starts with a failing test that reproduces the bug. Only then fix it.
- Every new feature gets tests for: the happy path, the obvious edge cases, and at least one invalid/error case.
- Never mark a task "done" without running the existing test suite. If you can't run it, say so explicitly - don't assume it passes.
- If tests fail after your change, don't touch unrelated tests to make them pass. Fix your code, or ask if the test needs to change.
- Don't delete or skip a failing test to unblock yourself. Flag it and ask.
- No mocking/stubbing beyond what's needed to isolate the unit under test - don't mock things that could just run for real (fast, local, deterministic).
- Match the existing test framework, style, and file layout. Don't introduce a new testing library because you prefer it.

## 6. Version Control
**You propose, I approve. Nothing lands without my review.**

- Never run `git commit`, `git push`, or open a PR unless I explicitly say so in that moment. A general "looks good" about the code is not approval to commit.
- After making changes, show me a summary of what changed (diff or file list) and wait.
- Don't stage/commit files I didn't ask you to touch, even if they seem related.
- If you think a commit should be split into multiple smaller commits, say so - don't decide unilaterally.
- Never modify git config, remotes, branches (create/delete/switch), or history (rebase, reset --hard, force push) without explicit instruction.
- Write commit messages when asked, but I decide when they get used.

---
**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, tests written before fixes/features (not after), no surprise commits, and clarifying questions come before implementation rather than after mistakes.
 