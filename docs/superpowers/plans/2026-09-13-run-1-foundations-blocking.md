# myTime Run 1 — Foundations, Blocking, Gate, Quick Look — Implementation Plan

> **For the implementing agent (Codex):** Work through the tasks **in order**. Steps use checkbox (`- [ ]`) syntax for tracking. Read `AGENTS.md` first. **Do not commit**; the reviewer commits after review.

**Goal:** A working menu-bar app that stays running, recognizes Discord being opened, hides it behind a gate with a 5-second pause, lets the user spend tokens on a 30-second quick look with a countdown pill, and quits Discord when time runs out. Tokens come from a DEV button in this run; earning arrives in Run 2.

**Architecture:**
- `MyTimeCore` is a pure-Swift library holding all rules and state. It is event-driven: `update(input)` returns side effects plus the next wake-up time.
- `MyTimeApp` is thin AppKit/SwiftUI glue. It turns macOS notifications into `refresh` calls, applies effects (hide/terminate/overlays), and schedules a single one-shot timer.
- There is no polling.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftPM, XCTest, AppKit, SwiftUI, Observation, CryptoKit. macOS 14+, arm64.

**Spec:** `docs/superpowers/specs/2026-09-13-mytime-design.md` (revision 2). Sections are cited as §N. The spec holds the rules; this plan holds the order of work, exact interfaces, tests, and platform snippets that were **verified to compile and run on the target Mac**. Ordinary implementation code is yours to write.

---

## How to work

### Where you have latitude (and where you don't)

**You are free to decide:**
- internal implementation code, private helpers, and private type names
- how SwiftUI views are composed and styled within §9
- splitting a file that grows past ~300 lines
- fixing a snippet in this plan that doesn't compile or behave correctly on the real OS

**You must keep:**
- every behavior, number, and piece of user-facing copy in the spec
- every **public** name and signature listed under "Interfaces" (later runs and the reviewer depend on them)
- every test in this plan, unweakened: fix the code, not the test
- the hard rules in spec §13

**If you believe something in the spec or plan is wrong:** implement the closest behavior that works and record it under `## Run 1` in `IMPLEMENTATION_NOTES.md` (what, why, and what you did instead). Unrecorded deviations will be treated as bugs.

### Environment

- Work in the local repo on the Mac (Codex CLI or app). A Linux cloud sandbox **cannot** build this project, because it needs AppKit.
- Run only `swift build …` and `swift test`. **Do not run** `scripts/build.sh`, `scripts/uninstall.sh`, or `launchctl`, since they install into the user's home folder. The reviewer installs and runs the manual tests.
- If the sandbox blocks `swift build` or `swift test` (for example, module cache writes), stop and ask for permission rather than working around it.
- Tests run without `DEV_TIMESCALE`, so they see **release** values from §8. DEV-only code is compiled separately with `swift build -Xswiftc -DDEV_TIMESCALE`.

---

## Global Constraints

