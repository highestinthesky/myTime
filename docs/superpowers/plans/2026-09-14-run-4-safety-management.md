# myTime Run 4 — Safety and Management — Implementation Plan

> **For the implementing agent (Codex):** Work through the tasks **in order**. Steps use checkbox (`- [ ]`) syntax. Read `AGENTS.md` first. **Do not commit**; the reviewer commits.

**Goal:** Make myTime manageable without weakening it:
- a **Settings window** where tightening applies at once and loosening waits out a delay (24 h in release, 1 min in DEV)
- **blocked apps** you can add, remove, and configure
- a **Pending** list with cancel and a delayed **uninstall**
- a **History** view
- the **tamper banner** and **clock-change note**
- **pruning** of old data

**Architecture:** All rules live in `MyTimeCore`:
- `SettingsPolicy.swift`: the loosening check, the add-app check, `submit`, `summary`, `cancelPending`, and apply-due (`update` step 3)
- `Pruning.swift`: `update` step 7
- `DurationFormat.historyDay` for History headings

The app layer adds:
- a Settings window (four tabs) through `WindowRouter`
- settings intents on `AppModel`
- the uninstall effect
- the panel's gear, pending capsule, and tamper banner

The only new timer is a 1 s `refresh(.panel)` while the Settings window is open (spec §3.6).

**Tech Stack:** Swift 6 toolchain in Swift 5 mode, SwiftPM, XCTest, AppKit, SwiftUI. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-09-13-mytime-design.md` (revision 5). Sections: §3.2 (reopen, uninstall), §3.6, §4.6, §5 (API, update order), §5.6, §5.7, §6.8, §7 formatting helpers, §7.2 items 1–2, §7.9, §8.1–§8.2, §11.1–§11.2.

---

## How to work

### Since Run 3

- Run 3 was clean. Keep doing the same: tests verbatim, rules as written, readable code, every deviation recorded.
- **Reviewer changes after Run 3 (spec revision 4) that you'll build on:**
  - myTime installs to `/Applications/myTime.app`.
  - **Quitting:**
    - The panel ends with **Quit myTime…**, which opens `QuitView` through `WindowRouter.showQuit()`.
    - `core.quit(reason:)` lives in `Logic/Quit.swift`.
    - `Installer.stopAgent()` removes the plist, boots the job out, and exits. Uninstall reuses it.
  - **Session start reminder:** `EngineEffect.bookingStarted(bookingID:)` exists. `HeadsUpController.show(_:bookingID:)` takes a `HeadsUpKind` (`.started` or `.endingSoon`).
  - **`WindowRouter`** has a private generic `show(title:content:)` that keeps one window per title. Extend it rather than writing a second window mechanism.
  - **Menu bar and panel:** the menu bar label has no `DEV ` prefix. The panel title is "myTime · DEV" in DEV builds.
  - **Manual step numbers:** Run 3 is 16–19, Run 4 is 20–25.

### Latitude

- **You decide:**
  - internal code and private helpers
  - view composition and styling within spec §9
  - splitting files over ~300 lines (suggested files are below)
  - fixing a snippet that doesn't compile or behave on the real OS
- **You must keep:**
  - every behavior, number, and piece of copy in the spec
  - every **public** name and signature under "Interfaces"
  - every test, verbatim
  - spec §13 hard rules
- **If you think the spec or plan is wrong:** implement the closest working behavior and record it under `## Run 4` in `IMPLEMENTATION_NOTES.md`.

### Environment

- Build locally on the Mac. Run only `swift build …` and `swift test`.
- Don't run `scripts/build.sh`, `scripts/uninstall.sh`, or `launchctl`.
- Tests run without `DEV_TIMESCALE`, so they see release values (24 h loosening delay, 5 h weekly session time). See the doc comment at the top of each test file.

---

## Global Constraints

- Swift 5 language mode.
- UI and engine classes are `@MainActor`. Use `Timer` with `MainActor.assumeIsolated`, never `Task.sleep` loops.
- **No new repeating timers** except the 1 s Settings refresh (§3.6), which runs only while the Settings window is open. Every `Timer` sets `tolerance`.
- `MyTimeCore` imports only Foundation and CryptoKit, and never reads the clock or `Locale.current`. The app passes `.current` in.
- Public Core API gets explicit `public init`s. Persisted dictionaries keep `String` keys.
- Copy is verbatim from the spec: calm, no exclamation marks, no red (a destructive-*style* button is fine), no sounds.
- Tightening applies immediately, and loosening is scheduled. **Nothing in the UI may apply a loosening change directly**; it always goes through `submit`.
- Readable formatting (AGENTS.md rule 6). Tests verbatim (AGENTS.md rule 7).

---

## Current code you'll build on

- **`EngineCore` (`Logic/EngineCore.swift`):**
  - `update` runs, in order:
    1. clock
    2. daily reset (an inline `if state.tokensDayKey != key` block)
    3. `accrueFocus`
    4. grant expiry (builds `effects`)
    5. `applyBookingTransitions` (merged without duplicates)
    6. the wake-up planner
  - Helpers: `record`, `updateToday`, `setting`, `app(id:)`, `dayStartHour`, `timeZone`, `now`.
- **Model types already exist with their full shape:**
  - `SettingChange` (with `fieldKey`), `PendingChange`, `SubmitResult` in `Model/PendingChange.swift`
  - `SettingKey` (`title`, `group`, `unit`, `defaultValue`, `range`, `step`, `looserWhen`, `clamp`), `SettingGroup`, `LooserWhen`
  - `Settings` (subscript get/set clamps), `AccessMode.title`
  - `HistoryKind` already has `changeScheduled`, `changeApplied`, `changeCanceled`, `appAdded`, `appRemoved`, `tamperDetected`
- **Already in place:**
  - `WakeUpPlanner` wakes at every pending `applyAt`.
  - `EngineEffect.uninstall` exists. `AppModel.refresh` currently ignores it (`case .uninstall: break`).
- **Tamper handling is done:**
  - `StateStore` (App) and `PersistedState.penalized` (Core, `Persistence/Penalty.swift`) set `tamperNoticeUntil`.
  - Only the panel banner is missing.
