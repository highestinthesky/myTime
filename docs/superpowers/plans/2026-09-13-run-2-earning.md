# myTime Run 2 — Earning — Implementation Plan

> **For the implementing agent (Codex):** Work through the tasks **in order**. Steps use checkbox (`- [ ]`) syntax. Read `AGENTS.md` first; its rules were tightened after Run 1 and are enforced in review. **Do not commit**; the reviewer commits.

**Goal:** Tokens can be earned. The user starts a focus session; time before each keyboard/mouse input is credited; idle, a locked screen, or sleep pause crediting; away time can be claimed from the menu bar panel; opening a blocked app during focus shows a "You're focusing" card; the menu bar shows a filling ring while focusing.

**Architecture:** All earning rules live in `MyTimeCore` as an `EngineCore` extension (`FocusAccrual.swift`) called from `update` step 4, plus sleep/wake handlers. The app layer only forwards sleep/wake events, adds a focus-card mode to the existing gate overlay, and adds three views (menu bar ring icon, panel focus block with claim row, today strip). No new timers: focus checks already come from `WakeUpPlanner` (every 30 s while focusing or away).

**Tech Stack:** Swift 6 toolchain in Swift 5 mode, SwiftPM, XCTest, AppKit, SwiftUI. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-09-13-mytime-design.md` — §5.2 (earning), §6.6 (focus card outcomes), §7.1 (menu bar), §7.2 (panel), §7.3 (gate Start Focus), §7.4 (focus card), §7.7 (hold button), §11.1–11.2. Snippets marked **verified** were compiled and run on the target Mac.

---

## How to work

### What went wrong in Run 1 (don't repeat it)

- **Code was compressed onto single lines.** Rejected. Write one statement per line and run `swift format --in-place --recursive Sources Tests` before finishing.
- **The plan's tests were replaced with shorter ones.** Rejected. Copy every test in this plan **verbatim** into the named file. You may add tests; never remove, rename, merge, or weaken one.
- **A rule was implemented to pass the exact test inputs instead of the rule as written.** That shipped a bug. Implement each rule as the spec states it.
- **Two behavior changes weren't recorded.** Every change from the spec goes in `IMPLEMENTATION_NOTES.md`, however small.

### Latitude

- **You decide:** internal code, private helpers, view composition and styling within spec §9, splitting files over ~300 lines, and fixing a snippet here that doesn't compile or behave on the real OS.
- **You must keep:**
  - every behavior, number, and piece of copy in the spec
  - every **public** name/signature under "Interfaces"
  - every test, verbatim
  - spec §13 hard rules
- **If you think the spec or plan is wrong:** implement the closest working behavior and record it under `## Run 2` in `IMPLEMENTATION_NOTES.md`.

### Environment

- Build locally on the Mac (not a Linux sandbox). Run only `swift build …` and `swift test`.
- Don't run `scripts/build.sh`, `scripts/uninstall.sh`, or `launchctl`.
- If the sandbox blocks a build, stop and ask.
- Tests run without `DEV_TIMESCALE` and so see release values (focus per token 900 s, idle threshold 300 s, auto-end 1800 s, claim budget 1800 s/day, min away gap 120 s, min claimable 60 s, focus check 30 s).

---

## Global Constraints

- Swift 5 language mode; UI/engine classes `@MainActor`; `Timer` + `MainActor.assumeIsolated` for callbacks; no `Task.sleep` loops.
- **No new repeating timers.** Focus checks come from `WakeUpPlanner`; the panel already refreshes every 1 s while open (Run 1).
- `MyTimeCore` imports only Foundation/CryptoKit and never reads the clock; time comes from `UpdateInput`.
- Public Core API gets explicit `public init`s.
- Copy is verbatim from the spec: calm, no exclamation marks, no red, no sounds.
- Enforcement is quit-first (spec §5.8/§6): a blocked app without access is quit on sight and the gate or card is shown for the **app**.
- Readable formatting (AGENTS.md rule 6). Tests verbatim (AGENTS.md rule 7).

---

## Current code you'll build on (Run 1, reviewed)

- **`EngineCore` (`Sources/MyTimeCore/Logic/EngineCore.swift`):**
  - `start`, and `update` with steps 1, 2, 5, 8
  - `vest(_:)`, `updateToday(_:)`, `record(_:_:)` (internal)
  - `secondsToNextToken` (already subtracts `runtime.unvestedSeconds`)
  - `start` already ends focus after downtime longer than the idle threshold (untested until this run)
- **`EngineRuntime` (`Sources/MyTimeCore/Model/EngineTypes.swift`):** `unvestedSeconds`, `lastUptime`, `blockedRunningAtLastUpdate`, `awayStartUptime`, `lastActiveBookingID`.
- **`EnforcementPolicy`:** returns `.allow / .terminate / .terminateAndShowGate / .terminateAndShowFocusCard`. `Enforcer` currently shows the gate for both of the last two.
- **`OverlayController` (`Sources/MyTimeApp/UI/OverlayController.swift`):** owns `GateSession` (app, bundleURL, icon, pause, timeout), `showGate(app:bundleURL:)`, `closeGate()`, never-mind and quick-look actions, and the pill.
- **`AppModel.refresh(_:)`:** calls `core.start` for `.launch` and `core.update` otherwise. `.willSleep`/`.didWake` already arrive from `SystemEvents`.
- **`TestSupport.swift`:** has `testTZ`, `date(...)`, `Sim` (with `wall`, `continuous`, `uptime`, `boot`, `idle`, `locked`, `running`, `advance(_:)`), and `makeEngine(at:tokens:)`.