- `// swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, `swiftLanguageModes: [.v5]`.
- Frameworks: Foundation, AppKit, SwiftUI, Observation, CryptoKit, CoreGraphics, UniformTypeIdentifiers only. No third-party packages.
- `MyTimeCore` imports only Foundation and CryptoKit. It never calls `Date()`, never reads clocks or `TimeZone.current`, and never imports AppKit. Time, time zone, and system readings come in as parameters or stored properties.
- Every Core type, property, method, and init used outside the module is `public`, with an **explicit `public init`**. Memberwise inits are not public.
- Persisted dictionaries use `String` keys.
- JSON: `dateEncodingStrategy = .secondsSince1970`, `outputFormatting = [.sortedKeys]`.
- No polling. Repeating timers only while their UI is visible (§3.6). Every `Timer` sets `tolerance`.
- UI and engine classes are `@MainActor`. Closures delivered by `Timer` or by `NotificationCenter` on `.main` must hop in with `MainActor.assumeIsolated { … }`.
- Not allowed: UserNotifications, AX APIs, AppleScript, SMAppService, network, sandbox, entitlements, `NSAppSleepDisabled`, SwiftUI `Settings`/`Window` scenes, `@main`.
- Copy and tone come from the spec verbatim: calm, no exclamation marks, no red, no sounds.
- Blocked processes match by **exact** bundle ID **and** `activationPolicy == .regular`.
- Bundle ID `local.mytime.app`; LaunchAgent label `local.mytime.agent`.

---

## File map for Run 1

| File | Responsibility | Task |
|---|---|---|
| `Package.swift`, `Packaging/Info.plist`, `scripts/build.sh`, `scripts/uninstall.sh` | Package, bundle metadata, install helpers (§3.3, §10) | 1 |
| `Sources/MyTimeCore/Logic/Constants.swift` | Non-configurable constants with DEV variants (§8.2) | 2 |
| `Sources/MyTimeCore/Model/SettingKey.swift` | Configurable settings table (§8.1) | 2 |
| `Sources/MyTimeCore/Logic/DurationFormat.swift` | Human-readable durations | 2 |
| `Sources/MyTimeCore/Logic/TrustedClock.swift` | `TrustedClockState` + clock-jump correction (§5.1) | 3 |
| `Sources/MyTimeCore/Logic/CalendarKeys.swift` | Day/week keys and boundaries (§5.1) | 3 |
| `Sources/MyTimeCore/Model/` Settings, BlockedApp, AccessGrant, Booking, Stats, HistoryEvent, PendingChange, PersistedState, EngineTypes | Data model (§4) | 4 |
| `Sources/MyTimeCore/Logic/EngineError.swift` | Errors + user messages (§7.10) | 4 |
| `Sources/MyTimeCore/Persistence/JSONCoding.swift` | Shared encoder/decoder | 4 |
| `Sources/MyTimeCore/Persistence/StateCodec.swift`, `Penalty.swift` | HMAC envelope, penalized state (§5.7) | 5 |
| `Sources/MyTimeCore/Logic/EnforcementPolicy.swift` | Pure decision table (§5.8) | 6 |
| `Sources/MyTimeCore/Logic/WakeUpPlanner.swift` | Next wake-up (§5.9) | 6 |
| `Sources/MyTimeCore/Logic/EngineCore.swift` | Façade: start/update, daily reset, grants, queries, DEV helpers | 7 |
| `Sources/MyTimeApp/Engine/SystemProbe.swift` | Clocks, boot ID, idle, lock | 8 |
| `Sources/MyTimeApp/Engine/StateStore.swift` | Load/save/sentinel/tamper | 8 |
| `Sources/MyTimeApp/Engine/Installer.swift` | LaunchAgent install + self-heal | 8 |
| `Sources/MyTimeApp/Engine/Scheduler.swift` | Single one-shot wake-up timer | 8 |
| `Sources/MyTimeApp/Engine/SystemEvents.swift` | Notification subscriptions → `RefreshReason` | 8 |
| `Sources/MyTimeApp/Engine/AppMonitor.swift` | Blocked-process lookup | 8 |
| `Sources/MyTimeApp/UI/RepeatingUITimer.swift`, `Theme.swift` | Visible-only timer helper, colors | 8 |
| `Sources/MyTimeApp/main.swift`, `MyTimeScene.swift`, `AppDelegate.swift` | Entry points | 9 |
| `Sources/MyTimeApp/Engine/AppModel.swift` | Owns `EngineCore`; refresh cycle; effects; save; schedule | 9 |
| `Sources/MyTimeApp/Engine/Enforcer.swift` | Applies policy: hide/terminate/gate | 9 |
| `Sources/MyTimeApp/UI/OverlayPanel.swift`, `OverlayController.swift` | Panel subclass; gate + pill presentation and actions | 9 |
| `Sources/MyTimeApp/UI/GateView.swift`, `PillView.swift`, `MenuBarLabel.swift`, `PopoverView.swift` | Views | 9 |
| `Tests/MyTimeCoreTests/*.swift` | Unit tests | 1–7 |
| `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md` | Run docs | 10 |

---

### Task 1: Package scaffold, packaging, scripts

**Files:**
- Create: `Package.swift`, `Packaging/Info.plist`, `scripts/build.sh`, `scripts/uninstall.sh`
- Create (temporary; replaced in later tasks): `Sources/MyTimeCore/Logic/Constants.swift`, `Sources/MyTimeApp/main.swift`, `Tests/MyTimeCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: targets `MyTimeCore`, `MyTimeApp` (product `myTime`), `MyTimeCoreTests`.

- [ ] **Step 1: Create `Package.swift`** exactly as in spec §3.3.

- [ ] **Step 2: Create `Packaging/Info.plist`** as an XML plist with exactly the keys and values in spec §10.1.

- [ ] **Step 3: Create `scripts/build.sh`** exactly as spec §10.2, and `scripts/uninstall.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
launchctl bootout "gui/$(id -u)/local.mytime.agent" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.mytime.agent.plist"
rm -rf "$HOME/Applications/myTime.app"
echo "myTime removed (data in ~/Library/Application Support/myTime was kept)."
```

Then run `chmod +x scripts/build.sh scripts/uninstall.sh`.

- [ ] **Step 4: Create temporary sources so the package builds**

`Sources/MyTimeCore/Logic/Constants.swift` (rewritten in Task 2):

```swift
import Foundation

public enum Constants {
    public static let schemaVersion = 1
}
```

`Sources/MyTimeApp/main.swift` (rewritten in Task 9):

```swift
import Foundation
print("myTime")
```

`Tests/MyTimeCoreTests/SmokeTests.swift` (deleted in Task 2):

```swift
import XCTest
@testable import MyTimeCore

final class SmokeTests: XCTestCase {
    func testPackageBuilds() { XCTAssertEqual(Constants.schemaVersion, 1) }
}
```

- [ ] **Step 5: Verify**

Run: `swift build && swift test && bash -n scripts/build.sh && bash -n scripts/uninstall.sh`
Expected: `Build complete!`, `Executed 1 test, with 0 failures`, no syntax errors.

- [ ] **Step 6: Checkpoint** — all of the above pass. Do not commit.

---

### Task 2: Settings table, constants, duration formatting

**Files:**
- Modify: `Sources/MyTimeCore/Logic/Constants.swift` (full rewrite)
- Create: `Sources/MyTimeCore/Model/SettingKey.swift`, `Sources/MyTimeCore/Logic/DurationFormat.swift`
- Delete: `Tests/MyTimeCoreTests/SmokeTests.swift`
- Test: `Tests/MyTimeCoreTests/SettingKeyTests.swift`, `Tests/MyTimeCoreTests/DurationFormatTests.swift`

**Interfaces:**
- Produces:

```swift
public enum Constants {
    public static let schemaVersion: Int        // 1
    public static let isDev: Bool               // true only under DEV_TIMESCALE
    // Every row of spec §8.2 as a `public static let`, using the §8.2 name.
    // TimeInterval: launchGrace, extendWindow, focusCheckInterval, bookingHeadsUp, gateTimeout, forceQuitAfter,
    //   holdToConfirm, headsUpVisible, minAwayGap, minClaimable, clockJumpTolerance,
    //   criticalWakeTolerance, normalWakeTolerance
    // Int: bookingMinSeconds, bookingStartStepSeconds, bookingDurationStepSeconds, bookingHorizonSeconds,
    //   minReplyNote, minEmergencyReason, historyCap, dailyRetentionDays, bookingRetentionDays
}

public enum SettingUnit: String, Codable { case seconds, count, hourOfDay }
public enum LooserWhen: String, Codable { case higher, lower, anyChange }
public enum SettingGroup: String, Codable, CaseIterable {
    case earning = "Earning", spending = "Spending", sessions = "Sessions", emergency = "Emergency", safety = "Safety"
}

public enum SettingKey: String, Codable, CaseIterable {
    // the 19 cases of spec §8.1, in table order
    public var title: String { get }
    public var group: SettingGroup { get }
    public var unit: SettingUnit { get }
    public var defaultValue: Int { get }          // DEV default under DEV_TIMESCALE
    public var range: ClosedRange<Int> { get }    // DEV: lower bound = min(release lower bound, 1); dayStartHour always 0...23
    public var step: Int { get }
    public var looserWhen: LooserWhen { get }
    public func clamp(_ value: Int) -> Int
}

public enum DurationFormat {
    public static func clock(_ seconds: Double) -> String
    public static func short(_ seconds: Double) -> String
    public static func hourOfDay(_ hour: Int, locale: Locale) -> String
    public static func setting(_ key: SettingKey, _ value: Int, locale: Locale) -> String
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/SettingKeyTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class SettingKeyTests: XCTestCase {
    func testDefaultsMatchSpec() {
        XCTAssertEqual(SettingKey.allCases.count, 19)
        XCTAssertEqual(SettingKey.focusSecondsPerToken.defaultValue, 900)
        XCTAssertEqual(SettingKey.dayStartHour.defaultValue, 4)
        XCTAssertEqual(SettingKey.quickLookSecondsPerToken.defaultValue, 30)
        XCTAssertEqual(SettingKey.quickLookMaxTokens.defaultValue, 3)
        XCTAssertEqual(SettingKey.gatePauseSeconds.defaultValue, 5)
        XCTAssertEqual(SettingKey.weeklyAllowanceSeconds.defaultValue, 18000)
        XCTAssertEqual(SettingKey.bookingLeadSeconds.defaultValue, 600)
        XCTAssertEqual(SettingKey.looseningDelaySeconds.defaultValue, 86400)
        XCTAssertEqual(SettingKey.focusSecondsPerToken.title, "Focus per token")
        XCTAssertEqual(SettingKey.dayStartHour.unit, .hourOfDay)
        XCTAssertEqual(SettingKey.bookingLeadSeconds.group, .sessions)
    }

    func testEveryDefaultIsInsideItsRange() {
        for key in SettingKey.allCases {
            XCTAssertTrue(key.range.contains(key.defaultValue), key.rawValue)
        }
    }

    func testLooseningDirections() {
        XCTAssertEqual(SettingKey.focusSecondsPerToken.looserWhen, .lower)
        XCTAssertEqual(SettingKey.weeklyAllowanceSeconds.looserWhen, .higher)
        XCTAssertEqual(SettingKey.dayStartHour.looserWhen, .anyChange)
        XCTAssertEqual(SettingKey.replyTokenCost.looserWhen, .lower)
        XCTAssertEqual(SettingKey.looseningDelaySeconds.looserWhen, .lower)
    }

    func testClamp() {
        XCTAssertEqual(SettingKey.quickLookMaxTokens.clamp(99), 10)
        XCTAssertEqual(SettingKey.dayStartHour.clamp(-3), 0)
        XCTAssertEqual(SettingKey.gatePauseSeconds.clamp(7), 7)
    }

    func testReleaseConstants() {
        XCTAssertFalse(Constants.isDev)
        XCTAssertEqual(Constants.launchGrace, 15)
        XCTAssertEqual(Constants.extendWindow, 10)
        XCTAssertEqual(Constants.focusCheckInterval, 30)
        XCTAssertEqual(Constants.bookingHeadsUp, 300)
        XCTAssertEqual(Constants.bookingStartStepSeconds, 300)
        XCTAssertEqual(Constants.gateTimeout, 60)
        XCTAssertEqual(Constants.historyCap, 500)
    }
}
```

`Tests/MyTimeCoreTests/DurationFormatTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class DurationFormatTests: XCTestCase {
    let enUS = Locale(identifier: "en_US")

    func testClockCountsUpToTheNextWholeSecond() {
        XCTAssertEqual(DurationFormat.clock(0), "0:00")
        XCTAssertEqual(DurationFormat.clock(4.2), "0:05")
        XCTAssertEqual(DurationFormat.clock(60), "1:00")
        XCTAssertEqual(DurationFormat.clock(3723), "1:02:03")
        XCTAssertEqual(DurationFormat.clock(-5), "0:00")
    }

    func testShort() {
        XCTAssertEqual(DurationFormat.short(45), "45 s")
        XCTAssertEqual(DurationFormat.short(59.6), "1 min")
        XCTAssertEqual(DurationFormat.short(720), "12 min")
        XCTAssertEqual(DurationFormat.short(3600), "1h")
        XCTAssertEqual(DurationFormat.short(7800), "2h 10m")
    }

    func testHourOfDayUsesPlainSpaces() {
        XCTAssertEqual(DurationFormat.hourOfDay(4, locale: enUS), "4:00 AM")
        XCTAssertEqual(DurationFormat.hourOfDay(16, locale: enUS), "4:00 PM")
    }

    func testSettingFormatting() {
        XCTAssertEqual(DurationFormat.setting(.weeklyAllowanceSeconds, 18000, locale: enUS), "5h")
        XCTAssertEqual(DurationFormat.setting(.quickLookMaxTokens, 3, locale: enUS), "3")
        XCTAssertEqual(DurationFormat.setting(.dayStartHour, 4, locale: enUS), "4:00 AM")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`SettingKey`, `DurationFormat` not found).

- [ ] **Step 3: Implement**

- **`Constants.swift`**: one `#if DEV_TIMESCALE … #else … #endif` block with every row of §8.2 (Release vs DEV columns), plus `schemaVersion = 1` and `isDev`.
- **`SettingKey.swift`**: all 19 rows of §8.1, every column. A private row struct returned from one `switch` keeps it compact, for example:

```swift
private struct Row {
    let title: String; let group: SettingGroup; let unit: SettingUnit
    let release: Int; let dev: Int; let range: ClosedRange<Int>; let step: Int; let looser: LooserWhen
}
// case .focusSecondsPerToken:
//     return Row(title: "Focus per token", group: .earning, unit: .seconds,
//                release: 900, dev: 15, range: 300...3600, step: 60, looser: .lower)
```

- **`DurationFormat`** rules:
  - `clock`: `s = max(0, Int(seconds.rounded(.up)))`. Under 3600 → `"m:ss"`; otherwise `"h:mm:ss"`.
  - `short`:
    - `total = Int(seconds.rounded())`
    - if `total < 60` → `"\(total) s"`
    - otherwise `m = Int((Double(total) / 60).rounded())`
    - if `m < 60` → `"\(m) min"`
    - otherwise `h = m / 60`, `mm = m % 60`, giving `"\(h)h"` when `mm == 0`, else `"\(h)h \(mm)m"`
  - `setting`: `.seconds` → `short`, `.count` → `"\(value)"`, `.hourOfDay` → `hourOfDay`.
  - `hourOfDay` (**verified**: macOS inserts U+202F before AM/PM, so it must be normalized):

```swift
public static func hourOfDay(_ hour: Int, locale: Locale) -> String {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let date = utc.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour))!
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.setLocalizedDateFormatFromTemplate("j:mm")
    return formatter.string(from: date)
        .replacingOccurrences(of: "\u{202F}", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Checkpoint** — `swift build && swift test` pass. Do not commit.

---

### Task 3: Trusted clock and calendar keys

**Files:**
- Create: `Sources/MyTimeCore/Logic/TrustedClock.swift`, `Sources/MyTimeCore/Logic/CalendarKeys.swift`
- Test: `Tests/MyTimeCoreTests/TestSupport.swift`, `Tests/MyTimeCoreTests/TrustedClockTests.swift`, `Tests/MyTimeCoreTests/CalendarKeysTests.swift`

**Interfaces:**
- Produces:

```swift
public struct TrustedClockState: Codable, Equatable {
    public var offsetSeconds: Double
    public var lastWall: Double
    public var lastContinuous: Double
    public var bootSessionID: String
    public init(offsetSeconds: Double = 0, lastWall: Double = 0, lastContinuous: Double = 0, bootSessionID: String = "")
}

public enum TrustedClock {
    /// Returns trusted seconds since 1970 and updates `state` (spec §5.1).
    public static func update(_ state: inout TrustedClockState, wall: Double, continuous: Double, bootSessionID: String) -> Double
}

public enum CalendarKeys {
    public static func dayKey(_ date: Date, dayStartHour: Int, timeZone: TimeZone) -> String    // "yyyy-MM-dd"
    public static func weekKey(_ date: Date, dayStartHour: Int, timeZone: TimeZone) -> String   // "YYYY-Www"
    public static func nextDayStart(after date: Date, dayStartHour: Int, timeZone: TimeZone) -> Date
    public static func nextWeekStart(after date: Date, dayStartHour: Int, timeZone: TimeZone) -> Date
}
```

- [ ] **Step 1: Write test support and the failing tests**

`Tests/MyTimeCoreTests/TestSupport.swift`:

```swift
import Foundation
@testable import MyTimeCore

let testTZ = TimeZone(identifier: "America/New_York")!

/// Local date in `testTZ`. 2026-09-13 is a Sunday; 2026-09-14 is a Monday.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = testTZ
    return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}
```

`Tests/MyTimeCoreTests/TrustedClockTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class TrustedClockTests: XCTestCase {
    func testFirstReadingSetsBaseline() {
        var s = TrustedClockState()
        XCTAssertEqual(TrustedClock.update(&s, wall: 1000, continuous: 50, bootSessionID: "A"), 1000)
        XCTAssertEqual(s.offsetSeconds, 0)
        XCTAssertEqual(s.bootSessionID, "A")
    }

    func testForwardJumpIsCancelled() {
        var s = TrustedClockState()
        _ = TrustedClock.update(&s, wall: 1000, continuous: 50, bootSessionID: "A")
        let t = TrustedClock.update(&s, wall: 1000 + 10_800 + 1, continuous: 51, bootSessionID: "A")
        XCTAssertEqual(t, 1001, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, -10_800, accuracy: 0.001)
    }

    func testBackwardJumpIsCancelled() {
        var s = TrustedClockState()
        _ = TrustedClock.update(&s, wall: 10_000, continuous: 50, bootSessionID: "A")
        let t = TrustedClock.update(&s, wall: 10_000 - 7200 + 1, continuous: 51, bootSessionID: "A")
        XCTAssertEqual(t, 10_001, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, 7200, accuracy: 0.001)
    }

    func testSmallDriftIsAccepted() {
        var s = TrustedClockState()
        _ = TrustedClock.update(&s, wall: 1000, continuous: 50, bootSessionID: "A")
        XCTAssertEqual(TrustedClock.update(&s, wall: 1631, continuous: 650, bootSessionID: "A"), 1631, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, 0)
    }

    func testLongGapWithoutJumpIsAccepted() {
        var s = TrustedClockState()
        _ = TrustedClock.update(&s, wall: 1000, continuous: 50, bootSessionID: "A")
        XCTAssertEqual(TrustedClock.update(&s, wall: 1600, continuous: 650, bootSessionID: "A"), 1600, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, 0)
    }

    func testNewBootKeepsOffsetWithoutAdjusting() {
        var s = TrustedClockState(offsetSeconds: -500, lastWall: 1000, lastContinuous: 50, bootSessionID: "A")
        let t = TrustedClock.update(&s, wall: 90_000, continuous: 10, bootSessionID: "B")
        XCTAssertEqual(t, 89_500, accuracy: 0.001)
        XCTAssertEqual(s.offsetSeconds, -500)
        XCTAssertEqual(s.bootSessionID, "B")
    }
}
```

`Tests/MyTimeCoreTests/CalendarKeysTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class CalendarKeysTests: XCTestCase {
    func testDayKeyFlipsAtDayStartHour() {
        XCTAssertEqual(CalendarKeys.dayKey(date(2026, 9, 14, 3, 59), dayStartHour: 4, timeZone: testTZ), "2026-09-13")
        XCTAssertEqual(CalendarKeys.dayKey(date(2026, 9, 14, 4, 0), dayStartHour: 4, timeZone: testTZ), "2026-09-14")
        XCTAssertEqual(CalendarKeys.dayKey(date(2026, 9, 14, 0, 30), dayStartHour: 0, timeZone: testTZ), "2026-09-14")
    }

    func testWeekStartsMondayAtDayStartHour() {
        let sundayNight = CalendarKeys.weekKey(date(2026, 9, 13, 23), dayStartHour: 4, timeZone: testTZ)
        let mondayEarly = CalendarKeys.weekKey(date(2026, 9, 14, 3), dayStartHour: 4, timeZone: testTZ)
        let mondayLater = CalendarKeys.weekKey(date(2026, 9, 14, 4), dayStartHour: 4, timeZone: testTZ)
        XCTAssertEqual(sundayNight, mondayEarly)
        XCTAssertNotEqual(mondayEarly, mondayLater)
        XCTAssertEqual(mondayLater, "2026-W38")
    }

    func testNextDayStartIsStrictlyAfter() {
        XCTAssertEqual(CalendarKeys.nextDayStart(after: date(2026, 9, 14, 3), dayStartHour: 4, timeZone: testTZ), date(2026, 9, 14, 4))
        XCTAssertEqual(CalendarKeys.nextDayStart(after: date(2026, 9, 14, 5), dayStartHour: 4, timeZone: testTZ), date(2026, 9, 15, 4))
        XCTAssertEqual(CalendarKeys.nextDayStart(after: date(2026, 9, 14, 4), dayStartHour: 4, timeZone: testTZ), date(2026, 9, 15, 4))
    }

    func testNextWeekStart() {
        XCTAssertEqual(CalendarKeys.nextWeekStart(after: date(2026, 9, 13, 12), dayStartHour: 4, timeZone: testTZ), date(2026, 9, 14, 4))
        XCTAssertEqual(CalendarKeys.nextWeekStart(after: date(2026, 9, 14, 5), dayStartHour: 4, timeZone: testTZ), date(2026, 9, 21, 4))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`TrustedClock`, `CalendarKeys` not found).

- [ ] **Step 3: Implement**

- **`TrustedClock.update`**: the pseudocode in §5.1, with `Constants.clockJumpTolerance`.
- **`CalendarKeys`** (**verified** approach):
  - Gregorian calendar with the given `timeZone`. Shift by `-dayStartHour` hours via `calendar.date(byAdding: .hour, value: -dayStartHour, to: date)!` before reading components.
  - `dayKey`: `String(format: "%04d-%02d-%02d", …)`.
  - `weekKey`: `Calendar(identifier: .iso8601)` with the same time zone, reading `[.yearForWeekOfYear, .weekOfYear]`, formatted `"%04d-W%02d"`.
  - `nextDayStart`: `calendar.nextDate(after: date, matching: DateComponents(hour: h, minute: 0, second: 0), matchingPolicy: .nextTime)!`.
  - `nextWeekStart`: the same, adding `weekday: 2`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Checkpoint** — `swift build && swift test` pass. Do not commit.

---

### Task 4: Data model and errors

**Files:**
- Create: `Sources/MyTimeCore/Model/Settings.swift`, `BlockedApp.swift`, `AccessGrant.swift`, `Booking.swift`, `Stats.swift`, `HistoryEvent.swift`, `PendingChange.swift`, `PersistedState.swift`, `EngineTypes.swift`
- Create: `Sources/MyTimeCore/Logic/EngineError.swift`, `Sources/MyTimeCore/Persistence/JSONCoding.swift`
- Test: `Tests/MyTimeCoreTests/ModelTests.swift`

**Interfaces:**
- Consumes: `SettingKey`, `DurationFormat`, `CalendarKeys`, `TrustedClockState`.
- Produces: all types are `Codable, Equatable` unless marked otherwise. Property lists and defaults are exact. Every type gets an explicit `public init` taking every stored property in the listed order, with the listed defaults.

```swift
// Settings.swift
public struct Settings {
    public var numbers: [String: Int] = [:]
    public var apps: [BlockedApp] = []
    public subscript(key: SettingKey) -> Int { get set }   // get: numbers[rawValue] ?? defaultValue; set: stores key.clamp(newValue)
}

// BlockedApp.swift
public enum AccessMode: String, Codable, CaseIterable {
    case quickLook, reply, booked
    public var title: String { get }                       // "Quick look", "Reply mode", "Sessions"
}
public struct BlockedApp: Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var bundleIDs: [String]
    public var modes: Set<AccessMode>
    public static func discord() -> BlockedApp             // spec §4.2 default entry, all three modes
}

// AccessGrant.swift
public enum GrantKind: String, Codable { case quickLook, reply, emergency }
public struct AccessGrant: Identifiable {
    public var id: UUID = UUID()
    public var appID: UUID
    public var kind: GrantKind
    public var createdAt: Date
    public var startsAt: Date
    public var expiresAt: Date
    public var tokensSpent: Int = 0
    public var note: String? = nil
}

// Booking.swift
public struct Booking: Identifiable {
    public var id: UUID = UUID()
    public var start: Date
    public var durationSeconds: Int
    public var extensionSeconds: Int = 0
    public var createdAt: Date
    public var canceledAt: Date? = nil
    public var endedAt: Date? = nil
    public var appOpened: Bool = false
    public var warned: Bool = false
    public var end: Date { get }                     // start + durationSeconds + extensionSeconds
    public func isUpcoming(at now: Date) -> Bool     // canceledAt == nil && now < start
    public func isActive(at now: Date) -> Bool       // canceledAt == nil && endedAt == nil && start <= now && now < end
    public func isFinished(at now: Date) -> Bool     // canceledAt == nil && (endedAt != nil || now >= end)
}

// Stats.swift
public struct DailyStats {
    public var focusSeconds: Double = 0
    public var tokensEarned: Int = 0
    public var tokensSpent: Int = 0
    public var backedOff: Int = 0
    public var quickLooks: Int = 0
    public var replies: Int = 0
    public var claimedAwaySeconds: Double = 0
    public var unclaimedAwaySeconds: Double = 0
}
public struct WeeklyStats {
    public var emergencyUses: Int = 0
    public var allowanceForfeited: Bool = false
}

// HistoryEvent.swift
public enum HistoryKind: String, Codable {
    case focusStarted, focusEnded, tokenEarned, dayReset, awayClaimed, quickLook, reply, extended,
         backedOff, bookingCreated, bookingCanceled, bookingEnded, bookingExtended,
         emergency, changeScheduled, changeApplied, changeCanceled, appAdded, appRemoved, tamperDetected
}
public struct HistoryEvent: Identifiable {
    public var id: UUID = UUID()
    public var date: Date
    public var kind: HistoryKind
    public var text: String
}

// PendingChange.swift
public enum SettingChange: Codable, Equatable {
    case setNumber(key: SettingKey, value: Int)
    case addApp(BlockedApp)
    case removeApp(id: UUID)
    case setMode(appID: UUID, mode: AccessMode, enabled: Bool)
    case uninstall
    public var fieldKey: String { get }   // "number:<key rawValue>", "app:<uuidString>" (add & remove), "mode:<uuidString>:<mode rawValue>", "uninstall"
}
public struct PendingChange: Identifiable {
    public var id: UUID = UUID()
    public var createdAt: Date
    public var applyAt: Date
    public var change: SettingChange
    public var summary: String
}
public enum SubmitResult: Equatable { case applied, scheduled(applyAt: Date), noChange }   // Equatable only

// PersistedState.swift
public struct FocusSession {
    public var startedAt: Date
    public var creditedSeconds: Double = 0
}
public struct PersistedState {
    public var schemaVersion: Int = 1
    public var settings: Settings
    public var pending: [PendingChange] = []
    public var tokens: Int = 0
    public var progressSeconds: Double = 0
    public var tokensDayKey: String
    public var focus: FocusSession? = nil
    public var grants: [AccessGrant] = []
    public var bookings: [Booking] = []
    public var daily: [String: DailyStats] = [:]
    public var weekly: [String: WeeklyStats] = [:]
    public var history: [HistoryEvent] = []
    public var clock: TrustedClockState = TrustedClockState()
    public var tamperNoticeUntil: Date? = nil
    /// settings = Settings(apps: [.discord()]);
    /// tokensDayKey = CalendarKeys.dayKey(now, dayStartHour: SettingKey.dayStartHour.defaultValue, timeZone: timeZone)
    public static func fresh(now: Date, timeZone: TimeZone) -> PersistedState
}

// EngineTypes.swift  (Equatable only, not Codable)
public struct EngineRuntime {
    public var unvestedSeconds: Double = 0
    public var lastUptime: Double? = nil
    public var blockedRunningAtLastUpdate: Bool = false
    public var awayStartUptime: Double? = nil
    public var lastActiveBookingID: UUID? = nil
}
public struct UpdateInput {   // no defaults
    public var wall: Date
    public var continuous: Double
    public var uptime: Double
    public var bootSessionID: String
    public var idleSeconds: Double
    public var isLocked: Bool
    public var runningAppIDs: Set<UUID>
}
public struct WakeUp { public var date: Date; public var critical: Bool }
public struct UpdateResult { public var effects: [EngineEffect] = []; public var nextWakeUp: WakeUp? = nil }
public enum EngineEffect { case terminateIfNotAllowed(appID: UUID), bookingHeadsUp(bookingID: UUID), uninstall }

// EngineError.swift  (Error, Equatable)
public enum EngineError: Error, Equatable {
    case unknownApp, unknownGrant, modeNotAllowed, focusActive, invalidAmount(max: Int), notEnoughTokens,
         noteTooShort, replyLimitReached, cannotExtend, reasonTooShort, emergencyUnavailable,
         bookingTooSoon(leadSeconds: Int), bookingTooFar, invalidDuration(minSeconds: Int, maxSeconds: Int),
         bookingOverlap, allowanceExceeded, cannotCancel, cannotExtendBooking
    public var userMessage: String { get }   // spec §7.10; use DurationFormat.short for seconds values
}

// JSONCoding.swift
public extension JSONEncoder { static var myTime: JSONEncoder { get } }   // .secondsSince1970, [.sortedKeys]
public extension JSONDecoder { static var myTime: JSONDecoder { get } }   // .secondsSince1970
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/ModelTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class ModelTests: XCTestCase {
    func testFreshStateBlocksDiscordWithAllModes() {
        let s = PersistedState.fresh(now: date(2026, 9, 14, 10), timeZone: testTZ)
        XCTAssertEqual(s.schemaVersion, 1)
        XCTAssertEqual(s.tokens, 0)
        XCTAssertEqual(s.tokensDayKey, "2026-09-14")
        XCTAssertEqual(s.settings.apps.count, 1)
        XCTAssertEqual(s.settings.apps[0].name, "Discord")
        XCTAssertEqual(s.settings.apps[0].bundleIDs, ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"])
        XCTAssertEqual(s.settings.apps[0].modes, [.quickLook, .reply, .booked])
    }

    func testSettingsSubscriptFallsBackToDefaultAndClamps() {
        var settings = Settings()
        XCTAssertEqual(settings[.focusSecondsPerToken], 900)
        settings[.focusSecondsPerToken] = 600
        XCTAssertEqual(settings.numbers["focusSecondsPerToken"], 600)
        settings[.quickLookMaxTokens] = 50
        XCTAssertEqual(settings[.quickLookMaxTokens], 10)
    }

    func testPersistedStateRoundTripsAndUsesStringKeyedObjects() throws {
        var s = PersistedState.fresh(now: date(2026, 9, 14, 10), timeZone: testTZ)
        let discord = s.settings.apps[0].id
        s.tokens = 4
        s.daily["2026-09-14"] = DailyStats(backedOff: 1)
        s.grants = [AccessGrant(appID: discord, kind: .reply, createdAt: date(2026, 9, 14, 10),
                                startsAt: date(2026, 9, 14, 10), expiresAt: date(2026, 9, 14, 10, 3),
                                tokensSpent: 2, note: "reply to Sam")]
        s.pending = [PendingChange(createdAt: date(2026, 9, 14, 10), applyAt: date(2026, 9, 15, 10),
                                   change: .setMode(appID: discord, mode: .reply, enabled: true),
                                   summary: "Turn on Reply mode for Discord")]
        let data = try JSONEncoder.myTime.encode(s)
        XCTAssertEqual(try JSONDecoder.myTime.decode(PersistedState.self, from: data), s)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"daily\":{\"2026-09-14\":{"), json)
    }

    func testBookingStates() {
        var b = Booking(start: date(2026, 9, 14, 20), durationSeconds: 3600, createdAt: date(2026, 9, 14, 10))
        XCTAssertEqual(b.end, date(2026, 9, 14, 21))
        XCTAssertTrue(b.isUpcoming(at: date(2026, 9, 14, 19)))
        XCTAssertTrue(b.isActive(at: date(2026, 9, 14, 20, 30)))
        XCTAssertTrue(b.isFinished(at: date(2026, 9, 14, 21)))
        b.endedAt = date(2026, 9, 14, 20, 30)
        XCTAssertFalse(b.isActive(at: date(2026, 9, 14, 20, 45)))
        XCTAssertTrue(b.isFinished(at: date(2026, 9, 14, 20, 45)))
        b.canceledAt = date(2026, 9, 14, 12)
        XCTAssertFalse(b.isFinished(at: date(2026, 9, 14, 22)))
        XCTAssertFalse(b.isUpcoming(at: date(2026, 9, 14, 19)))
    }

    func testFieldKeys() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let app = BlockedApp(id: id, name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"], modes: [])
        XCTAssertEqual(SettingChange.setNumber(key: .replyPerDay, value: 1).fieldKey, "number:replyPerDay")
        XCTAssertEqual(SettingChange.addApp(app).fieldKey, "app:00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(SettingChange.removeApp(id: id).fieldKey, "app:00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(SettingChange.setMode(appID: id, mode: .reply, enabled: true).fieldKey,
                       "mode:00000000-0000-0000-0000-000000000001:reply")
        XCTAssertEqual(SettingChange.uninstall.fieldKey, "uninstall")
    }

    func testEngineErrorMessages() {
        XCTAssertEqual(EngineError.invalidAmount(max: 3).userMessage, "Choose between 1 and 3 tokens.")
        XCTAssertEqual(EngineError.notEnoughTokens.userMessage, "Not enough tokens.")
        XCTAssertEqual(EngineError.bookingTooSoon(leadSeconds: 600).userMessage, "Book at least 10 min ahead.")
        XCTAssertEqual(EngineError.invalidDuration(minSeconds: 1800, maxSeconds: 10800).userMessage,
                       "Choose a length between 30 min and 3h.")
        XCTAssertEqual(EngineError.unknownApp.userMessage, "That app isn't blocked anymore.")
        XCTAssertEqual(EngineError.unknownGrant.userMessage, "That access has already ended.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (model types not found).

- [ ] **Step 3: Implement** the declarations above.
- Codable is synthesized, including `SettingChange`'s associated values.
- `EngineError.userMessage` uses the §7.10 table plus the two additions tested above.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Checkpoint** — `swift build && swift test` pass. Do not commit.

---

### Task 5: State codec and tamper penalty

**Files:**
- Create: `Sources/MyTimeCore/Persistence/StateCodec.swift`, `Sources/MyTimeCore/Persistence/Penalty.swift`
- Test: `Tests/MyTimeCoreTests/StateCodecTests.swift`

**Interfaces:**
- Consumes: `PersistedState`, `JSONEncoder.myTime`, `JSONDecoder.myTime`, `CalendarKeys`.
- Produces:

```swift
public enum DecodeResult: Equatable { case ok(PersistedState), tampered }

public enum StateCodec {
    public static func encode(_ state: PersistedState) throws -> Data
    public static func decode(_ data: Data) -> DecodeResult     // never throws
}

extension PersistedState {
    public static func penalized(now: Date, timeZone: TimeZone) -> PersistedState   // spec §5.7
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/StateCodecTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class StateCodecTests: XCTestCase {
    let now = date(2026, 9, 14, 10)

    func testRoundTrip() throws {
        var s = PersistedState.fresh(now: now, timeZone: testTZ)
        s.tokens = 7
        XCTAssertEqual(StateCodec.decode(try StateCodec.encode(s)), .ok(s))
    }

    func testEnvelopeShape() throws {
        let data = try StateCodec.encode(.fresh(now: now, timeZone: testTZ))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["v"] as? Int, 1)
        XCTAssertNotNil(obj["payload"] as? String)
        XCTAssertEqual((obj["mac"] as? String)?.count, 64)
    }

    func testEditedPayloadIsTampered() throws {
        let data = try StateCodec.encode(.fresh(now: now, timeZone: testTZ))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(obj["payload"] as? String)))
        let original = String(decoding: payload, as: UTF8.self)
        let edited = original.replacingOccurrences(of: "\"tokens\":0", with: "\"tokens\":9")
        XCTAssertNotEqual(original, edited)
        obj["payload"] = Data(edited.utf8).base64EncodedString()
        XCTAssertEqual(StateCodec.decode(try JSONSerialization.data(withJSONObject: obj)), .tampered)
    }

    func testGarbageIsTampered() {
        XCTAssertEqual(StateCodec.decode(Data("not json".utf8)), .tampered)
        XCTAssertEqual(StateCodec.decode(Data("{\"v\":1,\"payload\":\"%%%\",\"mac\":\"zz\"}".utf8)), .tampered)
    }

    func testPenalizedState() {
        let p = PersistedState.penalized(now: now, timeZone: testTZ)
        let week = CalendarKeys.weekKey(now, dayStartHour: 4, timeZone: testTZ)
        let day = CalendarKeys.dayKey(now, dayStartHour: 4, timeZone: testTZ)
        XCTAssertEqual(p.tokens, 0)
        XCTAssertEqual(p.weekly[week]?.allowanceForfeited, true)
        XCTAssertEqual(p.weekly[week]?.emergencyUses, 99)
        XCTAssertEqual(p.daily[day]?.replies, 99)
        XCTAssertEqual(p.daily[day]?.claimedAwaySeconds, 1_000_000)
        XCTAssertEqual(p.tamperNoticeUntil, now.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(p.history.last?.kind, .tamperDetected)
        XCTAssertEqual(p.history.last?.text, "Saved data was edited outside myTime. Balances were reset.")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`StateCodec`, `penalized` not found).

- [ ] **Step 3: Implement** spec §5.7.
- **Key derivation:**

```swift
private static let key = SymmetricKey(data: SHA256.hash(data: Data("myTime.integrity.v1.7c1e9b4a-5d2f-4e8a-9f61-2b3c4d5e6f70".utf8)))
```

- **Envelope:** a private `Codable` struct `{ v: Int, payload: String, mac: String }`.
- **encode:** `payload = JSONEncoder.myTime.encode(state)`, `mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)` rendered as lowercase hex. The envelope is encoded with a plain `JSONEncoder` using `[.sortedKeys]`.
- **decode:** parse the envelope → base64-decode the payload → hex-decode the mac (malformed → `.tampered`) → `HMAC<SHA256>.isValidAuthenticationCode(macData, authenticating: payload, using: key)` → decode the state. Any failure → `.tampered`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Checkpoint** — `swift build && swift test` pass. Do not commit.

---

### Task 6: Enforcement policy and wake-up planner

**Files:**
- Create: `Sources/MyTimeCore/Logic/EnforcementPolicy.swift`, `Sources/MyTimeCore/Logic/WakeUpPlanner.swift`
- Test: `Tests/MyTimeCoreTests/EnforcementPolicyTests.swift`, `Tests/MyTimeCoreTests/WakeUpPlannerTests.swift`

**Interfaces:**
- Consumes: `PersistedState`, `EngineRuntime`, `WakeUp`, `Booking.isActive(at:)`, `Constants`.
- Produces:

```swift
public enum EnforcementTrigger: Equatable { case launched, activated, startupSweep }
public enum EnforcementAction: Equatable { case allow, gate, focusCard, keepHidden, terminate }

public struct EnforcementContext: Equatable {
    public var terminationPending: Bool
    public var isAllowed: Bool
    public var focusActive: Bool
    public var overlayShowingForThisProcess: Bool
    public var overlayBusyWithOtherProcess: Bool
    public init(terminationPending: Bool, isAllowed: Bool, focusActive: Bool,
                overlayShowingForThisProcess: Bool, overlayBusyWithOtherProcess: Bool)
}

public enum EnforcementPolicy {
    public static func decide(trigger: EnforcementTrigger, context: EnforcementContext) -> EnforcementAction   // §5.8
}

public enum WakeUpPlanner {
    /// §5.9. Ignores candidates that are not strictly after `now`. On a tie, `critical: true` wins.
    public static func next(state: PersistedState, runtime: EngineRuntime, now: Date, nextDayStart: Date) -> WakeUp?
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/EnforcementPolicyTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class EnforcementPolicyTests: XCTestCase {
    private func ctx(pending: Bool = false, allowed: Bool = false, focus: Bool = false,
                     mine: Bool = false, busy: Bool = false) -> EnforcementContext {
        EnforcementContext(terminationPending: pending, isAllowed: allowed, focusActive: focus,
                           overlayShowingForThisProcess: mine, overlayBusyWithOtherProcess: busy)
    }

    func testRulesInPriorityOrder() {
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(pending: true, allowed: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx(allowed: true)), .allow)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .activated, context: ctx(mine: true, busy: true)), .keepHidden)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .startupSweep, context: ctx(focus: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(focus: true, busy: true)), .terminate)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .launched, context: ctx(focus: true)), .focusCard)
        XCTAssertEqual(EnforcementPolicy.decide(trigger: .activated, context: ctx()), .gate)
    }
}
```

`Tests/MyTimeCoreTests/WakeUpPlannerTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class WakeUpPlannerTests: XCTestCase {
    let now = date(2026, 9, 14, 10)
    let dayStart = date(2026, 9, 15, 4)
    var fresh: PersistedState { PersistedState.fresh(now: now, timeZone: testTZ) }

    private func plan(_ s: PersistedState, _ rt: EngineRuntime = EngineRuntime()) -> WakeUp? {
        WakeUpPlanner.next(state: s, runtime: rt, now: now, nextDayStart: dayStart)
    }

    func testIdleReturnsNextDayStart() {
        XCTAssertEqual(plan(fresh), WakeUp(date: dayStart, critical: false))
    }

    func testGrantExpiryIsCriticalAndEarliest() {
        var s = fresh
        s.grants = [AccessGrant(appID: s.settings.apps[0].id, kind: .quickLook, createdAt: now,
                                startsAt: now, expiresAt: now.addingTimeInterval(30))]
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(30), critical: true))
    }

    func testFocusAddsCheckInterval() {
        var s = fresh
        s.focus = FocusSession(startedAt: now)
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(Constants.focusCheckInterval), critical: false))
    }

    func testAwayWithoutFocusStillChecks() {
        var rt = EngineRuntime()
        rt.awayStartUptime = 5
        XCTAssertEqual(plan(fresh, rt)?.date, now.addingTimeInterval(Constants.focusCheckInterval))
    }

    func testActiveBookingHeadsUpThenEnd() {
        var s = fresh
        s.bookings = [Booking(start: now.addingTimeInterval(-1800), durationSeconds: 3600,
                              createdAt: now.addingTimeInterval(-7200))]
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(1800 - Constants.bookingHeadsUp), critical: false))
        s.bookings[0].warned = true
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(1800), critical: true))
    }

    func testUpcomingBookingStartIsNotACandidate() {
        var s = fresh
        s.bookings = [Booking(start: now.addingTimeInterval(600), durationSeconds: 1800, createdAt: now)]
        XCTAssertEqual(plan(s), WakeUp(date: dayStart, critical: false))
    }

    func testPendingChangeAndPastCandidatesIgnored() {
        var s = fresh
        s.pending = [
            PendingChange(createdAt: now, applyAt: now.addingTimeInterval(-10), change: .uninstall, summary: "Uninstall myTime"),
            PendingChange(createdAt: now, applyAt: now.addingTimeInterval(600), change: .uninstall, summary: "Uninstall myTime"),
        ]
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(600), critical: false))
    }

    func testTieBreakPrefersCritical() {
        var s = fresh
        s.pending = [PendingChange(createdAt: now, applyAt: now.addingTimeInterval(30), change: .uninstall, summary: "Uninstall myTime")]
        s.grants = [AccessGrant(appID: s.settings.apps[0].id, kind: .quickLook, createdAt: now,
                                startsAt: now, expiresAt: now.addingTimeInterval(30))]
        XCTAssertEqual(plan(s), WakeUp(date: now.addingTimeInterval(30), critical: true))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors.

- [ ] **Step 3: Implement**
- **`decide`**: the 7 rules of §5.8, first match wins.
- **`next`**: collect the §5.9 candidates as `(Date, Bool)`:
  - each grant `expiresAt` (critical)
  - the active booking's `end` (critical) and, if `!warned`, `end - bookingHeadsUp` (not critical)
  - each pending `applyAt` (not critical)
  - `nextDayStart` (not critical)
  - `now + focusCheckInterval` when `state.focus != nil || runtime.awayStartUptime != nil` (not critical)

  Drop candidates `<= now`, then pick the earliest, preferring critical on ties.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 5: Checkpoint** — `swift build && swift test` pass. Do not commit.

---

### Task 7: EngineCore — start/update, daily reset, grants, queries

**Files:**
- Create: `Sources/MyTimeCore/Logic/EngineCore.swift`
- Modify: `Tests/MyTimeCoreTests/TestSupport.swift` (append)
- Test: `Tests/MyTimeCoreTests/DailyResetTests.swift`, `Tests/MyTimeCoreTests/GrantTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2–6.
- Produces (Run 1 subset of spec §5; later runs add to this type):

```swift
public struct EngineCore {
    public var state: PersistedState
    public var runtime: EngineRuntime
    public private(set) var now: Date                  // trusted time from the last start/update
    public let timeZone: TimeZone
    public init(state: PersistedState, timeZone: TimeZone)   // now = Date(timeIntervalSince1970: state.clock.lastWall)

    public mutating func start(_ input: UpdateInput) -> UpdateResult   // Run 1: clock update → reset runtime → return update(input)
    public mutating func update(_ input: UpdateInput) -> UpdateResult  // Run 1: steps 1, 2, 5, 8 of §5

    public var dayStartHour: Int { get }
    public var today: DailyStats { get }                 // state.daily[dayKey(now)] ?? DailyStats()
    public var nextDayStart: Date { get }
    public var secondsToNextToken: Double { get }        // max(0, focusSecondsPerToken − progressSeconds − runtime.unvestedSeconds)
    public func setting(_ key: SettingKey) -> Int
    public func app(id: UUID) -> BlockedApp?
    public func app(bundleID: String) -> BlockedApp?     // exact match within any app's bundleIDs
    public var activeBooking: Booking? { get }
    public func activeGrant(appID: UUID) -> AccessGrant? // latest-expiring grant with now < expiresAt
    public func remaining(of grant: AccessGrant) -> Double   // max(0, expiresAt − max(now, startsAt))
    public func isAllowed(appID: UUID) -> Bool

    public mutating func buyQuickLook(appID: UUID, tokens: Int, appLaunchDate: Date?) throws -> AccessGrant
    public func canExtend(grantID: UUID) -> Bool
    public mutating func extendGrant(grantID: UUID) throws
    public mutating func recordBackedOff(appID: UUID)

    mutating func vest(_ seconds: Double)                          // internal; §5.2 vest(x)
    mutating func updateToday(_ body: (inout DailyStats) -> Void)  // internal
    mutating func record(_ kind: HistoryKind, _ text: String)      // internal; append, keep newest Constants.historyCap

    #if DEV_TIMESCALE
    public mutating func devAddToken()
    public mutating func devAddProgress(seconds: Double)   // calls vest
    public mutating func devSimulateNewDay()               // state.tokensDayKey = ""
    #endif
}
```

- [ ] **Step 1: Append simulation helpers to `TestSupport.swift`**

```swift
/// Simulated system readings. `advance` moves wall, continuous and uptime together.
struct Sim {
    var wall: Date
    var continuous: Double = 1_000
    var uptime: Double = 1_000
    var boot = "BOOT-A"
    var idle: Double = 0
    var locked = false
    var running: Set<UUID> = []

    var input: UpdateInput {
        UpdateInput(wall: wall, continuous: continuous, uptime: uptime, bootSessionID: boot,
                    idleSeconds: idle, isLocked: locked, runningAppIDs: running)
    }

    mutating func advance(_ seconds: Double) {
        wall = wall.addingTimeInterval(seconds)
        continuous += seconds
        uptime += seconds
    }
}

func makeEngine(at wall: Date, tokens: Int = 0) -> (EngineCore, Sim) {
    var state = PersistedState.fresh(now: wall, timeZone: testTZ)
    state.tokens = tokens
    var core = EngineCore(state: state, timeZone: testTZ)
    let sim = Sim(wall: wall)
    _ = core.start(sim.input)
    return (core, sim)
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/MyTimeCoreTests/DailyResetTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class DailyResetTests: XCTestCase {
    func testTokensAndProgressClearAtDayStart() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 3, 50), tokens: 3)
        core.state.progressSeconds = 120
        sim.advance(9 * 60)                                   // 3:59
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 3)
        sim.advance(2 * 60)                                   // 4:01
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokens, 0)
        XCTAssertEqual(core.state.progressSeconds, 0)
        XCTAssertEqual(core.state.tokensDayKey, "2026-09-14")
        XCTAssertEqual(core.state.history.filter { $0.kind == .dayReset }.count, 1)
        XCTAssertEqual(core.state.history.last?.text, "New day · 3 unused tokens cleared")
        sim.advance(60)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.history.filter { $0.kind == .dayReset }.count, 1)
    }

    func testStartAfterOvernightShutdownClearsYesterdaysTokens() {
        var state = PersistedState.fresh(now: date(2026, 9, 14, 23), timeZone: testTZ)
        state.tokens = 5
        state.clock = TrustedClockState(lastWall: date(2026, 9, 14, 23).timeIntervalSince1970,
                                        lastContinuous: 5_000, bootSessionID: "BOOT-A")
        var core = EngineCore(state: state, timeZone: testTZ)
        let sim = Sim(wall: date(2026, 9, 15, 9), continuous: 20, uptime: 20, boot: "BOOT-B")
        let result = core.start(sim.input)
        XCTAssertEqual(core.now, date(2026, 9, 15, 9))
        XCTAssertEqual(core.state.tokens, 0)
        XCTAssertEqual(result.nextWakeUp, WakeUp(date: date(2026, 9, 16, 4), critical: false))
    }

    func testEmptyDayKeyForcesResetWithoutHistoryWhenNoTokens() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        core.state.tokensDayKey = ""
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertEqual(core.state.tokensDayKey, "2026-09-14")
        XCTAssertTrue(core.state.history.filter { $0.kind == .dayReset }.isEmpty)
    }

    func testVestMintsTokensAndCarriesRemainder() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        core.vest(1000)
        XCTAssertEqual(core.state.tokens, 1)
        XCTAssertEqual(core.state.progressSeconds, 100, accuracy: 0.001)
        XCTAssertEqual(core.today.focusSeconds, 1000, accuracy: 0.001)
        XCTAssertEqual(core.today.tokensEarned, 1)
        XCTAssertEqual(core.state.history.last?.text, "Earned a token")
        XCTAssertEqual(core.secondsToNextToken, 800, accuracy: 0.001)
    }
}
```

`Tests/MyTimeCoreTests/GrantTests.swift`:

```swift
import XCTest
@testable import MyTimeCore

final class GrantTests: XCTestCase {
    private var discord: UUID!

    private func engine(tokens: Int) -> (EngineCore, Sim) {
        let pair = makeEngine(at: date(2026, 9, 14, 10), tokens: tokens)
        discord = pair.0.state.settings.apps[0].id
        return pair
    }

    func testQuickLookSpendsTokensAndCreatesGrant() throws {
        var (core, _) = engine(tokens: 5)
        let g = try core.buyQuickLook(appID: discord, tokens: 2, appLaunchDate: nil)
        XCTAssertEqual(core.state.tokens, 3)
        XCTAssertEqual(g.kind, .quickLook)
        XCTAssertEqual(g.tokensSpent, 2)
        XCTAssertEqual(g.startsAt, core.now)
        XCTAssertEqual(g.expiresAt, core.now.addingTimeInterval(60))
        XCTAssertEqual(core.today.tokensSpent, 2)
        XCTAssertEqual(core.today.quickLooks, 1)
        XCTAssertEqual(core.state.history.last?.text, "Quick look in Discord · 1:00 · 2 ◆")
        XCTAssertTrue(core.isAllowed(appID: discord))
        XCTAssertEqual(core.activeGrant(appID: discord)?.id, g.id)
    }

    func testLaunchGraceDelaysStart() throws {
        var (core, _) = engine(tokens: 5)
        let g = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: core.now.addingTimeInterval(-5))
        XCTAssertEqual(g.startsAt, core.now.addingTimeInterval(10))
        XCTAssertEqual(g.expiresAt, core.now.addingTimeInterval(40))
        XCTAssertEqual(core.remaining(of: g), 30, accuracy: 0.001)
    }

    func testAppLaunchedLongAgoStartsNow() throws {
        var (core, _) = engine(tokens: 5)
        let g = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: core.now.addingTimeInterval(-60))
        XCTAssertEqual(g.startsAt, core.now)
    }

    func testQuickLookErrorsInOrder() {
        var (core, _) = engine(tokens: 1)
        func expect(_ error: EngineError, tokens: Int, app: UUID? = nil) {
            XCTAssertThrowsError(try core.buyQuickLook(appID: app ?? discord, tokens: tokens, appLaunchDate: nil)) {
                XCTAssertEqual($0 as? EngineError, error)
            }
        }
        expect(.unknownApp, tokens: 1, app: UUID())
        expect(.invalidAmount(max: 3), tokens: 0)
        expect(.invalidAmount(max: 3), tokens: 4)
        expect(.notEnoughTokens, tokens: 2)
        core.state.settings.apps[0].modes = [.reply]
        expect(.modeNotAllowed, tokens: 1)
        core.state.settings.apps[0].modes = [.quickLook]
        core.state.focus = FocusSession(startedAt: core.now)
        expect(.focusActive, tokens: 1)
        XCTAssertEqual(core.state.tokens, 1)
    }

    func testExtendOnlyInLastTenSeconds() throws {
        var (core, sim) = engine(tokens: 3)
        let g = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: nil)
        XCTAssertFalse(core.canExtend(grantID: g.id))
        XCTAssertThrowsError(try core.extendGrant(grantID: g.id)) { XCTAssertEqual($0 as? EngineError, .cannotExtend) }
        sim.advance(21)
        _ = core.update(sim.input)
        XCTAssertTrue(core.canExtend(grantID: g.id))
        try core.extendGrant(grantID: g.id)
        XCTAssertEqual(core.state.tokens, 1)
        XCTAssertEqual(core.activeGrant(appID: discord)?.expiresAt, g.expiresAt.addingTimeInterval(30))
        XCTAssertEqual(core.today.tokensSpent, 2)
        XCTAssertEqual(core.state.history.last?.text, "Extended Discord · +30 s")
        XCTAssertThrowsError(try core.extendGrant(grantID: UUID())) { XCTAssertEqual($0 as? EngineError, .unknownGrant) }
    }

    func testCannotExtendWithoutTokensOrForEmergency() throws {
        var (core, sim) = engine(tokens: 1)
        let g = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: nil)
        sim.advance(25)
        _ = core.update(sim.input)
        XCTAssertFalse(core.canExtend(grantID: g.id))
        core.state.tokens = 5
        XCTAssertTrue(core.canExtend(grantID: g.id))
        core.state.grants[0].kind = .emergency
        XCTAssertFalse(core.canExtend(grantID: g.id))
    }

    func testExpiryRemovesGrantAndAsksToTerminate() throws {
        var (core, sim) = engine(tokens: 1)
        _ = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: nil)
        sim.advance(29)
        var r = core.update(sim.input)
        XCTAssertEqual(r.effects, [])
        XCTAssertEqual(r.nextWakeUp, WakeUp(date: core.now.addingTimeInterval(1), critical: true))
        sim.advance(1)
        r = core.update(sim.input)
        XCTAssertEqual(r.effects, [.terminateIfNotAllowed(appID: discord)])
        XCTAssertTrue(core.state.grants.isEmpty)
        XCTAssertFalse(core.isAllowed(appID: discord))
    }

    func testManualClockJumpDoesNotShortenAccess() throws {
        var (core, sim) = engine(tokens: 1)
        _ = try core.buyQuickLook(appID: discord, tokens: 1, appLaunchDate: nil)
        sim.wall = sim.wall.addingTimeInterval(3 * 3600)
        sim.continuous += 1
        sim.uptime += 1
        let r = core.update(sim.input)
        XCTAssertEqual(r.effects, [])
        let grant = try XCTUnwrap(core.activeGrant(appID: discord))
        XCTAssertEqual(core.remaining(of: grant), 29, accuracy: 0.01)
    }

    func testActiveBookingAllowsOnlyBookedModeApps() {
        var (core, sim) = engine(tokens: 0)
        core.state.bookings = [Booking(start: core.now.addingTimeInterval(-60), durationSeconds: 1800,
                                       createdAt: core.now.addingTimeInterval(-3600))]
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertNotNil(core.activeBooking)
        XCTAssertTrue(core.isAllowed(appID: discord))
        core.state.settings.apps[0].modes = [.quickLook]
        XCTAssertFalse(core.isAllowed(appID: discord))
    }

    func testBackedOffIsCounted() {
        var (core, _) = engine(tokens: 0)
        core.recordBackedOff(appID: discord)
        XCTAssertEqual(core.today.backedOff, 1)
        XCTAssertEqual(core.state.history.last?.kind, .backedOff)
        XCTAssertEqual(core.state.history.last?.text, "Backed off from Discord")
    }

    func testLookups() {
        let (core, _) = engine(tokens: 0)
        XCTAssertEqual(core.app(bundleID: "com.hnc.DiscordPTB")?.id, discord)
        XCTAssertNil(core.app(bundleID: "com.hnc.Discord.helper"))
        XCTAssertEqual(core.setting(.quickLookSecondsPerToken), 30)
        XCTAssertEqual(core.nextDayStart, date(2026, 9, 15, 4))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (`EngineCore` not found).

- [ ] **Step 4: Implement `EngineCore`**
- **`update`, Run 1 steps:**
  1. `now = Date(timeIntervalSince1970: TrustedClock.update(&state.clock, wall: input.wall.timeIntervalSince1970, continuous: input.continuous, bootSessionID: input.bootSessionID))`
  2. **Daily reset** per §5.2. History text is `"New day · N unused tokens cleared"` (`"1 unused token cleared"` when N == 1), recorded only when tokens > 0.
  5. **Grant expiry** per §5.3.
  8. `nextWakeUp = WakeUpPlanner.next(state:runtime:now:nextDayStart:)`.
- **`start`:** step 1 → `runtime = EngineRuntime()` → `return update(input)`.
- **`buyQuickLook`:** check order is `unknownApp` → `modeNotAllowed` → `focusActive` → `invalidAmount(max:)` → `notEnoughTokens`. Then apply §5.3.
  - `startsAt = appLaunchDate.map { max(now, $0 + Constants.launchGrace) } ?? now` (corrected in review: no grace when the launch date is unknown).
  - History: `"Quick look in <App> · <DurationFormat.clock(duration)> · <n> ◆"`.
- **`canExtend`/`extendGrant`:** per §5.3. `extendGrant` throws `.unknownGrant` if the id is missing, otherwise `.cannotExtend` when `!canExtend`. History: `"Extended <App> · +<quickLookSecondsPerToken> s"`.
- **`recordBackedOff`:** history `"Backed off from <App>"`.
- **`vest`:** §5.2 `vest(x)`. History `"Earned a token"` per token.
- **DEV helpers:**
  - `devAddToken`: `tokens += 1`.
  - `devAddProgress`: calls `vest`.
  - `devSimulateNewDay`: sets `tokensDayKey = ""`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Compile the DEV variant**

Run: `swift build -Xswiftc -DDEV_TIMESCALE`
Expected: `Build complete!`

- [ ] **Step 7: Checkpoint** — `swift build && swift test && swift build -Xswiftc -DDEV_TIMESCALE` pass. Do not commit.

---

### Task 8: App infrastructure (probe, storage, installer, scheduler, events, monitor)

No unit tests: this is OS glue. Verification is compiling. The snippets below were **compiled and run on the target Mac**; use them as written.

**Files:**
- Create: `Sources/MyTimeApp/Engine/SystemProbe.swift`, `StateStore.swift`, `Installer.swift`, `Scheduler.swift`, `SystemEvents.swift`, `AppMonitor.swift`
- Create: `Sources/MyTimeApp/UI/RepeatingUITimer.swift`, `Sources/MyTimeApp/UI/Theme.swift`

**Interfaces:**
- Consumes: `PersistedState`, `StateCodec`, `EngineCore`, `BlockedApp`, `WakeUp`, `Constants`.
- Produces:

```swift
@MainActor final class SystemProbe {
    let bootSessionID: String
    func continuousSeconds() -> Double
    func uptimeSeconds() -> Double
    func idleSeconds() -> Double
    func isScreenLocked() -> Bool
}

@MainActor final class StateStore {
    enum Outcome { case existing, fresh, tampered }
    func load() -> (state: PersistedState, outcome: Outcome)
    func save(_ state: PersistedState) throws
}

enum Installer {                                     // nonisolated
    static let label: String                         // "local.mytime.agent"
    static func installAndStart() -> Never
    static func selfHeal()
}

@MainActor final class Scheduler {
    var onFire: (() -> Void)?
    func schedule(_ wake: WakeUp?, trustedNow: Date)
}

enum RefreshReason {
    case launch, appLaunched(NSRunningApplication), appActivated(NSRunningApplication), appTerminated(pid_t)
    case screenLocked, screenUnlocked, willSleep, didWake, willPowerOff, clockChanged, wakeUp, intent, panel
}

@MainActor final class SystemEvents {
    init(handler: @escaping (RefreshReason) -> Void)
    func start()
}

@MainActor final class AppMonitor {
    func blockedApp(for process: NSRunningApplication, in core: EngineCore) -> BlockedApp?
    func runningBlocked(in core: EngineCore) -> [(app: BlockedApp, process: NSRunningApplication)]
    func runningBlockedAppIDs(in core: EngineCore) -> Set<UUID>
}

@MainActor final class RepeatingUITimer {
    var isRunning: Bool { get }
    func start(interval: TimeInterval, _ body: @escaping @MainActor () -> Void)   // no-op if already running
    func stop()
}

enum Theme {
    static let accent: Color   // light #2F8F83, dark #5BC0B2
    static let warm: Color     // light #D98A1F, dark #F2B24C
}
```

- [ ] **Step 1: `SystemProbe.swift`** (verified)

```swift
import AppKit
import CoreGraphics

@MainActor final class SystemProbe {
    let bootSessionID: String = SystemProbe.readBootSessionID()

    func continuousSeconds() -> Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9 }
    func uptimeSeconds() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }

    func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }

    func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    nonisolated private static func readBootSessionID() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}
```

- [ ] **Step 2: `StateStore.swift`** per §5.7:
  - **Directory:** `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]/myTime/`.
  - **File and sentinel:** release uses `state.json` and `mytime.initialized`; `#if DEV_TIMESCALE` uses `state-dev.json` and `mytime.dev.initialized`.
  - **`load()`:**
    - If the file can't be read: `.tampered` with `PersistedState.penalized(now: Date(), timeZone: .current)` when the sentinel is true, otherwise `.fresh` with `PersistedState.fresh(now: Date(), timeZone: .current)`.
    - If `StateCodec.decode` returns `.tampered`: move the file to `state.tampered-<Int(unix seconds)>.json` in the same folder (ignore errors) and return the penalized state.
  - **`save(_:)`:** create the directory if needed, then `try StateCodec.encode(state).write(to: fileURL, options: .atomic)`, then set the sentinel to `true`.

- [ ] **Step 3: `Installer.swift`** (spec §3.2)

```swift
import Foundation

enum Installer {
    static let label = "local.mytime.agent"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var executablePath: String? { Bundle.main.executableURL?.resolvingSymlinksInPath().path }
    static var domain: String { "gui/\(getuid())" }

    static func installAndStart() -> Never {
        guard let exe = executablePath, exe.contains(".app/Contents/MacOS/") else {
            FileHandle.standardError.write(Data("myTime must be run from myTime.app (use scripts/build.sh)\n".utf8))
            exit(1)
        }
        do { try writePlist(executable: exe) } catch {
            FileHandle.standardError.write(Data("myTime: could not write LaunchAgent: \(error)\n".utf8))
            exit(1)
        }
        if launchctl(["print", "\(domain)/\(label)"]) != 0 {
            launchctl(["bootstrap", domain, plistURL.path])
        } else {
            launchctl(["kickstart", "\(domain)/\(label)"])
        }
        exit(0)
    }

    /// Rewrites the plist if it is missing or points elsewhere. Only when running from an app bundle.
    static func selfHeal() {
        guard let exe = executablePath, exe.contains(".app/Contents/MacOS/") else { return }
        let args = NSDictionary(contentsOf: plistURL)?["ProgramArguments"] as? [String]
        if args?.first != exe { try? writePlist(executable: exe) }
    }

    private static func writePlist(executable: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--agent"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 5,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
```

- [ ] **Step 4: `RepeatingUITimer.swift` and `Scheduler.swift`** (verified timer pattern)

```swift
import Foundation

@MainActor final class RepeatingUITimer {
    private var timer: Timer?
    var isRunning: Bool { timer != nil }

    func start(interval: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        guard timer == nil else { return }
        let t = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { body() } }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }
}
```

```swift
import Foundation
import MyTimeCore

@MainActor final class Scheduler {
    var onFire: (() -> Void)?
    private var timer: Timer?

    /// `wake.date` is trusted time; `trustedNow` converts it to an interval.
    func schedule(_ wake: WakeUp?, trustedNow: Date) {
        timer?.invalidate()
        timer = nil
        guard let wake else { return }
        let interval = max(0.05, wake.date.timeIntervalSince(trustedNow))
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFire?() }
        }
        t.tolerance = wake.critical ? Constants.criticalWakeTolerance : Constants.normalWakeTolerance
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
```

- [ ] **Step 5: `SystemEvents.swift`** — define `RefreshReason` (above) and subscribe with this pattern (verified):

```swift
private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                     _ map: @escaping (Notification) -> RefreshReason?) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        MainActor.assumeIsolated {
            if let reason = map(note) { self?.handler(reason) }
        }
    }
    tokens.append((center, token))
}
```

`start()` registers exactly these (the app is `note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication`):

| Center | Name | Reason |
|---|---|---|
| `NSWorkspace.shared.notificationCenter` | `NSWorkspace.didLaunchApplicationNotification` | `.appLaunched(app)` |
| same | `NSWorkspace.didActivateApplicationNotification` | `.appActivated(app)` |
| same | `NSWorkspace.didUnhideApplicationNotification` | `.appActivated(app)` |
| same | `NSWorkspace.didTerminateApplicationNotification` | `.appTerminated(app.processIdentifier)` |
| same | `NSWorkspace.willSleepNotification` | `.willSleep` |
| same | `NSWorkspace.didWakeNotification` | `.didWake` |
| same | `NSWorkspace.willPowerOffNotification` | `.willPowerOff` |
| `DistributedNotificationCenter.default()` | `Notification.Name("com.apple.screenIsLocked")` | `.screenLocked` |
| same | `Notification.Name("com.apple.screenIsUnlocked")` | `.screenUnlocked` |
| `NotificationCenter.default` | `.NSSystemClockDidChange` | `.clockChanged` |
| same | `.NSSystemTimeZoneDidChange` | `.clockChanged` |

- [ ] **Step 6: `AppMonitor.swift`**
  - `blockedApp(for:in:)` returns `nil` unless `!process.isTerminated`, `process.activationPolicy == .regular`, and `process.bundleIdentifier` is non-nil. Otherwise it returns `core.app(bundleID:)`.
  - `runningBlocked` maps `NSWorkspace.shared.runningApplications` through `blockedApp`.
  - `runningBlockedAppIDs` returns the set of `app.id`s.

- [ ] **Step 7: `Theme.swift`**
  - Each color is `Color(nsColor: NSColor(name: nil) { appearance in … })`.
  - Choose dark vs. light with `appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua`.
  - Build colors with `NSColor(srgbRed:green:blue:alpha:)` from the hex values in §9.

- [ ] **Step 8: Build**

Run: `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`
Expected: `Build complete!` twice, all tests pass. `main.swift` is still the Task 1 placeholder.

- [ ] **Step 9: Checkpoint** — all pass. Do not commit.

---

### Task 9: The running app (model, enforcement, gate, pill, menu bar)

**Files:**
- Modify: `Sources/MyTimeApp/main.swift` (full rewrite)
- Create: `Sources/MyTimeApp/MyTimeScene.swift`, `AppDelegate.swift`, `Engine/AppModel.swift`, `Engine/Enforcer.swift`
- Create: `Sources/MyTimeApp/UI/OverlayPanel.swift`, `OverlayController.swift`, `GateView.swift`, `PillView.swift`, `MenuBarLabel.swift`, `PopoverView.swift`

**Interfaces:**
- Consumes: everything from Task 8 and `EngineCore`.
- Produces:

```swift
@MainActor @Observable final class AppModel {
    static let shared: AppModel
    private(set) var core: EngineCore
    private(set) var uiNow: Date                       // bumped by UI timers so views re-render
    var displayNow: Date { get }                       // Date() + core.state.clock.offsetSeconds
    var grantCountdown: GrantCountdown? { get }        // running blocked app with an active grant, least remaining
    func launch()
    func refresh(_ reason: RefreshReason)
    @discardableResult func perform<T>(_ intent: (inout EngineCore) throws -> T) rethrows -> T
    func panelDidOpen()
    func panelDidClose()
    func saveNow()
    #if DEV_TIMESCALE
    func devReset()
    #endif
    // @ObservationIgnored: store, probe, monitor, enforcer, overlays, scheduler, events, timers, lastSaved, activity
}

struct GrantCountdown {
    let app: BlockedApp
    let process: NSRunningApplication
    let grant: AccessGrant
    let remaining: Double
}

@MainActor final class Enforcer {
    init(model: AppModel)
    func handle(_ process: NSRunningApplication, trigger: EnforcementTrigger)
    func sweep()
    func terminate(_ process: NSRunningApplication)
    func terminateIfNotAllowed(appID: UUID)
    func processTerminated(pid: pid_t)
}

@MainActor final class OverlayController {
    init(model: AppModel)
    var gateOwnerPID: pid_t? { get }
    var isGateVisible: Bool { get }
    func showGate(app: BlockedApp, process: NSRunningApplication)
    func closeGate()
    func updatePill()
}

@MainActor @Observable final class GateSession {
    let app: BlockedApp
    @ObservationIgnored let process: NSRunningApplication
    let pauseEndsAt: Date
    var now: Date
    var lastInteraction: Date
    var quickLookTokens: Int = 1
    var errorMessage: String?
    var isPausing: Bool { get }          // now < pauseEndsAt
    var pauseRemaining: Int { get }      // max(0, Int(ceil(pauseEndsAt − now)))
    func touch()                         // lastInteraction = Date()
}
```

- [ ] **Step 1: Entry points** (verified pattern)

`main.swift`:

```swift
import AppKit

let arguments = CommandLine.arguments
#if DEV_TIMESCALE
let runInForeground = arguments.contains("--foreground")
#else
let runInForeground = false
#endif

if arguments.contains("--agent") || runInForeground {
    MyTimeScene.main()
} else {
    Installer.installAndStart()
}
```

`MyTimeScene.swift`:

```swift
import SwiftUI

struct MyTimeScene: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: AppModel.shared)
        } label: {
            MenuBarLabel(model: AppModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
```

`AppDelegate.swift`:

```swift
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { AppModel.shared.launch() }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.saveNow() }
}
```

- [ ] **Step 2: `AppModel.swift`**. The refresh cycle is spec §3.5; implement it as below.

> **Important:** intents read `core.now`, which is only as fresh as the last refresh. Minutes can pass between refreshes when nothing is happening. `perform` therefore **refreshes before and after** every intent. Without the first refresh, a quick look bought after a quiet period would be timestamped in the past and expire immediately.

```swift
// Declared as:
//   @ObservationIgnored private(set) var enforcer: Enforcer!          (implicitly-unwrapped, defaults to nil)
//   @ObservationIgnored private(set) var overlays: OverlayController!
//   @ObservationIgnored private var lastSaved: PersistedState?
private init() {
    let store = StateStore()
    let loaded = store.load()
    self.store = store
    self.core = EngineCore(state: loaded.state, timeZone: .current)
    self.lastSaved = loaded.outcome == .existing ? loaded.state : nil   // fresh/tampered states get saved on first refresh
    self.enforcer = Enforcer(model: self)
    self.overlays = OverlayController(model: self)
}

func launch() {
    Installer.selfHeal()
    scheduler.onFire = { [weak self] in self?.refresh(.wakeUp) }
    events = SystemEvents { [weak self] reason in self?.refresh(reason) }
    events?.start()
    refresh(.launch)
}

func refresh(_ reason: RefreshReason) {
    var input = UpdateInput(wall: Date(), continuous: probe.continuousSeconds(), uptime: probe.uptimeSeconds(),
                            bootSessionID: probe.bootSessionID, idleSeconds: probe.idleSeconds(),
                            isLocked: probe.isScreenLocked(), runningAppIDs: monitor.runningBlockedAppIDs(in: core))
    if case .screenLocked = reason { input.isLocked = true }
    if case .screenUnlocked = reason { input.isLocked = false }

    let result: UpdateResult
    if case .launch = reason { result = core.start(input) } else { result = core.update(input) }
    uiNow = Date()

    for effect in result.effects {
        switch effect {
        case .terminateIfNotAllowed(let appID): enforcer.terminateIfNotAllowed(appID: appID)
        case .bookingHeadsUp, .uninstall: break     // Runs 3 and 4
        }
    }

    switch reason {
    case .launch: enforcer.sweep()
    case .appLaunched(let process): enforcer.handle(process, trigger: .launched)
    case .appActivated(let process): enforcer.handle(process, trigger: .activated)
    case .appTerminated(let pid): enforcer.processTerminated(pid: pid)
    case .didWake, .willPowerOff: Installer.selfHeal()
    default: break
    }

    overlays.updatePill()
    updateActivityAndTimers()
    saveIfChanged()
    scheduler.schedule(result.nextWakeUp, trustedNow: displayNow)
}

@discardableResult
func perform<T>(_ intent: (inout EngineCore) throws -> T) rethrows -> T {
    refresh(.intent)
    let value = try intent(&core)
    refresh(.intent)
    return value
}
```

Also implement in `AppModel`:
- **`saveIfChanged()`**: if `core.state != lastSaved`, `try store.save(core.state)` then set `lastSaved`. Log failures with `NSLog`. `saveNow()` saves unconditionally.
- **`updateActivityAndTimers()`**:
  - **Activity assertion** (§3.2): hold `ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Enforcing app limits")` while `overlays.isGateVisible || !core.state.grants.isEmpty || core.activeBooking != nil`. Otherwise end it.
  - **Menu bar label timer:** a `RepeatingUITimer` at 1 s that sets `uiNow = Date()`, running only while `grantCountdown != nil`.
- **`panelDidOpen()`**: start a 1 s `RepeatingUITimer` calling `refresh(.panel)`. **`panelDidClose()`** stops it.
- **`grantCountdown`**: for each `(app, process)` in `monitor.runningBlocked(in: core)` with `core.activeGrant(appID: app.id)`, `remaining = max(0, grant.expiresAt.timeIntervalSince(max(displayNow, grant.startsAt)))`. Return the smallest.
- **`devReset()`** (DEV only): `core.state = .fresh(now: displayNow, timeZone: .current)`, then `refresh(.intent)`.

- [ ] **Step 3: `Enforcer.swift`** per spec §6.2–§6.7
  - **`handle`**: look up `monitor.blockedApp(for:in:)`; return if `nil`; otherwise `reconcile`.
  - **`sweep`**: `reconcile(…, trigger: .startupSweep)` for every `monitor.runningBlocked(in:)` pair.
  - **`reconcile`**: build the context with `pendingTermination.contains(pid)`, `core.isAllowed(appID:)`, `core.state.focus != nil`, `overlays.gateOwnerPID == pid`, and `overlays.gateOwnerPID != nil && != pid`. Then act:
    - `.allow` → nothing
    - `.keepHidden` → `if !process.isHidden { process.hide() }`
    - `.terminate` → `terminate(process)`
    - `.gate` → `process.hide()`, then `overlays.showGate(app:process:)`
    - `.focusCard` → in Run 1 focus can't be active, so call `terminate(process)` (Run 2 replaces this with the focus card)
  - **`terminateIfNotAllowed(appID:)`**: if `!core.isAllowed`, terminate every running process of that app.
  - **`processTerminated(pid:)`**: remove the pid from `pendingTermination`; if `overlays.gateOwnerPID == pid`, call `overlays.closeGate()`.
  - **`terminate`** (verified):

```swift
func terminate(_ process: NSRunningApplication) {
    let pid = process.processIdentifier
    guard !pendingTermination.contains(pid) else { return }
    pendingTermination.insert(pid)
    process.terminate()
    let t = Timer(timeInterval: Constants.forceQuitAfter, repeats: false) { _ in
        MainActor.assumeIsolated {
            if let p = NSRunningApplication(processIdentifier: pid), !p.isTerminated { p.forceTerminate() }
        }
    }
    t.tolerance = 0.5
    RunLoop.main.add(t, forMode: .common)
}
```

- [ ] **Step 4: `OverlayPanel.swift`** (verified)

```swift
import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    private let allowsKey: Bool

    init(allowsKey: Bool) {
        self.allowsKey = allowsKey
        super.init(contentRect: .zero,
                   styleMask: allowsKey ? [.borderless] : [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = allowsKey ? .modalPanel : .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    func setRoot<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }
}
```

- [ ] **Step 5: `OverlayController.swift` and `GateSession`**

**Gate:**
- **`showGate(app:process:)`:**
  1. Return if `gateOwnerPID == process.processIdentifier`.
  2. Close any existing gate.
  3. Create a `GateSession` with `pauseEndsAt = Date() + core.setting(.gatePauseSeconds)`.
  4. Create `OverlayPanel(allowsKey: true)`, `setRoot(GateView(...))`, and center it in the `visibleFrame` of the screen containing `NSEvent.mouseLocation` (fallback `NSScreen.main`).
  5. Call `NSApp.activate()`, then `panel.makeKeyAndOrderFront(nil)`.
  6. Start a 1 s `RepeatingUITimer` (gate clock) and a 0.5 s `RepeatingUITimer` (re-hide: `if !session.process.isHidden { session.process.hide() }`).
- **Gate clock tick:** `session.now = Date()`. If `Date() − session.lastInteraction ≥ Constants.gateTimeout`, run Never mind.
- **Never mind:** `model.perform { $0.recordBackedOff(appID:) }`, capture the process, `closeGate()`, then `model.enforcer.terminate(process)`.
- **Quick look(n):** `session.touch()`, then `try model.perform { try $0.buyQuickLook(appID:tokens:appLaunchDate: session.process.launchDate) }`.
  - On success, run the verified hand-off:

```swift
let process = session.process
closeGate()
process.unhide()
NSApp.yieldActivation(to: process)
process.activate()
updatePill()
```

  - On `EngineError`, set `session.errorMessage = error.userMessage`.
- **`closeGate()`:** stop both timers, `orderOut` the panel, clear the session, panel, and `gateOwnerPID`.

**Pill:**
- **`updatePill()`:** if `model.grantCountdown == nil`, close the pill panel and stop its timer.
- Otherwise, if no pill panel exists:
  - Create `OverlayPanel(allowsKey: false)` with a **fixed** content size of 320×72, content right-aligned so the capsule hugs the right edge.
  - `setRoot(PillView(model:))`.
  - Place it at the top-right of `NSScreen.main!.visibleFrame` with a 12 pt inset.
  - `orderFrontRegardless()`.
  - Start a 1 s `RepeatingUITimer` that calls `updatePill()`. `PillView` re-renders from `model.uiNow`, which the label timer bumps.

- [ ] **Step 6: Views**

**`GateView`** (spec §7.3, Run 1 subset; styling §9):
- **Stable layout** (the panel is sized once): the order is
  1. icon with the pause ring
  2. title
  3. subtitle
  4. status line: `"Options unlock in Ns"` while pausing, otherwise a blank line
  5. options area
  6. error line: `session.errorMessage ?? " "`
  7. **Never mind**

  Width 420, padding 24, `.regularMaterial` background with radius 22 and a 1 pt `Color(nsColor: .separatorColor)` stroke.
- **Icon:** `NSWorkspace.shared.icon(forFile: session.process.bundleURL?.path ?? "")` at 64 pt. Around it, a 3 pt `Theme.accent` ring trimmed to the remaining pause fraction, `.rotationEffect(.degrees(-90))`, with `.animation(.linear(duration: 1), value: session.now)`.
- **Title:** `"Still want to open \(session.app.name)?"`, `.title3.weight(.semibold)`.
- **Subtitle:** `"\(n) \(n == 1 ? "token" : "tokens") · 1 token = \(P / 60) min of focus"`, secondary.
- **Options area:**
  - Only if `session.app.modes.contains(.quickLook)`.
  - If `tokens == 0`: `"No tokens yet. Your next one is \(DurationFormat.short(core.secondsToNextToken)) of focus away."` (no button in Run 1).
  - Otherwise, a card (`.quaternary.opacity(0.5)`, radius 12) with:
    - "Quick look" and `"\(quickLookSecondsPerToken) s per token"`
    - `Stepper(value: $session.quickLookTokens, in: 1...min(quickLookMaxTokens, tokens))`
    - button `"Open for \(DurationFormat.clock(Double(n × sec))) · \(n) ◆"`, disabled while `session.isPausing`
  - Wrap the session as `@Bindable var session: GateSession`.
- **Never mind:** `Button { onNeverMind() } label: { Text("Never mind").frame(maxWidth: .infinity) }` with `.buttonStyle(.borderedProminent)`, `.controlSize(.large)`, `.keyboardShortcut(.cancelAction)`. Never disabled. Any other click calls `session.touch()`.
- **Accessibility:** honor Reduce Motion (no scale animation).

**`PillView`** (§7.5):
- Reads `model.uiNow`. If `model.grantCountdown` is `nil`, render nothing.
- **Content:** a capsule (`.thickMaterial`) with the 18 pt app icon and `"\(app.name) · \(DurationFormat.clock(remaining))"` (or `"Emergency · …"` for emergency grants), monospaced digits.
- **Reply grants:** a second caption line `"“\(note)”"` with `lineLimit(1)`.
- **Last 10 s:** when `remaining ≤ Constants.extendWindow`, the text and icon tint turn `Theme.warm` with `.animation(.easeInOut(duration: 0.3), value: warm)`. If `model.core.canExtend(grantID:)`, show a button `"+\(quickLookSecondsPerToken) s · 1 ◆"` that calls `model.perform { try? $0.extendGrant(grantID: id) }`.

**`MenuBarLabel`** (§7.1, rows 1 and 5 only in Run 1): verified form.

```swift
HStack(spacing: 4) {
    Image(systemName: countdown == nil ? "diamond.fill" : "hourglass")
    Text(prefix + (countdown.map { DurationFormat.clock($0.remaining) } ?? "\(model.core.state.tokens)")).monospacedDigit()
}
```

- `prefix` is `"DEV "` when `Constants.isDev`.
- Read `model.uiNow` in the body so it re-renders.
- If the menu bar shows only the image, fall back to a single `Text("\(Image(systemName: …)) \(text)")` and record it in the notes.

**`PopoverView`** (Run 1 panel):
- `VStack(alignment: .leading, spacing: 16)`, padding 16, width 320:
  1. `Text("myTime").font(.headline)`
  2. Tokens row: `"◆ \(n) \(n == 1 ? "token" : "tokens")"` and, right-aligned in secondary, `"Resets at \(DurationFormat.hourOfDay(core.setting(.dayStartHour), locale: .current))"`
  3. `#if DEV_TIMESCALE` row of buttons:
     - "+1 token" → `model.perform { $0.devAddToken() }`
     - "+5 min progress" → `model.perform { $0.devAddProgress(seconds: 300) }`
     - "New day" → `model.perform { $0.devSimulateNewDay() }`
     - "Reset state" → `model.devReset()`
- `.onAppear { model.panelDidOpen() }` and `.onDisappear { model.panelDidClose() }`.

- [ ] **Step 7: Build both variants and run tests**

Run: `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`
Expected: `Build complete!` twice, all tests pass. Deprecation warnings are acceptable; errors are not.

- [ ] **Step 8: Build release binaries the way `scripts/build.sh` does** (compile only, no install)

Run: `swift build -c release --arch arm64 && swift build -c release --arch arm64 -Xswiftc -DDEV_TIMESCALE`
Expected: `Build complete!` twice.

- [ ] **Step 9: Checkpoint** — all pass. Do not commit.

---

### Task 10: Run documentation and final verification

**Files:**
- Create: `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md`

- [ ] **Step 1: Write `docs/MANUAL_TESTS.md`** with a top line `Run each step against scripts/build.sh --dev unless noted.`, then a `## Run 1` section containing steps 1–7 from spec §11.2, copied verbatim with their expected results.

- [ ] **Step 2: Write `IMPLEMENTATION_NOTES.md`** with a `## Run 1` section that has three subsections:
  - `### Deviations`: each with what, why, and what you did instead, or "None."
  - `### Not verified`: at minimum, everything that needs the installed app (all manual tests), plus anything else.
  - `### Commands run`: each command with a one-line result.

- [ ] **Step 3: Final verification**

Run:

```bash
swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test && swift build -c release --arch arm64 -Xswiftc -DDEV_TIMESCALE
```

Expected: every build prints `Build complete!` and tests report `0 failures`. Paste the test summary line into the notes.

- [ ] **Step 4: Stop.** Do not start Run 2 and do not commit. Reply with a short summary: what was built, test count, and any deviations.

---

## Self-review record (reviewer)

**Spec coverage for Run 1 (§12):**

| Spec item | Task |
|---|---|
| Package, Info.plist, scripts | 1 |
| SettingKey, Constants, DurationFormat | 2 |
| TrustedClock, CalendarKeys | 3 |
| All model types | 4 |
| StateCodec, tamper penalty | 5 |
| EnforcementPolicy, WakeUpPlanner | 6 |
| EngineCore: init/start/update steps 1·2·5·8, daily reset, quick look, extend, expiry, isAllowed, backed off, DEV helpers | 7 |
| SystemProbe, StateStore, Installer (install + self-heal), Scheduler, SystemEvents, AppMonitor, Theme | 8 |
| main modes, AppModel refresh, Enforcer, OverlayPanel, gate (pause / Never mind / quick look / no-tokens), pill, menu bar diamond + hourglass, minimal panel + DEV row, startup sweep, activity assertion | 9 |
| Tests for TrustedClock, CalendarKeys, daily reset, grants, StateCodec, EnforcementPolicy, WakeUpPlanner | 2–7 |
| Manual steps 1–7, implementation notes | 10 |

**Deferred by design:**
- Run 2: focus accrual, claims, focus card
- Run 3: reply mode, bookings, emergency
- Run 4: settings policy, settings window, uninstall