- **`AppModel`:**
  - `refresh`, `perform` (refresh before and after an intent), `saveNow`, `displayNow`, `monitor`, `enforcer`, `router`
  - `panelDidOpen` / `panelDidClose`, which use a `RepeatingUITimer`
- **`Enforcer.sweep()`** reconciles every running blocked process with the `.startupSweep` trigger. Apps without access are quit, with no gate.
- **`WindowRouter`:**
  - `showBooking()` and `showQuit()`, both built on `show(title:content:)`
  - The window is created at 380×300 with `[.titled, .closable]`, and a `willClose` observer forgets it.
- **`PopoverView`:** header `Text`, focus block, claim row, tokens row, `SessionsBlock`, today strip, DEV row, Quit button.
- **`AppDelegate`:** `applicationDidFinishLaunching`, `applicationWillTerminate`.

---

## File map for Run 4

| File | Change | Task |
|---|---|---|
| `Sources/MyTimeCore/Logic/SettingsPolicy.swift` | **new**: `SettingsPolicy`, `summary`, `submit`, `cancelPending`, `applyDuePending` | 1 |
| `Sources/MyTimeCore/Logic/EngineCore.swift` | step 3 apply-due, step 7 pruning, `didReset` | 1–2 |
| `Tests/MyTimeCoreTests/SettingsPolicyTests.swift` | **new** | 1 |
| `Sources/MyTimeCore/Logic/Pruning.swift` | **new**: `prune()` | 2 |
| `Sources/MyTimeCore/Logic/Constants.swift` | `weeklyRetentionWeeks` | 2 |
| `Sources/MyTimeCore/Logic/DurationFormat.swift` | `historyDay` | 2 |
| `Tests/MyTimeCoreTests/PruningTests.swift`, `HistoryFormatTests.swift` | **new** | 2 |
| `Sources/MyTimeApp/Engine/AppModel.swift` | `submit`, `cancelPending`, settings timer, `.uninstall` effect | 3 |
| `Sources/MyTimeApp/Engine/Installer.swift` | `uninstall()` | 3 |
| `Sources/MyTimeApp/AppDelegate.swift` | reopen opens Settings | 3 |
| `Sources/MyTimeApp/UI/PopoverView.swift` | header gear + pending capsule, tamper banner | 3 |
| `Sources/MyTimeApp/Engine/WindowRouter.swift` | `showSettings(tab:)`, window size parameter | 4 |
| `Sources/MyTimeApp/UI/Settings/SettingsView.swift` | **new**: header, clock note, `TabView` | 4 |
| `Sources/MyTimeApp/UI/Settings/GeneralSettingsTab.swift` | **new** | 4 |
| `Sources/MyTimeApp/UI/Settings/HistoryTab.swift` | **new** | 4 |
| `Sources/MyTimeApp/UI/Settings/SettingsAlerts.swift` | **new**: `NSAlert` helpers | 5 |
| `Sources/MyTimeApp/UI/Settings/BlockedAppsTab.swift` | **new** (toggles, remove, add) | 5 |
| `Sources/MyTimeApp/UI/Settings/PendingTab.swift` | **new** (list, cancel, uninstall) | 5 |
| `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md` | Run 4 sections | 6 |

---

### Task 1: Settings policy, submit, and apply-due

**Files:**
- Create: `Sources/MyTimeCore/Logic/SettingsPolicy.swift`, `Tests/MyTimeCoreTests/SettingsPolicyTests.swift`
- Modify: `Sources/MyTimeCore/Logic/EngineCore.swift`

**Interfaces:**
- Produces:

```swift
public enum SettingsPolicy {
    public static func isLoosening(_ change: SettingChange, settings: Settings) -> Bool
    public static func addAppProblem(bundleID: String?, path: String, ownBundleID: String?, apps: [BlockedApp]) -> String?
}
extension EngineCore {
    public func summary(of change: SettingChange, locale: Locale) -> String
    public mutating func submit(_ change: SettingChange, locale: Locale) -> SubmitResult
    public mutating func cancelPending(id: UUID)
    mutating func applyDuePending() -> [EngineEffect]   // update step 3
}
```

- [ ] **Step 1: Write the failing tests.** Create `Tests/MyTimeCoreTests/SettingsPolicyTests.swift` with exactly this content:

```swift
import XCTest

@testable import MyTimeCore

/// Settings changes and the loosening delay (spec §5.6). Release values: the delay is 24 h, and
/// "Session time per week" is 5 h. The engine starts on Monday 2026-09-14 at 10:00.
final class SettingsPolicyTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func submit(_ core: inout EngineCore, _ change: SettingChange) -> SubmitResult {
        core.submit(change, locale: locale)
    }

    private func notes() -> BlockedApp {
        BlockedApp(name: "Notes", bundleIDs: ["com.example.notes"], modes: [.quickLook])
    }

    func testLooseningDirection() {
        let (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        let settings = core.state.settings
        let discord = settings.apps[0]
        func loosens(_ change: SettingChange) -> Bool {
            SettingsPolicy.isLoosening(change, settings: settings)
        }
        XCTAssertTrue(loosens(.setNumber(key: .weeklyAllowanceSeconds, value: 28800)))
        XCTAssertFalse(loosens(.setNumber(key: .weeklyAllowanceSeconds, value: 14400)))
        XCTAssertTrue(loosens(.setNumber(key: .focusSecondsPerToken, value: 600)))
        XCTAssertFalse(loosens(.setNumber(key: .focusSecondsPerToken, value: 1200)))
        XCTAssertTrue(loosens(.setNumber(key: .dayStartHour, value: 3)))
        XCTAssertTrue(loosens(.setNumber(key: .dayStartHour, value: 5)))
        XCTAssertFalse(loosens(.setNumber(key: .dayStartHour, value: 4)))
        XCTAssertFalse(loosens(.addApp(notes())))
        XCTAssertTrue(loosens(.removeApp(id: discord.id)))
        XCTAssertFalse(loosens(.setMode(appID: discord.id, mode: .quickLook, enabled: false)))
        XCTAssertFalse(loosens(.setMode(appID: discord.id, mode: .quickLook, enabled: true)))
        var withoutQuickLook = settings
        withoutQuickLook.apps[0].modes = [.reply]
        XCTAssertTrue(
            SettingsPolicy.isLoosening(
                .setMode(appID: discord.id, mode: .quickLook, enabled: true), settings: withoutQuickLook))
        XCTAssertTrue(loosens(.uninstall))
    }

    func testTighteningAppliesImmediately() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        let result = submit(&core, .setNumber(key: .weeklyAllowanceSeconds, value: 14400))
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(core.setting(.weeklyAllowanceSeconds), 14400)
        XCTAssertTrue(core.state.pending.isEmpty)
        XCTAssertEqual(core.state.history.last?.kind, .changeApplied)
        XCTAssertEqual(core.state.history.last?.text, "Session time per week: 5h → 4h")
    }

    func testLooseningIsScheduledAfterTheDelay() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let result = submit(&core, .setNumber(key: .weeklyAllowanceSeconds, value: 28800))
        XCTAssertEqual(result, .scheduled(applyAt: date(2026, 9, 15, 10)))
        XCTAssertEqual(core.setting(.weeklyAllowanceSeconds), 18000)
        XCTAssertEqual(core.state.pending.count, 1)
        XCTAssertEqual(core.state.pending.first?.summary, "Session time per week: 5h → 8h")
        XCTAssertEqual(core.state.history.last?.kind, .changeScheduled)
        XCTAssertEqual(
            core.state.history.last?.text, "Scheduled: Session time per week: 5h → 8h · applies Tomorrow 10:00 AM")

        sim.advance(86400 - 1)  // Tuesday 9:59:59
        _ = core.update(sim.input)
        XCTAssertEqual(core.setting(.weeklyAllowanceSeconds), 18000)
        sim.advance(1)  // Tuesday 10:00
        _ = core.update(sim.input)
        XCTAssertEqual(core.setting(.weeklyAllowanceSeconds), 28800)
        XCTAssertTrue(core.state.pending.isEmpty)
        XCTAssertEqual(core.state.history.last?.kind, .changeApplied)
        XCTAssertEqual(core.state.history.last?.text, "Applied: Session time per week: 5h → 8h")
    }

    func testDueChangesApplyInApplyAtOrder() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let now = core.now
        core.state.pending = [
            PendingChange(
                createdAt: now, applyAt: now.addingTimeInterval(200),
                change: .setNumber(key: .replyPerDay, value: 7), summary: "second"),
            PendingChange(
                createdAt: now, applyAt: now.addingTimeInterval(100),
                change: .setNumber(key: .replyPerDay, value: 5), summary: "first"),
        ]
        sim.advance(300)
        _ = core.update(sim.input)
        XCTAssertEqual(core.setting(.replyPerDay), 7)
        XCTAssertEqual(core.state.history.suffix(2).map(\.text), ["Applied: first", "Applied: second"])
    }

    func testSameFieldSupersedesAndANoOpCancels() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        _ = submit(&core, .setNumber(key: .weeklyAllowanceSeconds, value: 28800))
        _ = submit(&core, .setNumber(key: .weeklyAllowanceSeconds, value: 36000))
        XCTAssertEqual(core.state.pending.count, 1)
        XCTAssertEqual(core.state.pending.first?.change, .setNumber(key: .weeklyAllowanceSeconds, value: 36000))
        let historyCount = core.state.history.count
        XCTAssertEqual(submit(&core, .setNumber(key: .weeklyAllowanceSeconds, value: 18000)), .noChange)
        XCTAssertTrue(core.state.pending.isEmpty)
        XCTAssertEqual(core.state.history.count, historyCount)
    }

    func testShorteningTheDelayWaitsOutTheCurrentDelay() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        XCTAssertEqual(
            submit(&core, .setNumber(key: .looseningDelaySeconds, value: 3600)),
            .scheduled(applyAt: date(2026, 9, 15, 10)))
        sim.advance(86400)
        _ = core.update(sim.input)
        XCTAssertEqual(core.setting(.looseningDelaySeconds), 3600)
        XCTAssertEqual(
            submit(&core, .setNumber(key: .replyPerDay, value: 5)),
            .scheduled(applyAt: date(2026, 9, 15, 11)))
    }

    func testValuesAreClampedToTheirRange() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        _ = submit(&core, .setNumber(key: .quickLookMaxTokens, value: 99))
        XCTAssertEqual(core.state.pending.first?.change, .setNumber(key: .quickLookMaxTokens, value: 10))
        XCTAssertEqual(core.state.pending.first?.summary, "Max tokens per quick look: 3 → 10")
        XCTAssertEqual(submit(&core, .setNumber(key: .gatePauseSeconds, value: 99)), .applied)
        XCTAssertEqual(core.setting(.gatePauseSeconds), 30)
    }

    func testAddingRemovingAndModes() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0]
        let app = notes()

        XCTAssertEqual(submit(&core, .addApp(app)), .applied)
        XCTAssertEqual(core.state.settings.apps.map(\.name), ["Discord", "Notes"])
        XCTAssertEqual(core.state.history.last?.kind, .appAdded)
        XCTAssertEqual(core.state.history.last?.text, "Add Notes")
        let duplicate = BlockedApp(name: "Notes 2", bundleIDs: ["com.other", "com.example.notes"], modes: [])
        XCTAssertEqual(submit(&core, .addApp(duplicate)), .noChange)

        XCTAssertEqual(submit(&core, .removeApp(id: app.id)), .scheduled(applyAt: date(2026, 9, 15, 10)))
        XCTAssertEqual(core.state.pending.last?.summary, "Remove Notes")
        XCTAssertEqual(submit(&core, .removeApp(id: UUID())), .noChange)

        XCTAssertEqual(submit(&core, .setMode(appID: discord.id, mode: .quickLook, enabled: false)), .applied)
        XCTAssertEqual(core.state.settings.apps[0].modes, [.reply, .booked])
        XCTAssertEqual(core.state.history.last?.text, "Turn off Quick look for Discord")
        XCTAssertEqual(
            submit(&core, .setMode(appID: discord.id, mode: .quickLook, enabled: true)),
            .scheduled(applyAt: date(2026, 9, 15, 10)))
        XCTAssertEqual(core.state.pending.last?.summary, "Turn on Quick look for Discord")
        XCTAssertEqual(submit(&core, .setMode(appID: UUID(), mode: .reply, enabled: false)), .noChange)
    }

    func testAppliedRemovalDropsLaterChangesForThatApp() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let app = notes()
        _ = submit(&core, .addApp(app))
        _ = submit(&core, .removeApp(id: app.id))
        sim.advance(60)
        _ = core.update(sim.input)
        _ = submit(&core, .setMode(appID: app.id, mode: .reply, enabled: true))
        XCTAssertEqual(core.state.pending.count, 2)

        sim.advance(86400)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.settings.apps.map(\.name), ["Discord"])
        XCTAssertTrue(core.state.pending.isEmpty)
        XCTAssertEqual(core.state.history.last?.kind, .appRemoved)
        XCTAssertEqual(core.state.history.last?.text, "Applied: Remove Notes")
    }

    func testCancelingAPendingChange() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        _ = submit(&core, .setNumber(key: .replyPerDay, value: 5))
        core.cancelPending(id: try XCTUnwrap(core.state.pending.first).id)
        XCTAssertTrue(core.state.pending.isEmpty)
        XCTAssertEqual(core.state.history.last?.kind, .changeCanceled)
        XCTAssertEqual(core.state.history.last?.text, "Canceled: Reply mode uses per day: 3 → 5")
        core.cancelPending(id: UUID())
        XCTAssertEqual(core.state.history.last?.kind, .changeCanceled)
        sim.advance(2 * 86400)
        _ = core.update(sim.input)
        XCTAssertEqual(core.setting(.replyPerDay), 3)
    }

    func testUninstallEmitsItsEffectWhenDue() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        XCTAssertEqual(submit(&core, .uninstall), .scheduled(applyAt: date(2026, 9, 15, 10)))
        XCTAssertEqual(core.state.pending.first?.summary, "Uninstall myTime")
        sim.advance(86400 - 1)
        XCTAssertFalse(core.update(sim.input).effects.contains(.uninstall))
        sim.advance(1)
        XCTAssertEqual(core.update(sim.input).effects, [.uninstall])
        XCTAssertEqual(core.state.history.last?.text, "Applied: Uninstall myTime")
        sim.advance(60)
        XCTAssertEqual(core.update(sim.input).effects, [])
    }

    func testChangingTheDayStartDoesNotClearTokens() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        XCTAssertEqual(
            submit(&core, .setNumber(key: .dayStartHour, value: 11)),
            .scheduled(applyAt: date(2026, 9, 15, 10)))
        XCTAssertEqual(core.state.pending.first?.summary, "Day starts at: 4:00 AM → 11:00 AM")
        sim.advance(86400 - 1)  // Tuesday 9:59:59, after Tuesday's 4 AM reset
        _ = core.update(sim.input)
        core.state.tokens = 2
        sim.advance(1)  // Tuesday 10:00: the change applies; with 11 AM, it's still Monday's day
        _ = core.update(sim.input)
        XCTAssertEqual(core.setting(.dayStartHour), 11)
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 2)
        sim.advance(3600)  // Tuesday 11:00, the new day start
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 0)
    }

    func testAddAppProblems() {
        let (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        let apps = core.state.settings.apps
        func problem(_ bundleID: String?, _ path: String) -> String? {
            SettingsPolicy.addAppProblem(bundleID: bundleID, path: path, ownBundleID: "local.mytime", apps: apps)
        }
        XCTAssertNil(problem("com.apple.TextEdit", "/Applications/TextEdit.app"))
        XCTAssertEqual(problem(nil, "/Applications/Odd.app"), "That app can't be blocked.")
        XCTAssertEqual(problem("local.mytime", "/Applications/myTime.app"), "myTime can't block itself.")
        XCTAssertEqual(
            problem("com.apple.Safari", "/System/Applications/Safari.app"), "System apps can't be blocked.")
        XCTAssertEqual(problem("com.hnc.DiscordPTB", "/Applications/Discord PTB.app"), "Discord is already blocked.")
    }
}
```