---

## File map for Run 2

| File | Change | Task |
|---|---|---|
| `Sources/MyTimeCore/Model/EngineTypes.swift` | `EngineRuntime.sleepStartContinuous` | 1 |
| `Sources/MyTimeCore/Logic/FocusAccrual.swift` | **new**: focus sessions, per-update accrual, away, auto-end | 1 |
| `Sources/MyTimeCore/Logic/EngineCore.swift` | call `accrueFocus` as update step 4 | 1 |
| `Tests/MyTimeCoreTests/FocusAccrualTests.swift` | **new** | 1 |
| `Sources/MyTimeCore/Logic/FocusAccrual.swift` | claims | 2 |
| `Tests/MyTimeCoreTests/ClaimTests.swift` | **new** | 2 |
| `Sources/MyTimeCore/Logic/FocusAccrual.swift` | sleep/wake handlers | 3 |
| `Tests/MyTimeCoreTests/SleepAndLaunchTests.swift`, `SamplingIndependenceTests.swift` | **new** | 3 |
| `Sources/MyTimeApp/Engine/AppModel.swift` | sleep/wake handlers, focus/claim intents, ring step, claim dot, `syncGateMode` call | 4 |
| `Sources/MyTimeApp/Engine/Enforcer.swift` | focus card action | 4 |
| `Sources/MyTimeApp/UI/OverlayController.swift` | `GateMode`, `showFocusCard`, `syncGateMode`, new actions | 4 |
| `Sources/MyTimeApp/UI/GateView.swift` | `OverlayActions`, Start Focus button | 4 |
| `Sources/MyTimeApp/UI/FocusCardView.swift` | **new** | 4 |
| `Sources/MyTimeApp/UI/MenuBarIcon.swift` | **new** (verified) | 5 |
| `Sources/MyTimeApp/UI/MenuBarLabel.swift` | precedence rows | 5 |
| `Sources/MyTimeApp/UI/FocusRing.swift`, `HoldButton.swift` | **new** (HoldButton verified) | 6 |
| `Sources/MyTimeApp/UI/PopoverView.swift` | focus block, claim row, today strip | 6 |
| `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md` | Run 2 sections | 7 |

---

### Task 1: Focus sessions, accrual, and away

**Files:**
- Modify: `Sources/MyTimeCore/Model/EngineTypes.swift`, `Sources/MyTimeCore/Logic/EngineCore.swift`
- Create: `Sources/MyTimeCore/Logic/FocusAccrual.swift`
- Test: `Tests/MyTimeCoreTests/FocusAccrualTests.swift`

**Interfaces:**
- Consumes: `EngineCore.state`, `runtime`, `now`, `setting(_:)`, `today`, `vest(_:)`, `updateToday(_:)`, `record(_:_:)`, `DurationFormat.short`, `Constants.minAwayGap`.
- Produces:

```swift
// EngineTypes.swift — add as the LAST stored property and the LAST init parameter:
public var sleepStartContinuous: Double?          // init default: nil

// FocusAccrual.swift
extension EngineCore {
    public var isAway: Bool { get }                // runtime.awayStartUptime != nil
    public mutating func startFocus()
    public mutating func endFocus()
    mutating func accrueFocus(_ input: UpdateInput) // internal — update step 4 (spec §5.2 "Per-update accrual")
    mutating func endFocusWithoutVesting(_ historyText: String)  // internal helper: focus = nil, record(.focusEnded, text)
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/FocusAccrualTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

final class FocusAccrualTests: XCTestCase {
    /// Engine at 10:00 with a focus session just started. `Sim` starts at uptime 1000 with idle 0.
    private func focusing(tokens: Int = 0) -> (EngineCore, Sim) {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10), tokens: tokens)
        core.startFocus()
        return (core, sim)
    }

    func testNothingIsCreditedWithoutAFocusSession() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        sim.advance(600)
        _ = core.update(sim.input)
        XCTAssertEqual(core.today.focusSeconds, 0)
        XCTAssertEqual(core.state.progressSeconds, 0)
    }

    func testStartFocusRecordsHistoryAndIsIdempotent() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.startFocus()
        let started = core.state.focus?.startedAt
        core.startFocus()
        XCTAssertEqual(core.state.focus?.startedAt, started)
        XCTAssertEqual(core.state.history.filter { $0.kind == .focusStarted }.count, 1)
        XCTAssertEqual(core.state.history.last?.text, "Started focus")
    }

    func testTimeBeforeTheLastInputVestsAndTheRestStaysUnvested() {
        var (core, sim) = focusing()
        sim.advance(60)
        sim.idle = 10
        _ = core.update(sim.input)
        XCTAssertEqual(core.today.focusSeconds, 50, accuracy: 0.001)
        XCTAssertEqual(core.runtime.unvestedSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(core.state.focus?.creditedSeconds ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(core.secondsToNextToken, 840, accuracy: 0.001)
    }

    func testTokensMintAndProgressCarriesAcrossSessions() {
        var (core, sim) = focusing()
        sim.advance(1000)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 1)
        XCTAssertEqual(core.state.progressSeconds, 100, accuracy: 0.001)
        core.endFocus()
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.history.last?.text, "Focus ended · 17 min")
        sim.advance(300)
        _ = core.update(sim.input)
        core.startFocus()
        sim.advance(800)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 2)
        XCTAssertEqual(core.state.progressSeconds, 0, accuracy: 0.001)
    }

    func testEndFocusVestsUnvestedTime() {
        var (core, sim) = focusing()
        sim.advance(40)
        sim.idle = 15
        _ = core.update(sim.input)
        core.endFocus()
        XCTAssertEqual(core.today.focusSeconds, 40, accuracy: 0.001)
        XCTAssertEqual(core.runtime.unvestedSeconds, 0)
    }

    func testCrossingTheIdleThresholdDiscardsTheIdleMinutes() {
        var (core, sim) = focusing()
        sim.advance(100)
        _ = core.update(sim.input)
        sim.advance(300)
        sim.idle = 300
        _ = core.update(sim.input)
        XCTAssertTrue(core.isAway)
        XCTAssertEqual(core.today.focusSeconds, 100, accuracy: 0.001)
        XCTAssertEqual(core.runtime.unvestedSeconds, 0)
        XCTAssertEqual(core.runtime.awayStartUptime ?? 0, sim.uptime - 300, accuracy: 0.001)
    }

    func testNoCreditForIntervalsThatStartWithABlockedAppRunning() {
        var (core, sim) = focusing()
        let discord = core.state.settings.apps[0].id
        sim.running = [discord]
        sim.advance(1)
        _ = core.update(sim.input)
        sim.advance(100)
        _ = core.update(sim.input)
        sim.running = []
        sim.advance(1)
        _ = core.update(sim.input)
        sim.advance(10)
        _ = core.update(sim.input)
        XCTAssertEqual(core.today.focusSeconds, 11, accuracy: 0.001)
    }

    func testLockingEntersAwayImmediatelyAndUnlockingReturns() {
        var (core, sim) = focusing()
        sim.advance(60)
        _ = core.update(sim.input)
        sim.locked = true
        sim.advance(10)
        sim.idle = 10
        _ = core.update(sim.input)
        XCTAssertTrue(core.isAway)
        sim.advance(170)
        sim.idle = 180
        _ = core.update(sim.input)
        XCTAssertTrue(core.isAway)
        sim.locked = false
        sim.idle = 0
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertFalse(core.isAway)
        XCTAssertEqual(core.today.focusSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 181, accuracy: 0.001)
    }

    func testShortAwayGapsAreNotClaimable() {
        var (core, sim) = focusing()
        sim.locked = true
        sim.advance(30)
        sim.idle = 30
        _ = core.update(sim.input)
        sim.locked = false
        sim.idle = 0
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertFalse(core.isAway)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
    }

    func testLongAbsenceEndsFocusButTheGapIsStillRecorded() {
        var (core, sim) = focusing()
        sim.advance(10)
        _ = core.update(sim.input)
        sim.advance(300)
        sim.idle = 300
        _ = core.update(sim.input)
        sim.advance(1500)
        sim.idle = 1800
        _ = core.update(sim.input)
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.history.last?.text, "Focus ended after 30 min away")
        XCTAssertTrue(core.isAway)
        sim.advance(10)
        sim.idle = 0
        _ = core.update(sim.input)
        XCTAssertFalse(core.isAway)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 1810, accuracy: 0.001)
        XCTAssertEqual(core.today.focusSeconds, 10, accuracy: 0.001)
    }

    func testFocusKeepsTheEngineWakingEveryCheckInterval() {
        var (core, sim) = focusing()
        sim.advance(1)
        let result = core.update(sim.input)
        XCTAssertEqual(result.nextWakeUp, WakeUp(date: core.now.addingTimeInterval(Constants.focusCheckInterval), critical: false))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FocusAccrualTests`
Expected: compile errors (`startFocus`, `isAway` not found).

- [ ] **Step 3: Implement**

1. **`EngineRuntime`:** add `sleepStartContinuous` as described.
2. **`FocusAccrual.swift`:** implement spec §5.2 "Per-update accrual" **exactly** (branches A–D, with the `defer` that updates `lastUptime` and `blockedRunningAtLastUpdate` on *every* path, including when not focusing).
   - The auto-end history text is `"Focus ended after \(DurationFormat.short(input.uptime - awayStart)) away"`.
   - `startFocus()`: no-op if focusing. Otherwise set `focus = FocusSession(startedAt: now)`, `unvestedSeconds = 0`, `awayStartUptime = nil`, and record `.focusStarted` / `"Started focus"`. Keep `lastUptime`.
   - `endFocus()`: guard focusing. `vest(unvestedSeconds)`, then `unvestedSeconds = 0`, `awayStartUptime = nil`. Record `.focusEnded` / `"Focus ended · \(DurationFormat.short(creditedSeconds))"` using the credited seconds **after** vesting. Then set `focus = nil`.
