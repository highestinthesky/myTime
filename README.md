# myTime

A macOS menu bar app I built for myself to stop opening Discord out of boredom. Discord stays closed unless I spend tokens earned by focusing, book a session ahead of time, or use a weekly emergency pass. Loosening any setting takes 24 hours.

It's personal and unsupported, but feel free to use it.

## How it works

Opening a blocked app quits it and shows a gate with a 5-second pause. Ways past the gate:

| Mode | Cost | Access |
|---|---|---|
| Quick look | 1 token, up to 3 at once | 30 s per token |
| Reply mode | 2 tokens and a typed note, 3 per day | 3 min |
| Booked session | Weekly allowance (5 h), booked at least 10 min ahead | The booked window |
| Emergency pass | Once a week, typed reason and a 60 s wait | 10 min |

- **Earning:** start a focus timer. 15 minutes of active focus is 1 token. Idle, locked, or sleeping time earns nothing, and some of it can be claimed back from the panel within a daily budget.
- **Reset:** tokens and partial progress reset every day at 4:00 AM.
- **Settings:** tightening applies at once. Loosening (including uninstall) waits 24 hours and can be cancelled while pending.
- **Quitting:** myTime restarts itself if killed. **Quit myTime…** needs a written reason and a 60 s wait, and it stays off until you open it from Applications.
- **Quiet:** event-driven with no polling, no network, no notifications, and no permissions to grant.

Defaults can be changed in Settings; the full list is in spec §8.

## Install

Requires macOS 14+ on Apple Silicon and the Xcode command line tools.

```bash
scripts/build.sh          # release build, installs to /Applications and starts the LaunchAgent
scripts/build.sh --dev    # test build: fast timescale, separate state-dev.json
scripts/uninstall.sh      # developer escape hatch; the in-app uninstall is delayed
```

## Develop

```bash
swift build
swift test                # 126 tests
swift format --in-place --recursive Sources Tests
```

- `Sources/MyTimeCore/` has all rules and state. It's pure Swift with no clocks or AppKit, and every rule has a test.
- `Sources/MyTimeApp/` is the thin UI and system glue.
- `Tests/MyTimeCoreTests/` is XCTest.

## Docs

- [Design spec](docs/superpowers/specs/2026-09-13-mytime-design.md): the source of truth, currently revision 7.
- [AGENTS.md](AGENTS.md): conventions and the workflow for changing the app.
- [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md): deviations, review findings, and verification per run.
- [docs/MANUAL_TESTS.md](docs/MANUAL_TESTS.md): manual checks to run against an installed build.
- [docs/superpowers/plans/](docs/superpowers/plans/): the four historical run plans.