- [ ] **Step 2: Run them to see them fail.** `swift test --filter SettingsPolicyTests` → compile errors for the missing API.

- [ ] **Step 3: `SettingsPolicy`** (spec §5.6)
  - **`isLoosening`:**
    - `.setNumber`: compare `key.clamp(value)` with `settings[key]` by `looserWhen`: `.higher` → greater, `.lower` → less, `.anyChange` → different.
    - `.addApp` → `false`; `.removeApp` → `true`; `.uninstall` → `true`.
    - `.setMode(appID, mode, enabled)` → `true` only if `enabled` and the app exists without that mode.
  - **`addAppProblem`:** the four checks in the spec's order, returning the exact messages, otherwise `nil`.

- [ ] **Step 4: `summary(of:locale:)`** uses the current settings:
  - `.setNumber` → `"\(key.title): \(old) → \(new)"`, both via `DurationFormat.setting(key, value, locale:)`, with `new` clamped
  - `"Add \(app.name)"`, `"Remove \(name)"`
  - `"Turn on \(mode.title) for \(name)"` / `"Turn off …"`
  - `"Uninstall myTime"`
  - For a missing app, use `"app"` as the name. Only `submit` calls it, after the no-op check.

- [ ] **Step 5: `submit(_:locale:)`**, exactly the spec pseudocode:
  1. Clamp `.setNumber`.
  2. Remove pending items with the same `fieldKey`.
  3. No-op → `.noChange`. A no-op is:
     - the same number
     - `setMode` on a missing app, or a mode already in that state
     - `addApp` when any existing app shares any bundle ID
     - `removeApp` of a missing app
  4. Build the summary.
  5. **If loosening:**
     - `applyAt = now + setting(.looseningDelaySeconds)`
     - append a `PendingChange`
     - history `.changeScheduled` `"Scheduled: \(summary) · applies \(DurationFormat.sessionStart(applyAt, now: now, timeZone: timeZone, locale: locale))"`
     - return `.scheduled(applyAt:)`
  6. **Otherwise:**
     - apply the change
     - history `.appAdded` for `.addApp`, else `.changeApplied`, with text `summary`
     - return `.applied`