3. **`EngineCore.update`:** call `accrueFocus(input)` immediately after the daily-reset block (step 2) and before grant expiry (step 5):

```swift
        // Step 4: focus accrual and away (spec §5.2)
        accrueFocus(input)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass (Run 1's 56 plus these).

- [ ] **Step 5: Checkpoint** — `swift build && swift test` pass. Do not commit.

---

### Task 2: Claiming away time

**Files:**
- Modify: `Sources/MyTimeCore/Logic/FocusAccrual.swift`
- Test: `Tests/MyTimeCoreTests/ClaimTests.swift`

**Interfaces:**
- Produces:

```swift
extension EngineCore {
    public var claimableSeconds: Double { get }   // max(0, min(today.unclaimedAwaySeconds, awayClaimSecondsPerDay − today.claimedAwaySeconds))
    public mutating func confirmClaim()
    public mutating func dismissClaim()
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/ClaimTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

final class ClaimTests: XCTestCase {
    func testClaimIsCappedByTheDailyBudget() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.updateToday { $0.unclaimedAwaySeconds = 2400 }
        XCTAssertEqual(core.claimableSeconds, 1800, accuracy: 0.001)
        core.confirmClaim()
        XCTAssertEqual(core.today.claimedAwaySeconds, 1800, accuracy: 0.001)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
        XCTAssertEqual(core.today.focusSeconds, 1800, accuracy: 0.001)
        XCTAssertEqual(core.state.tokens, 2)
        XCTAssertEqual(core.state.history.last?.kind, .awayClaimed)
        XCTAssertEqual(core.state.history.last?.text, "Counted 30 min away as focus")

        core.updateToday { $0.unclaimedAwaySeconds = 600 }
        XCTAssertEqual(core.claimableSeconds, 0)
        core.confirmClaim()
        XCTAssertEqual(core.today.focusSeconds, 1800, accuracy: 0.001)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
    }

    func testDismissClearsWithoutCrediting() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.updateToday { $0.unclaimedAwaySeconds = 900 }
        core.dismissClaim()
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
        XCTAssertEqual(core.today.focusSeconds, 0)
        XCTAssertEqual(core.claimableSeconds, 0)
    }

    func testClaimWorksWithoutAFocusSession() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.updateToday { $0.unclaimedAwaySeconds = 300 }
        core.confirmClaim()
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.progressSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(core.state.history.last?.text, "Counted 5 min away as focus")
    }

    func testANewDayStartsWithNothingToClaim() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 3, 0))
        core.updateToday { $0.unclaimedAwaySeconds = 900 }
        sim.advance(3600)
        _ = core.update(sim.input)
        XCTAssertEqual(core.claimableSeconds, 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ClaimTests`
Expected: compile errors.

- [ ] **Step 3: Implement** spec §5.2 "Claims":
- `confirmClaim`: `x = claimableSeconds`. If `x > 0`, then `updateToday { claimedAwaySeconds += x }`, `vest(x)`, and record `.awayClaimed` / `"Counted \(DurationFormat.short(x)) away as focus"`, **in that order** (so the claim is the last history line). Then always `updateToday { unclaimedAwaySeconds = 0 }`.
- `dismissClaim`: `updateToday { unclaimedAwaySeconds = 0 }`.

- [ ] **Step 4: Run tests** — `swift test`, all pass.

- [ ] **Step 5: Checkpoint.** Do not commit.

---

### Task 3: Sleep, wake, launch handling, and sampling independence

**Files:**
- Modify: `Sources/MyTimeCore/Logic/FocusAccrual.swift`
- Test: `Tests/MyTimeCoreTests/SleepAndLaunchTests.swift`, `Tests/MyTimeCoreTests/SamplingIndependenceTests.swift`

**Interfaces:**
- Produces:

```swift
extension EngineCore {
    public mutating func handleWillSleep(_ input: UpdateInput) -> UpdateResult
    public mutating func handleDidWake(_ input: UpdateInput) -> UpdateResult
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/SleepAndLaunchTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

final class SleepAndLaunchTests: XCTestCase {
    func testTimeAsleepIsNeverClaimable() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        core.startFocus()
        sim.advance(60)
        _ = core.update(sim.input)
        _ = core.handleWillSleep(sim.input)
        XCTAssertTrue(core.isAway)
        // Asleep for 10 minutes: wall and continuous clocks move, uptime does not.
        sim.wall = sim.wall.addingTimeInterval(600)
        sim.continuous += 600
        sim.idle = 600
        _ = core.handleDidWake(sim.input)
        XCTAssertNotNil(core.state.focus)
        sim.advance(20)
        sim.idle = 0
        _ = core.update(sim.input)
        XCTAssertFalse(core.isAway)
        XCTAssertEqual(core.today.unclaimedAwaySeconds, 0)
        XCTAssertEqual(core.today.focusSeconds, 60, accuracy: 0.001)
    }

    func testLongSleepEndsFocus() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        core.startFocus()
        _ = core.handleWillSleep(sim.input)
        sim.wall = sim.wall.addingTimeInterval(3600)
        sim.continuous += 3600
        sim.idle = 3600
        _ = core.handleDidWake(sim.input)
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.state.history.last?.text, "Focus ended · Mac was asleep")
        XCTAssertNil(core.runtime.sleepStartContinuous)
    }

    func testRestartAfterDowntimeEndsFocusWithoutCredit() {
        var state = PersistedState.fresh(now: date(2026, 9, 14, 10), timeZone: testTZ)
        state.focus = FocusSession(startedAt: date(2026, 9, 14, 9, 30), creditedSeconds: 1200)
        state.clock = TrustedClockState(
            lastWall: date(2026, 9, 14, 10).timeIntervalSince1970, lastContinuous: 5_000, bootSessionID: "BOOT-A")
        var core = EngineCore(state: state, timeZone: testTZ)
        let sim = Sim(wall: date(2026, 9, 14, 10, 10), continuous: 50, uptime: 50, boot: "BOOT-B")
        _ = core.start(sim.input)
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.today.focusSeconds, 0)
        XCTAssertTrue(core.state.history.contains { $0.text == "Focus ended · myTime wasn't running" })
    }

    func testQuickRelaunchKeepsFocus() {
        var state = PersistedState.fresh(now: date(2026, 9, 14, 10), timeZone: testTZ)
        state.focus = FocusSession(startedAt: date(2026, 9, 14, 9, 30))
        state.clock = TrustedClockState(
            lastWall: date(2026, 9, 14, 10).timeIntervalSince1970, lastContinuous: 5_000, bootSessionID: "BOOT-A")
        var core = EngineCore(state: state, timeZone: testTZ)
        let sim = Sim(wall: date(2026, 9, 14, 10, 0, 5), continuous: 5_005, uptime: 900, boot: "BOOT-A")
        _ = core.start(sim.input)
        XCTAssertNotNil(core.state.focus)
    }
}
```

`Tests/MyTimeCoreTests/SamplingIndependenceTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

