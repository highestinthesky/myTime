# AGENTS.md — myTime

myTime is a macOS menu-bar app that gates distracting apps (Discord by default) behind tokens earned with a focus timer.

**Source of truth:** `docs/superpowers/specs/2026-09-13-mytime-design.md`. Read it before changing anything. If code and spec disagree, the spec wins unless `IMPLEMENTATION_NOTES.md` records an approved deviation.

## Commands

| Task | Command |
|---|---|
| Build | `swift build` |
| Unit tests | `swift test` |
| Install DEV build (fast timescale, `state-dev.json`) | `scripts/build.sh --dev` |
| Install release build | `scripts/build.sh` |
| Remove install (developer only) | `scripts/uninstall.sh` |
| Agent status | `launchctl print gui/$(id -u)/local.mytime.agent` |

## Layout

- `Sources/MyTimeCore/` holds **all rules and state**. It is pure Swift (Foundation + CryptoKit only) and fully unit-tested. There are no clocks, no `Date()`, and no AppKit here; time and system readings come in as parameters.
- `Sources/MyTimeApp/` is glue and UI: system events, enforcement side effects, overlays, windows. It is thin and declarative.
- `Tests/MyTimeCoreTests/` is XCTest. Every rule in Core has a test.

## Conventions

1. Swift 5 language mode. UI and engine types are `@MainActor`. Use `Timer`, not `Task.sleep` loops.
2. **No polling.** The engine runs on events plus one scheduled wake-up. Repeating timers exist only while their UI is visible (spec §3.6), and every `Timer` sets `tolerance`.
3. Core API used by the app must be `public`, with explicit `public init`s.
4. Persisted dictionaries use `String` keys.
5. Keep files focused (~300 lines max). New rules go in Core with tests, never in views.
6. No third-party dependencies. No network, UserNotifications, Accessibility APIs, AppleScript, sandbox, or entitlements.
7. User-facing copy comes from the spec verbatim. The tone is calm and neutral: no guilt, no exclamation marks, no red, no sounds.
8. Don't add features, settings, or copy that aren't in the spec.

## Working in runs

- The app is built in the runs listed in spec §12. Build only the run you were given.
- At the end of a run:
  - `swift build` and `swift test` must pass.
  - Append that run's steps to `docs/MANUAL_TESTS.md`.
  - Append a `## Run N` section to `IMPLEMENTATION_NOTES.md` covering deviations, anything unverified, and the commands you ran with their results.
- **Do not commit.** The reviewer reviews, fixes, and commits.

## Changing the app later

Update the spec first (describe the new behavior and bump the revision line), then change Core and its tests, then the UI. Keep `AGENTS.md` accurate if commands or conventions change.