- [ ] **Step 6: Applying a change** (a private `apply(_:)` used by both paths)
  - `.setNumber` → `state.settings[key] = value`. If `key == .dayStartHour`, also set `state.tokensDayKey = CalendarKeys.dayKey(now, dayStartHour: <new hour>, timeZone: timeZone)`.
  - `.addApp` → append; `.removeApp` → remove by id.
  - `.setMode` → insert or remove the mode (ignore a missing app).
  - `.uninstall` → nothing (the effect does the work).

- [ ] **Step 7: `cancelPending(id:)`** — if found, remove it and record `.changeCanceled` `"Canceled: \(summary)"`. Unknown ids do nothing.

- [ ] **Step 8: `applyDuePending()`**
  1. Copy `now` into a local first; `removeAll` closures that read `self.now` while mutating `state` violate exclusivity.
  2. Take the items with `now >= applyAt`, sorted by `applyAt`, and remove them from `state.pending`.
  3. For each item:
     - If the target app is missing (`.removeApp`, `.setMode`), skip it silently.
     - Otherwise apply it and record `"Applied: \(summary)"`, with kind `.appRemoved` for `.removeApp` and `.changeApplied` for everything else.
     - For `.uninstall`, append `.uninstall` to the returned effects.

- [ ] **Step 9: `update` step 3.** In `EngineCore.update`, right after the daily reset, start the effect list with `var effects = applyDuePending()`. Then add the grant-expiry effects and the booking-transition effects, skipping any already in the list (keep the existing de-duplication).

- [ ] **Step 10: Run the tests.** `swift test --filter SettingsPolicyTests` → 13 tests pass. Then `swift test` → all pass.

- [ ] **Step 11: Checkpoint.** Do not commit.

---

### Task 2: Pruning and history labels

**Files:**
- Create: `Sources/MyTimeCore/Logic/Pruning.swift`, `Tests/MyTimeCoreTests/PruningTests.swift`, `Tests/MyTimeCoreTests/HistoryFormatTests.swift`
- Modify: `Sources/MyTimeCore/Logic/EngineCore.swift`, `Sources/MyTimeCore/Logic/Constants.swift`, `Sources/MyTimeCore/Logic/DurationFormat.swift`

**Interfaces:**
- Produces:

```swift
extension EngineCore { mutating func prune() }   // update step 7
public enum DurationFormat { public static func historyDay(_ date: Date, now: Date, timeZone: TimeZone, locale: Locale) -> String }
public enum Constants { public static let weeklyRetentionWeeks = 10 }   // shared by release and DEV
```

- [ ] **Step 1: Write the failing tests.** Create `Tests/MyTimeCoreTests/PruningTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

/// Old data is pruned only in the update where the daily reset runs (spec §8.2, update step 7).
/// The reset in this test is Tuesday 2026-09-15 at 4:00 AM, so the 14-day booking cutoff is Sep 1 at 4:00 AM.
final class PruningTests: XCTestCase {
    private func booking(start: Date, hours: Double = 0.5, canceledAt: Date? = nil) -> Booking {
        Booking(
            start: start, durationSeconds: Int(hours * 3600), createdAt: start.addingTimeInterval(-86400),
            canceledAt: canceledAt)
    }

    func testPruningRunsWithTheDailyResetAndKeepsRecentData() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        core.state.daily = ["2026-07-16": DailyStats(), "2026-07-17": DailyStats(), "2026-09-14": DailyStats()]
        core.state.weekly = ["2026-W27": WeeklyStats(), "2026-W28": WeeklyStats(), "2026-W38": WeeklyStats()]
        let canceledLongAgo = booking(start: date(2026, 9, 3, 12), canceledAt: date(2026, 8, 31, 12))
        let canceledRecently = booking(start: date(2026, 9, 3, 12), canceledAt: date(2026, 9, 2, 12))
        let endedLongAgo = booking(start: date(2026, 8, 31, 22))  // ends Aug 31, 10:30 PM
        let endedAfterCutoff = booking(start: date(2026, 8, 31, 22), hours: 8)  // ends Sep 1, 6:00 AM
        let endedRecently = booking(start: date(2026, 9, 2, 22))
        let upcoming = booking(start: date(2026, 9, 16, 20))
        core.state.bookings = [
            canceledLongAgo, canceledRecently, endedLongAgo, endedAfterCutoff, endedRecently, upcoming,
        ]
        core.state.history = (0..<510).map { HistoryEvent(date: core.now, kind: .backedOff, text: "\($0)") }
        let before = core.state

        sim.advance(17 * 3600 + 59 * 60 + 59)  // Tuesday 3:59:59, no reset yet
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.daily, before.daily)
        XCTAssertEqual(core.state.weekly, before.weekly)
        XCTAssertEqual(core.state.bookings, before.bookings)
        XCTAssertEqual(core.state.history.count, 510)

        sim.advance(1)  // Tuesday 4:00, the reset
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.daily.keys.sorted(), ["2026-07-17", "2026-09-14"])
        XCTAssertEqual(core.state.weekly.keys.sorted(), ["2026-W28", "2026-W38"])
        XCTAssertEqual(
            core.state.bookings.map(\.id), [canceledRecently.id, endedAfterCutoff.id, endedRecently.id, upcoming.id])
        XCTAssertEqual(core.state.history.count, 500)
        XCTAssertEqual(core.state.history.first?.text, "10")
    }
}
```

and `Tests/MyTimeCoreTests/HistoryFormatTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

/// Day headings in the Settings History tab (spec §7.9), by calendar day.
final class HistoryFormatTests: XCTestCase {
    func testHistoryDayLabels() {
        let now = date(2026, 9, 14, 10)  // Monday
        func label(_ day: Date) -> String {
            DurationFormat.historyDay(day, now: now, timeZone: testTZ, locale: Locale(identifier: "en_US"))
        }
        XCTAssertEqual(label(date(2026, 9, 14, 0, 5)), "Today")
        XCTAssertEqual(label(date(2026, 9, 13, 23, 55)), "Yesterday")
        XCTAssertEqual(label(date(2026, 9, 10, 9)), "Thursday, Sep 10")
    }
}
```

- [ ] **Step 2: Run them to see them fail.** `swift test --filter "PruningTests|HistoryFormatTests"` → compile errors.