final class SamplingIndependenceTests: XCTestCase {
    /// 25-minute script, in seconds from focus start:
    /// 0–600 typing · 600–1005 away (no input) · 1005–1500 typing · Discord open 1200–1320.
    /// Samples run at a fixed cadence plus at Discord's launch/quit, which the real app receives as events.
    private func run(every cadence: Double) -> (focus: Double, unclaimed: Double) {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0].id
        core.startFocus()
        func lastInput(at t: Double) -> Double { t <= 600 ? t : (t < 1005 ? 600 : t) }
        var times = Set(stride(from: cadence, through: 1500, by: cadence))
        times.formUnion([1200, 1320, 1500])
        var previous = 0.0
        for t in times.sorted() {
            sim.advance(t - previous)
            previous = t
            sim.idle = t - lastInput(at: t)
            sim.running = (1200..<1320).contains(t) ? [discord] : []
            _ = core.update(sim.input)
        }
        core.endFocus()
        return (core.today.focusSeconds, core.today.unclaimedAwaySeconds)
    }

    func testFocusPlusAwayTimeDoesNotDependOnHowOftenTheEngineChecks() {
        let fine = run(every: 1)
        let sparse = run(every: 30)
        XCTAssertEqual(fine.focus, 975, accuracy: 2)
        XCTAssertEqual(fine.unclaimed, 405, accuracy: 2)
        XCTAssertEqual(fine.focus + fine.unclaimed, sparse.focus + sparse.unclaimed, accuracy: 2)
        // Coming back is noticed at the next check, so at most one interval moves from focus to away time.
        XCTAssertEqual(fine.focus, sparse.focus, accuracy: 30 + 2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "SleepAndLaunchTests|SamplingIndependenceTests"`
Expected: compile errors (`handleWillSleep` not found). Once Task 3 compiles, the launch tests may already pass because Run 1's `start` implements that rule; that's fine.

- [ ] **Step 3: Implement** spec §5.2 "Sleep and wake" exactly:
- **`handleWillSleep`:** `let result = update(input)`, then `runtime.sleepStartContinuous = input.continuous`. If focusing and not away: `awayStartUptime = input.uptime - input.idleSeconds`, `unvestedSeconds = 0`. Return `result`.
- **`handleDidWake`:**
  - If focusing, `sleepStartContinuous != nil`, and `input.continuous - sleepStartContinuous! >= autoEndAwaySeconds`, call `endFocusWithoutVesting("Focus ended · Mac was asleep")`.
  - If away, set `awayStartUptime = input.uptime`.
  - Set `runtime.lastUptime = input.uptime` and `runtime.sleepStartContinuous = nil`.
  - `return update(input)`.
- Refactor `start`'s downtime branch to call `endFocusWithoutVesting("Focus ended · myTime wasn't running")` (same behavior).

- [ ] **Step 4: Run tests** — `swift test`, all pass.

- [ ] **Step 5: Checkpoint.** Do not commit.

---

### Task 4: App wiring, focus card, and gate Start Focus

**Files:**
- Modify: `Sources/MyTimeApp/Engine/AppModel.swift`, `Sources/MyTimeApp/Engine/Enforcer.swift`, `Sources/MyTimeApp/UI/OverlayController.swift`, `Sources/MyTimeApp/UI/GateView.swift`
- Create: `Sources/MyTimeApp/UI/FocusCardView.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:

```swift
// AppModel
func startFocus()                 // perform { $0.startFocus() }
func endFocus()                   // perform { $0.endFocus() }
func confirmClaim()               // perform { $0.confirmClaim() }
func dismissClaim()               // perform { $0.dismissClaim() }
var ringStep: Int { get }         // Int(((progress + unvested) / focusSecondsPerToken * 12).rounded(.down)), clamped 0...12
var showsClaimDot: Bool { get }   // core.claimableSeconds >= Constants.minClaimable && grantCountdown == nil

// OverlayController
enum GateMode { case gate, focusCard }
func showGate(app: BlockedApp, bundleURL: URL?)       // existing
func showFocusCard(app: BlockedApp, bundleURL: URL?)
func syncGateMode()               // gate showing in .gate mode while focus is active → reopen as .focusCard

// GateSession gains: let mode: GateMode  (init parameter after bundleURL)

// GateView.swift
struct OverlayActions {
    let neverMind: () -> Void
    let quickLook: (Int) -> Void
    let startFocus: () -> Void
    let backToWork: () -> Void
    let endFocus: () -> Void
}
struct GateView: View { init(session: GateSession, model: AppModel, actions: OverlayActions) }
struct FocusCardView: View { init(session: GateSession, model: AppModel, actions: OverlayActions) }
```

- [ ] **Step 1: `AppModel.refresh`** — route sleep/wake to the new handlers, and sync the overlay mode before the pill:

```swift
        let result: UpdateResult
        switch reason {
        case .launch: result = core.start(input)
        case .willSleep: result = core.handleWillSleep(input)
        case .didWake: result = core.handleDidWake(input)
        default: result = core.update(input)
        }
```

In the existing `switch reason` that follows, keep `.didWake` → `Installer.selfHeal()` and `.willSleep` → `saveNow()`. Call `overlays.syncGateMode()` immediately before `overlays.updatePill()`. Add the four intent methods and two computed properties listed above.

- [ ] **Step 2: `Enforcer.reconcile`** — split the combined case:

```swift
        case .terminateAndShowGate:
            let bundleURL = process.bundleURL
            terminate(process)
            model.overlays.showGate(app: app, bundleURL: bundleURL)
        case .terminateAndShowFocusCard:
            let bundleURL = process.bundleURL
            terminate(process)
            model.overlays.showFocusCard(app: app, bundleURL: bundleURL)
```

- [ ] **Step 3: `OverlayController`**
- Add `GateMode` and store `mode` on `GateSession`.
- Generalize `showGate` into a private `show(app:bundleURL:mode:)`, with `showGate` and `showFocusCard` as one-line wrappers.
  - The guard becomes `guard !(gateAppID == app.id && session?.mode == mode) else { return }`.
  - The root view is `GateView` for `.gate` and `FocusCardView` for `.focusCard`, both given the same `OverlayActions`.
  - The 60 s timeout calls `neverMind()` in `.gate` mode and `backToWork()` in `.focusCard` mode.
- **Actions** (spec §6.5–§6.6). All of them count "backed off" exactly once, except End focus:

| Action | Behavior |
|---|---|
| `neverMind` | Existing: backed off, close. |
| `startFocus` | Capture the app, `closeGate()`, then `model.perform { $0.recordBackedOff(appID: id); $0.startFocus() }`. Close **before** starting focus so `syncGateMode` doesn't flip the gate into a card first. |
| `backToWork` | Backed off, close. |
| `endFocus` | Capture `app` and `bundleURL`, `closeGate()`, `model.endFocus()`, then `showGate(app:bundleURL:)`. This is a fresh gate with the full pause, and nothing is counted as backed off. |

- **`syncGateMode()`:** if `session?.mode == .gate` and `model.core.state.focus != nil`, capture the app and bundleURL, `closeGate()`, then `showFocusCard(app:bundleURL:)`.

- [ ] **Step 4: `GateView`** — replace the `onNeverMind`/`onQuickLook` closures with `actions: OverlayActions`. In the no-tokens state, add a **Start Focus** button under the text (spec §7.3), with `.buttonStyle(.bordered)`, calling `actions.startFocus`.

- [ ] **Step 5: `FocusCardView`** (spec §7.4):
- Width 360, padding 24, same surface as the gate (`.regularMaterial`, radius 22, 1 pt separator stroke).
- Content: the app icon from `session.icon` at 48 pt, then the title **"You're focusing"** (`.title3.weight(.semibold)`).
- Body: `"\(DurationFormat.short(model.core.secondsToNextToken)) to your next token."` (secondary).
- Buttons in an `HStack`:
  - **End focus…** (`.bordered`) → `actions.endFocus`
  - **Back to work** (`.borderedProminent`, `.keyboardShortcut(.cancelAction)`) → `actions.backToWork`

- [ ] **Step 6: Build**

Run: `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`
Expected: `Build complete!` twice; all tests pass.

- [ ] **Step 7: Checkpoint.** Do not commit.

---

### Task 5: Menu bar ring icon and label precedence

**Files:**
- Create: `Sources/MyTimeApp/UI/MenuBarIcon.swift`
- Modify: `Sources/MyTimeApp/UI/MenuBarLabel.swift`

**Interfaces:**
- Consumes: `AppModel.ringStep`, `AppModel.showsClaimDot`, `AppModel.grantCountdown`, `core.isAway`.
- Produces: `MenuBarIcon.image(_ kind: MenuBarIcon.Kind, dot: Bool) -> NSImage`, with `Kind` = `.diamond`, `.pause`, `.ring(step: Int)`.

- [ ] **Step 1: `MenuBarIcon.swift`** (**verified**: all variants render as template images, the ring fills in 12 steps, and the halo keeps the dot off the glyph):

```swift
import AppKit

/// Menu bar glyphs drawn as template images so the system tints them for light/dark menu bars (spec §7.1).
@MainActor enum MenuBarIcon {
    enum Kind: Hashable {
        case diamond
        case pause
        case ring(step: Int)
    }

    nonisolated static let size = NSSize(width: 18, height: 16)
    private static var cache: [String: NSImage] = [:]

    static func image(_ kind: Kind, dot: Bool) -> NSImage {
        let key = "\(kind)-\(dot)"
        if let cached = cache[key] { return cached }
        let image = NSImage(size: size, flipped: false) { _ in
            switch kind {
            case .diamond: drawSymbol("diamond.fill")
            case .pause: drawSymbol("pause.circle")
            case .ring(let step): drawRing(step: max(0, min(12, step)))
            }
            if dot {
                // Clear a small halo first so the dot never touches the glyph underneath.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 12.2, y: 9.2, width: 6.8, height: 6.8)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 13.4, y: 10.4, width: 4.4, height: 4.4)).fill()
            }
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }

    private static func drawSymbol(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        else { return }
        let s = symbol.size
        symbol.draw(in: NSRect(x: (16 - s.width) / 2, y: (16 - s.height) / 2, width: s.width, height: s.height))
    }

    private static func drawRing(step: Int) {
        let center = NSPoint(x: 8, y: 8)
        let outline = NSBezierPath(ovalIn: NSRect(x: 1.75, y: 1.75, width: 12.5, height: 12.5))
        outline.lineWidth = 1.5
        NSColor.black.setStroke()
        outline.stroke()
        guard step > 0 else { return }
        let wedge = NSBezierPath()
        wedge.move(to: center)
        wedge.appendArc(withCenter: center, radius: 5, startAngle: 90, endAngle: 90 - CGFloat(step) * 30, clockwise: true)
        wedge.close()
        NSColor.black.setFill()
        wedge.fill()
    }
}
```

- [ ] **Step 2: `MenuBarLabel`** — spec §7.1 rows for Run 2 (the booking row arrives in Run 3). First match wins:

| State | Icon | Text |
|---|---|---|
| `model.grantCountdown != nil` | `Image(systemName: "hourglass")` | `DurationFormat.clock(remaining)` |
| focusing and `core.isAway` | `Image(nsImage: MenuBarIcon.image(.pause, dot: model.showsClaimDot))` | tokens |
| focusing | `Image(nsImage: MenuBarIcon.image(.ring(step: model.ringStep), dot: model.showsClaimDot))` | tokens |
| otherwise | `Image(nsImage: MenuBarIcon.image(.diamond, dot: model.showsClaimDot))` | tokens |

Keep `HStack(spacing: 4)`, `monospacedDigit()`, the `"DEV "` prefix, and reading `model.uiNow` in the body.

- [ ] **Step 3: Build** — `swift build && swift build -Xswiftc -DDEV_TIMESCALE`, both succeed.

- [ ] **Step 4: Checkpoint.** Do not commit.

---

### Task 6: Panel — focus block, claim row, today strip

**Files:**
- Create: `Sources/MyTimeApp/UI/FocusRing.swift`, `Sources/MyTimeApp/UI/HoldButton.swift`
- Modify: `Sources/MyTimeApp/UI/PopoverView.swift`

**Interfaces:**
- Consumes: `AppModel.startFocus/endFocus/confirmClaim/dismissClaim`, `core.secondsToNextToken`, `core.isAway`, `core.claimableSeconds`, `core.today`, `Theme.accent`.
- Produces: `FocusRing(fraction: Double)`, `HoldButton(title: String, duration: TimeInterval, action: () -> Void)`.

- [ ] **Step 1: `HoldButton.swift`** (**verified** to compile against macOS 14):

```swift
import SwiftUI

/// Press and hold to confirm (spec §7.7). Releasing early resets the fill.
struct HoldButton: View {
    let title: String
    let duration: TimeInterval
    let action: () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.accent.opacity(0.35))
                        .frame(width: geo.size.width * progress)
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 20) {
                action()
            } onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { progress = 0 }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Count away time") { action() }
    }
}
```

- [ ] **Step 2: `FocusRing.swift`**
- A 160×160 `ZStack` holding a background `Circle().stroke(.quaternary, lineWidth: 10)`.
- On top, `Circle().trim(from: 0, to: fraction)` stroked with `Theme.accent`, `StrokeStyle(lineWidth: 10, lineCap: .round)`, `.rotationEffect(.degrees(-90))`, `.animation(.easeInOut(duration: 0.3), value: fraction)`.
- Center content is supplied by the caller through a `@ViewBuilder` trailing closure: `FocusRing(fraction:) { … }`.

- [ ] **Step 3: `PopoverView`** — spec §7.2 order for Run 2. `VStack(alignment: .leading, spacing: 16)`, padding 16, width 320. Keep the existing `onAppear`/`onDisappear`.

1. `Text("myTime").font(.headline)`.
2. **Focus block** (centered):
   - `FocusRing(fraction: (progress + unvested) / focusSecondsPerToken)`.
   - In the ring center, `DurationFormat.clock(core.secondsToNextToken)` in `.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()`, with `"to next token"` (caption, secondary) under it.
   - Under the ring:
     - not focusing: no caption; button **Start Focus** (`.borderedProminent`, `.controlSize(.large)`) → `model.startFocus()`
     - focusing and away: caption `"Paused — no activity"`; button **End Focus** (`.bordered`) → `model.endFocus()`
     - focusing: caption `"This session · \(DurationFormat.short(creditedSeconds + unvested))"`; button **End Focus**
3. **Claim row** — only if `core.claimableSeconds >= Constants.minClaimable`:
   - `Text("You were away \(DurationFormat.short(core.today.unclaimedAwaySeconds)) during focus today.")`
   - `HoldButton(title: label, duration: Constants.holdToConfirm) { model.confirmClaim() }`, where `label = "Hold to count \(DurationFormat.short(core.claimableSeconds))"` with `" (daily limit)"` appended when `claimableSeconds < unclaimedAwaySeconds`
   - `Button("Dismiss") { model.dismissClaim() }.buttonStyle(.plain).foregroundStyle(.secondary)`
4. **Tokens row** (existing).
5. **Today strip:** three equal columns (`HStack` of `VStack`s with `frame(maxWidth: .infinity)`): caption label over a value. Labels and values: `"Focus"` / `short(today.focusSeconds)`, `"Earned"` / `"\(today.tokensEarned)"`, `"Backed off"` / `"\(today.backedOff)"`.
6. DEV row (existing).

- [ ] **Step 4: Build** — `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`, all succeed.

- [ ] **Step 5: Checkpoint.** Do not commit.

---

### Task 7: Docs and final verification

**Files:**
- Modify: `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md`

- [ ] **Step 1: Append `## Run 2` to `docs/MANUAL_TESTS.md`** with spec §11.2 steps 8–13 verbatim, plus these two:
  - **14. Short sleep:** during focus, close the lid for 1 minute and reopen → focus is still on, and no away time is offered for the sleep.
  - **15. Focus card:** during focus, open Discord → Discord quits with no window flashing and the "You're focusing" card appears. **End focus…** swaps to the gate with a fresh 5 s pause, and "Backed off" does **not** increase.

- [ ] **Step 2: Append `## Run 2` to `IMPLEMENTATION_NOTES.md`** with `### Deviations` (or "None."), `### Not verified`, and `### Commands run`.

- [ ] **Step 3: Format and verify**

```bash
swift format --in-place --recursive Sources Tests
swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test && swift build -c release --arch arm64 -Xswiftc -DDEV_TIMESCALE
```

Expected: every build prints `Build complete!`; tests report 0 failures. Paste the test summary line into the notes.

- [ ] **Step 4: Self-check before replying.** Confirm each item and say so in your reply:
  - [ ] No line in `Sources/` or `Tests/` exceeds ~130 characters (`awk 'length > 130' $(find Sources Tests -name '*.swift')` prints nothing, or only long string literals).
  - [ ] All plan test files exist with the exact test method names from this plan.
  - [ ] Every behavior change from the spec is listed in the notes.

- [ ] **Step 5: Stop.** Don't start Run 3 and don't commit. Reply with what you built, the test count, and every deviation.

---

## Self-review record (reviewer)

**Spec coverage for Run 2 (§12):**

| Spec item | Task |
|---|---|
| FocusAccrual (accrual, away, idle, lock, auto-end) | 1 |
| Claims | 2 |
| Sleep/wake handlers, launch handling | 3 |
| Sampling independence test | 3 |
| Lock/unlock + sleep/wake/power-off events | already subscribed in Run 1; handlers wired in 4 |
| `MenuBarIcon` ring, pause icon, claim dot | 5 |
| Panel focus block, claim row, `HoldButton`, today strip, "Resets at" caption | 6 (caption exists from Run 1) |
| `FocusCardView`, gate Start Focus button | 4 |
| Tests: FocusAccrual incl. sampling, launch handling | 1, 3 |
| Manual steps 8–13 (+14, 15) | 7 |

**Test validation:** every test in this plan was run against a reference implementation written straight from spec §5.2 in a scratch copy (not committed): 76/76 pass together with Run 1's tests. If a plan test fails on your implementation, the implementation diverges from the spec.

**Design refinements made while planning:**
- Exact sampling independence isn't achievable when a return is detected on a 30 s check; spec §5.2/§11.1 now state the conserved quantity (focus + away).
- Sleeping ≥ 30 min ends focus.
- The claim dot is monochrome, drawn into the template icon.