- [ ] **Step 3: `Constants.weeklyRetentionWeeks = 10`**, next to `bookingRetentionDays`, outside the `#if`.

- [ ] **Step 4: `prune()`** (spec §8.2). Copy `now` into a local before the `removeAll`.
  - `daily`: keep keys `>= CalendarKeys.dayKey(now − dailyRetentionDays × 86400, dayStartHour:, timeZone:)`.
  - `weekly`: keep keys `>= CalendarKeys.weekKey(now − weeklyRetentionWeeks × 7 × 86400, …)`.
  - `bookings`: with `cutoff = now − bookingRetentionDays × 86400`:
    - remove a canceled booking if `canceledAt < cutoff`
    - remove a booking with `isFinished(at: now)` if `(endedAt ?? end) < cutoff`
  - `history`: keep the last `Constants.historyCap` events.

- [ ] **Step 5: `update` step 7.** Capture `let didReset = state.tokensDayKey != key` before the reset block and use it as the block's condition. After the booking transitions, `if didReset { prune() }`.

- [ ] **Step 6: `historyDay`.** Use calendar days in `timeZone` (gregorian `startOfDay`, like `dayLabel`):
  - offset 0 → `"Today"`
  - offset −1 → `"Yesterday"`
  - otherwise a `DateFormatter` with `locale`, `timeZone`, and `setLocalizedDateFormatFromTemplate("EEEEMMMd")`

- [ ] **Step 7: Run the tests.** `swift test` → 122 tests, 0 failures.

- [ ] **Step 8: Checkpoint.** Do not commit.

---

### Task 3: App wiring — intents, uninstall, reopen, panel header and banner

**Files:**
- Modify: `Sources/MyTimeApp/Engine/AppModel.swift`, `Sources/MyTimeApp/Engine/Installer.swift`, `Sources/MyTimeApp/AppDelegate.swift`, `Sources/MyTimeApp/UI/PopoverView.swift`

**Interfaces:**
- Consumes: Task 1's `submit`, `cancelPending`; `WindowRouter.showSettings(tab:)` from Task 4. Add a stub in this task if you build before Task 4.
- Produces:

```swift
// AppModel
@discardableResult func submit(_ change: SettingChange) -> SubmitResult   // perform { $0.submit(change, locale: .current) }, then enforcer.sweep()
func cancelPending(id: UUID)                                              // perform { $0.cancelPending(id:) }
func settingsDidOpen()    // starts a RepeatingUITimer: 1 s, refresh(.panel)
func settingsDidClose()   // stops it
// Installer
static func uninstall() -> Never   // trash Bundle.main.bundleURL (ignore errors), then stopAgent()
```

- [ ] **Step 1: `AppModel` intents.** `submit` returns the result, and after the `perform` calls `enforcer.sweep()`, so an added app or a lost mode closes running apps with no gate (§6.8). `cancelPending` is a plain `perform`.

- [ ] **Step 2: Settings timer.** Add `@ObservationIgnored private let settingsTimer = RepeatingUITimer()`. `settingsDidOpen()` starts it (`interval: 1`, `refresh(.panel)`); `settingsDidClose()` stops it. These saves are throttled already, because `.panel` counts as a UI tick.

- [ ] **Step 3: Uninstall effect.** In `refresh`, replace `case .uninstall: break` with `saveNow()` then `Installer.uninstall()`.

- [ ] **Step 4: `Installer.uninstall()`** (§3.2): `try? FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)`, then `stopAgent()`.

- [ ] **Step 5: Reopen.** In `AppDelegate`:

```swift
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.router.showSettings(tab: .general)
        return false
    }
```

- [ ] **Step 6: Panel header and tamper banner** (§7.2 items 1–2)
  - **Header row:** replace the header `Text` with an `HStack`:
    - the title
    - `Spacer()`
    - if `core.state.pending.count > 0`: a small capsule button `"\(count) pending"` → `model.router.showSettings(tab: .pending)`, e.g. `.buttonStyle(.bordered)`, `.controlSize(.small)`, `.buttonBorderShape(.capsule)`
    - a borderless gear button (`Image(systemName: "gearshape")`, accessibility label "Settings") → `model.router.showSettings(tab: .general)`
  - **Tamper banner:** right below the header, if `let until = core.state.tamperNoticeUntil, core.now < until`, show `Text("Saved data was edited outside myTime, so balances were reset.")` in secondary style.

- [ ] **Step 7: Build.** `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`.

- [ ] **Step 8: Checkpoint.** Do not commit.

---

### Task 4: Settings window — shell, General, History

**Files:**
- Create: `Sources/MyTimeApp/UI/Settings/SettingsView.swift`, `GeneralSettingsTab.swift`, `HistoryTab.swift`
- Modify: `Sources/MyTimeApp/Engine/WindowRouter.swift`

**Interfaces:**
- Produces:

```swift
enum SettingsTab: Hashable { case general, apps, pending, history }
@MainActor @Observable final class SettingsNavigation { var tab: SettingsTab = .general }
// WindowRouter
func showSettings(tab: SettingsTab)
struct SettingsView: View { let model: AppModel; @Bindable var navigation: SettingsNavigation }   // @Bindable for TabView(selection:)
```

- [ ] **Step 1: `WindowRouter.showSettings(tab:)`**
  - Give `show(title:content:)` a `size: NSSize` parameter. Booking and Quit pass 380×300, Settings passes 560×520.
  - The router owns one `SettingsNavigation`. `showSettings(tab:)`:
    1. `model.refresh(.intent)`
    2. set `navigation.tab = tab`
    3. `show(title: "myTime Settings", size: NSSize(width: 560, height: 520)) { SettingsView(model: model, navigation: navigation) }`
  - An existing window is just brought forward, and the tab change still applies.
  - Call `model.settingsDidOpen()` when the Settings window is created, and `model.settingsDidClose()` in its `willClose` handler (only for that title).

- [ ] **Step 2: `SettingsView`** (§7.9), a `VStack(alignment: .leading, spacing: 12)` with 20 pt padding, framed at 560×520:
  - Header (secondary): `"Changes that make myTime stricter apply right away. Changes that loosen it apply after \(DurationFormat.short(Double(core.setting(.looseningDelaySeconds))))."`
  - If `abs(core.state.clock.offsetSeconds) > 120`, the secondary line `"Your Mac's clock was changed. myTime is ignoring the change (\(DurationFormat.short(abs(core.state.clock.offsetSeconds))))."`
  - `TabView(selection: $navigation.tab)` with four tabs, `.tabItem { Text(…) }` and `.tag(…)`: "General" `GeneralSettingsTab`, "Blocked Apps" `BlockedAppsTab`, "Pending" `PendingTab`, "History" `HistoryTab`.
  - Until Task 5, the Blocked Apps and Pending tabs can be `Text("")` placeholders.

- [ ] **Step 3: `GeneralSettingsTab`**
  - **Draft:** `@State private var draft: [SettingKey: Int] = [:]`, filled in `.onAppear` from `core.setting(key)` for every `SettingKey.allCases`. This is view state, not persisted, so an enum key is fine.
  - **Form:** `Form` with `.formStyle(.grouped)`, containing `ForEach(SettingGroup.allCases)` → `Section(group.rawValue)` → for each key in that group:
    - `Stepper(value: binding(key), in: key.range, step: key.step)` labeled by `HStack { Text(key.title); Spacer(); Text(DurationFormat.setting(key, draft[key] ?? core.setting(key), locale: .current)).monospacedDigit() }`
    - Under `.dayStartHour`, the caption `"Changing this always waits \(DurationFormat.short(Double(core.setting(.looseningDelaySeconds))))."`
  - **Bottom bar:** `HStack { Spacer(); Button("Revert"); Button("Apply Changes") }`. Revert refills the draft. Apply Changes is disabled unless some `draft[key] != core.setting(key)`.
  - **Apply**, for each changed key in `SettingKey.allCases` order:
    1. `let change = SettingChange.setNumber(key: key, value: draft[key]!)`
    2. `let text = model.core.summary(of: change, locale: .current)`, taken **before** submitting
    3. `switch model.submit(change)`:
       - `.applied` → line `"Applied now: \(text)"`
       - `.scheduled(let at)` → line `"Applies \(DurationFormat.sessionStart(at, now: model.displayNow, timeZone: .current, locale: .current)): \(text)"`
       - `.noChange` → no line
    4. After the loop, refill the draft and show an alert titled "Settings updated" with the lines joined by `"\n"` (SwiftUI `.alert` with a message, or `SettingsAlerts.inform` from Task 5).

- [ ] **Step 4: `HistoryTab`**
  - Events: `core.state.history` with `date >= model.displayNow − 7 × 86400`, newest first.
  - Group by `Calendar.current.startOfDay(for: event.date)`, newest day first.
  - `List`:
    - one `Section(DurationFormat.historyDay(day, now: model.displayNow, timeZone: .current, locale: .current))` per day
    - rows: `HStack(alignment: .firstTextBaseline) { Text(DurationFormat.timeOfDay(event.date, timeZone: .current, locale: .current)).monospacedDigit().foregroundStyle(.secondary).frame(width: 72, alignment: .leading); Text(event.text) }`
  - If there are no events, show a secondary "No history yet." centered. This is the one allowed empty-state line; record it in the notes.

- [ ] **Step 5: Build.** `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`.

- [ ] **Step 6: Checkpoint.** Do not commit.

---

### Task 5: Settings window — Blocked Apps and Pending

**Files:**
- Create: `Sources/MyTimeApp/UI/Settings/SettingsAlerts.swift`, `BlockedAppsTab.swift`, `PendingTab.swift`
- Modify: `Sources/MyTimeApp/UI/Settings/SettingsView.swift` (replace the placeholders)

**Interfaces:**
- Produces:

```swift
@MainActor enum SettingsAlerts {
    static func confirm(title: String, message: String, confirmTitle: String) -> Bool   // NSAlert, runModal, buttons [confirmTitle, "Cancel"]
    static func inform(title: String, message: String)                               // NSAlert, one "OK" button
}
```

- [ ] **Step 1: `SettingsAlerts`.** Wrap `NSAlert` (`messageText = title`, `informativeText = message`) and call `runModal()`. For `confirm`, add `confirmTitle` first, then "Cancel", and return `response == .alertFirstButtonReturn`.

- [ ] **Step 2: `BlockedAppsTab` rows** (§7.9)
  - A `List` over `core.state.settings.apps`.
  - Each row is an `HStack`:
    - the icon, 24 pt: `NSWorkspace.shared.icon(forFile:)` of the first bundle ID that resolves via `urlForApplication(withBundleIdentifier:)`, otherwise `NSWorkspace.shared.icon(for: .application)`
    - the name
    - `Spacer()`
    - three toggles in `AccessMode.allCases` order, titled `mode.title` (`.toggleStyle(.checkbox)`)
    - the remove control
  - Helper: `pending(_ fieldKey: String) -> PendingChange?` = `core.state.pending.first { $0.change.fieldKey == fieldKey }`.
  - **Toggle binding.** `get` is `app.modes.contains(mode)`. `set(newValue)`:
    - If `newValue`, ask `SettingsAlerts.confirm(title: "This loosens myTime", message: "It will apply \(when).", confirmTitle: "Schedule")`, where `when = sessionStart(displayNow + looseningDelaySeconds)`. On confirm, `model.submit(.setMode(appID:mode:enabled: true))`.
    - If `!newValue`, `model.submit(.setMode(…, enabled: false))` immediately.
  - **Clock badge:** if `pending(SettingChange.setMode(appID: app.id, mode: mode, enabled: true).fieldKey)` exists, show `Image(systemName: "clock")` next to the toggle with `.help("On \(sessionStart(applyAt))")`.
  - **Remove:**
    - If `pending(SettingChange.removeApp(id: app.id).fieldKey)` exists, show the secondary text `"Removal \(sessionStart(applyAt))"`.
    - Otherwise show `Button("Remove…")`, which runs the same loosening confirm and then `model.submit(.removeApp(id: app.id))`.

- [ ] **Step 3: Add App…** (a button under the list), all on the main thread:
  1. **Pick.** `NSOpenPanel`:
     - `allowedContentTypes = [.application]` (`import UniformTypeIdentifiers`)
     - `directoryURL = URL(fileURLWithPath: "/Applications")`
     - `canChooseDirectories = false`, `allowsMultipleSelection = false`
     - Run it with `runModal()`; return unless `.OK`.
  2. **Read.** `let bundleID = Bundle(url: url)?.bundleIdentifier`.
  3. **Check.** If `SettingsPolicy.addAppProblem(bundleID: bundleID, path: url.path, ownBundleID: Bundle.main.bundleIdentifier, apps: core.state.settings.apps)` returns a message, call `SettingsAlerts.inform(title: message, message: "")` and stop.
  4. **Build the entry.** `let name = url.deletingPathExtension().lastPathComponent`.
  5. **Running check.** If `NSWorkspace.shared.runningApplications` contains a `.regular` app with that bundle ID, `confirm(title: "\(name) is running and will be closed.", message: "", confirmTitle: "Add")` must return true.
  6. **Add.** `model.submit(.addApp(BlockedApp(name: name, bundleIDs: [bundleID!], modes: [.quickLook, .reply, .booked])))`. `submit` runs the sweep, which closes it.

- [ ] **Step 4: `PendingTab`**
  - **List or empty state.** If `core.state.pending` is empty, show secondary "No pending changes.". Otherwise a `List` of pending items sorted by `applyAt`, each row:
    - `VStack(alignment: .leading) { Text(summary); Text("Applies in \(DurationFormat.short(applyAt.timeIntervalSince(model.displayNow)))").foregroundStyle(.secondary) }`
    - `Spacer()`
    - `Button("Cancel") { model.cancelPending(id:) }`
  - **Uninstall.** At the bottom, `Button("Uninstall myTime…", role: .destructive)`. It calls `SettingsAlerts.confirm(title: "myTime will uninstall itself in \(DurationFormat.short(Double(core.setting(.looseningDelaySeconds)))). You can cancel it here until then.", message: "", confirmTitle: "Schedule")`, then `model.submit(.uninstall)` on confirm.

- [ ] **Step 5: Build.** `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`.

- [ ] **Step 6: Checkpoint.** Do not commit.

---

### Task 6: Docs and final verification

**Files:**
- Modify: `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md`

- [ ] **Step 1:** Append `## Run 4` to `docs/MANUAL_TESTS.md` with spec §11.2 steps 20–25 verbatim, followed by the line "Then re-run steps 1–7 against a release build (`scripts/build.sh`)."

- [ ] **Step 2:** Append `## Run 4` to `IMPLEMENTATION_NOTES.md` with `### Deviations` (or "None."), `### Not verified`, and `### Commands run`.

- [ ] **Step 3: Format and verify**

```bash
swift format --in-place --recursive Sources Tests
swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test && swift build -c release --arch arm64 -Xswiftc -DDEV_TIMESCALE
```

Expected: every build prints `Build complete!`, and the tests report 122 tests with 0 failures. Paste the summary line into the notes.

- [ ] **Step 4: Self-check before replying.** Confirm each item in your reply:
  - [ ] The three plan test files exist, with the exact test method names from this plan.
  - [ ] No code line in `Sources/` or `Tests/` exceeds ~130 characters (long comments or string literals excepted).
  - [ ] No file in `Sources/` exceeds ~300 lines.
  - [ ] No UI path changes `state.settings` directly. Every change goes through `model.submit`.
  - [ ] The only new repeating timer is the Settings refresh, and it stops when the window closes.
  - [ ] Every behavior change from the spec is listed in the notes.

- [ ] **Step 5: Stop.** Don't commit. Reply with what you built, the test count, and every deviation.

---

## Self-review record (reviewer)

**Spec coverage for Run 4 (§12):**

| Spec item | Task |
|---|---|
| `SettingsPolicy` (loosening, submit, supersede, clamp, summaries, history) | 1 |
| Apply-due (update step 3) and the `.uninstall` effect | 1 |
| Pruning (update step 7) | 2 |
| History headings | 2 (core), 4 (tab) |
| `Installer.uninstall`, reopen → Settings, settings intents + sweep (§6.8) | 3 |
| Pending capsule, tamper banner | 3 |
| Settings window: header, clock-change note, General draft/apply, History | 4 |
| Blocked Apps (toggles, alerts, badges, remove, add with checks), Pending with uninstall | 5 |
| Tests: SettingsPolicy, pruning, history labels | 1–2 |
| Manual steps 20–25, then release re-run of 1–7 | 6 |

**Test validation:** every test in this plan was run against a reference implementation written straight from spec §5.6 and §8.2 in a scratch copy (not committed). All 122 tests pass together (107 existing + 15 new). As a mutation check, 25 deliberate rule breaks were tried, among them swapped loosening directions, a one-way day-start check, mode-on always loosening, no clamping, no superseding, a duplicate check on the first bundle ID only, the new delay used when shortening the delay, unsorted or strict-`>` apply-due, due changes for removed apps not dropped, wrong history kinds, no uninstall effect, the day-start change clearing tokens, cancel without history, a scheduled line without the day, no `/System/` check, pruning on every update, off-by-one day and week cutoffs, canceled bookings kept, bookings pruned by start instead of end, no history cap, and "Yesterday" in the wrong direction. Every one makes at least one plan test fail. If a plan test fails on your implementation, the implementation diverges from the spec.

**Design decisions made while planning (now in spec revision 5):**
- `submit` and `summary` take a `Locale` because summaries format hours ("4:00 AM") and Core never reads `Locale.current`.
- Scheduled and pending times use `sessionStart` ("Tomorrow 10:00 AM") everywhere, from history lines to alerts, badges, and the removal note.
- **Day start change:** applying one sets `tokensDayKey` under the new hour. The change itself never clears tokens; the next reset comes at the new day start.
- **Superseding and no-ops:**
  - Replacing a pending item or cancelling it with a no-op adds no history.
  - `setMode` on a missing app is a no-op.
  - Due changes whose app is gone are dropped silently.
- **Sweep and uninstall:**
  - Every submitted change runs `Enforcer.sweep()`.
  - Uninstall trashes the app bundle, then uses the same shutdown as Quit.
- **Settings window:**
  - A 1 s refresh runs only while it's open, like the panel.
  - The add-app checks live in Core (`SettingsPolicy.addAppProblem`) so they're tested.
