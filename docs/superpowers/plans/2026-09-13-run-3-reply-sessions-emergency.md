# myTime Run 3 — Reply Mode, Sessions, Emergency — Implementation Plan

> **For the implementing agent (Codex):** Work through the tasks **in order**. Steps use checkbox (`- [ ]`) syntax. Read `AGENTS.md` first. **Do not commit**; the reviewer commits.

**Goal:** Three more ways past the gate. **Reply mode** spends tokens for a few minutes with a written purpose. **Booked sessions** come from a weekly allowance, are booked ahead in a Booking window, show a heads-up before they end, and close the app when they end. The **emergency pass** gives once-a-week access after a reason and a wait.

**Architecture:** All rules live in `MyTimeCore`:
- `ReplyAndEmergency.swift`: reply mode and the emergency pass
- `BookingRules.swift`: validation, allowance, intents, and booking-window choices, plus `update` step 6 transitions
- `DurationFormat` helpers for session times

The app layer adds:
- gate cards and the emergency sub-flow (state on `GateSession`)
- a Booking window through `WindowRouter`
- the panel Sessions block
- a heads-up overlay
- the menu bar booking row

The only new timer is the 60 s menu bar booking label (spec §3.6), plus the heads-up's one-shot 8 s auto-hide.

**Tech Stack:** Swift 6 toolchain in Swift 5 mode, SwiftPM, XCTest, AppKit, SwiftUI. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-09-13-mytime-design.md` (revision 3). Sections: §3.6, §4.9, §5 (API, update order), §5.3 reply, §5.4 bookings, §5.5 emergency, §6.4–§6.5, §7 formatting helpers, §7.1, §7.2 item 6, §7.3, §7.5, §7.6, §7.8, §7.10, §11.1–§11.2.

---

## How to work

### Since Run 2

- Run 2 was clean. Keep doing the same: tests verbatim, rules as written, readable code, every deviation recorded.
- **Reviewer changes after Run 2 that you'll build on:**
  - There is **no launch grace**. `buyQuickLook(appID:tokens:)` has no `appLaunchDate`, `AccessGrant` has no `startsAt`, and a grant's countdown starts when it's bought. Reply and emergency grants work the same way.
  - Saves from the 1 s `.panel` and `.uiTick` refreshes are throttled to once a minute (`RefreshReason.isUITick`). Don't change that.

### Latitude

- **You decide:**
  - internal code and private helpers
  - view composition and styling within spec §9
  - splitting files over ~300 lines (suggested splits are below)
  - fixing a snippet that doesn't compile or behave on the real OS
- **You must keep:**
  - every behavior, number, and piece of copy in the spec
  - every **public** name and signature under "Interfaces"
  - every test, verbatim
  - spec §13 hard rules
- **If you think the spec or plan is wrong:** implement the closest working behavior and record it under `## Run 3` in `IMPLEMENTATION_NOTES.md`.

### Environment

- Build locally on the Mac. Run only `swift build …` and `swift test`.
- Don't run `scripts/build.sh`, `scripts/uninstall.sh`, or `launchctl`.
- Tests run without `DEV_TIMESCALE`, so they see release values. For the numbers used here, see the doc comment at the top of each test file.

---

## Global Constraints

- Swift 5 language mode.
- UI and engine classes are `@MainActor`; use `Timer` with `MainActor.assumeIsolated`; no `Task.sleep` loops.
- **No new repeating timers** except the 60 s menu bar booking label (§3.6), which runs only while that label is showing. Every `Timer` sets `tolerance`.
- `MyTimeCore` imports only Foundation/CryptoKit and never reads the clock.
- Public Core API gets explicit `public init`s.
- Copy is verbatim from the spec: calm, no exclamation marks, no red, no sounds.
- **Nothing in the gate is bound to Return.** Never mind is the only prominent button (§7.3).
- Enforcement stays quit-first (§5.8/§6). Successful reply or emergency: buy, close the gate, relaunch the app, exactly like quick look.
- Readable formatting (AGENTS.md rule 6). Tests verbatim (AGENTS.md rule 7).

---

## Current code you'll build on

- **`EngineCore` (`Logic/EngineCore.swift`):**
  - `update` runs clock → daily reset → `accrueFocus` → grant expiry (builds `effects`) → planner.
  - Helpers: `updateToday`, `record`, `vest`, `setting`, `app(id:)`, `activeBooking`, `today`, `dayStartHour`, `timeZone`.
  - `Booking` (`Model/Booking.swift`) already has `end`, `isUpcoming(at:)`, `isActive(at:)`, `isFinished(at:)`.
  - `EngineError` already has every case and message, and `WakeUpPlanner` already plans booking heads-up and end.
  - `EngineEffect` already has `.bookingHeadsUp(bookingID:)` and `.uninstall`. `AppModel` currently only handles `.terminateIfNotAllowed`.
- **`OverlayController` (`UI/OverlayController.swift`, 262 lines):**
  - `GateSession`, with app, bundleURL, mode, icon, pause, now, lastInteraction, quickLookTokens, errorMessage, and `touch()`
  - `GateMode`
  - `show(app:bundleURL:mode:)`, `syncGateMode`, `closeGate`
  - actions `neverMind`, `startFocus`, `backToWork`, `endFocus`, `quickLook(_:)`
  - `relaunch(_:)`, `updatePill`
  - the 1 s `gateClock` that updates `session.now` and applies the 60 s timeout
- **`GateView`:** `OverlayActions` struct, pause ring, quick look card, and the no-tokens text with Start Focus.
- **`PillView`:** already shows the reply note line and the "Emergency" label.
- **`PopoverView`:** header, focus block, claim row, tokens row, today strip, DEV row.
- **`AppModel`:** `refresh`, `perform`, `grantCountdown`, `ringStep`, `showsClaimDot`, `updateActivityAndTimers` (the activity assertion already includes `core.activeBooking != nil`), `displayNow`, `monitor`, `uiNow`.
- **Verified on this Mac:** an `NSHostingView` panel grows and shrinks with its SwiftUI content and keeps its top edge. The gate needs no manual resizing when the emergency flow changes its height.

---

## File map for Run 3

| File | Change | Task |
|---|---|---|
| `Sources/MyTimeCore/Logic/ReplyAndEmergency.swift` | **new**: `replyUnavailableReason`, `buyReply`, `emergencyUsesLeftThisWeek`, `useEmergency` | 1 |
| `Tests/MyTimeCoreTests/ReplyTests.swift`, `EmergencyTests.swift` | **new** | 1 |
| `Sources/MyTimeCore/Logic/BookingRules.swift` | **new**: charged seconds, allowance, validation, intents, choices | 2 |
| `Tests/MyTimeCoreTests/BookingRulesTests.swift` | **new** | 2 |
| `Sources/MyTimeCore/Logic/BookingRules.swift`, `EngineCore.swift` | step 6 transitions and effect merge | 3 |
| `Sources/MyTimeCore/Logic/DurationFormat.swift` | `timeOfDay`, `dayLabel`, `sessionStart` | 3 |
| `Tests/MyTimeCoreTests/BookingTransitionTests.swift`, `SessionTimeFormatTests.swift` | **new** | 3 |
| `Sources/MyTimeApp/UI/GateSession.swift` | **new**: `GateSession` + `GateMode` + `GateStep`, moved out of `OverlayController.swift` | 4 |
| `Sources/MyTimeApp/UI/GateView.swift`, **new** `GateCards.swift`, **new** `EmergencyFlowView.swift` | reply card, sessions line, footer, emergency sub-flow | 4 |
| `Sources/MyTimeApp/UI/OverlayController.swift` | `reply`, `openEmergency`, `bookSession` actions; emergency wait in the gate clock; `pillFrame` | 4 |
| `Sources/MyTimeApp/Engine/WindowRouter.swift` | **new** | 5 |
| `Sources/MyTimeApp/UI/BookingView.swift`, **new** `SessionsBlock.swift` | Booking window, panel Sessions block | 5 |
| `Sources/MyTimeApp/UI/PopoverView.swift` | insert `SessionsBlock` | 5 |
| `Sources/MyTimeApp/UI/HeadsUpController.swift`, `HeadsUpView.swift` | **new** | 6 |
| `Sources/MyTimeApp/Engine/AppModel.swift` | `router`, `headsUp`, effect switch, booking intents, `bookingCountdown`, booking label timer, claim dot rule | 5–6 |
| `Sources/MyTimeApp/UI/MenuBarLabel.swift` | booking row | 6 |
| `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md` | Run 3 sections | 7 |

---

### Task 1: Reply mode and the emergency pass

**Files:**
- Create: `Sources/MyTimeCore/Logic/ReplyAndEmergency.swift`
- Test: `Tests/MyTimeCoreTests/ReplyTests.swift`, `Tests/MyTimeCoreTests/EmergencyTests.swift`

**Interfaces:**
- Consumes: `app(id:)`, `setting(_:)`, `today`, `updateToday`, `record`, `endFocus()`, `CalendarKeys.weekKey`, `Constants.minReplyNote`, `Constants.minEmergencyReason`.
- Produces:

```swift
extension EngineCore {
    public func replyUnavailableReason(appID: UUID, note: String) -> EngineError?
    public mutating func buyReply(appID: UUID, note: String) throws -> AccessGrant
    public var emergencyUsesLeftThisWeek: Int { get }
    public mutating func useEmergency(appID: UUID, reason: String) throws -> AccessGrant
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/ReplyTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

/// Reply mode (spec §5.3). Release values: 2 tokens, 3 minutes, 3 per day, note of at least 8 characters.
final class ReplyTests: XCTestCase {
    func testReplySpendsTokensAndKeepsTheTrimmedNote() throws {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10), tokens: 5)
        let discord = core.state.settings.apps[0].id
        let grant = try core.buyReply(appID: discord, note: "  reply to Sam in #capstone \n")
        XCTAssertEqual(grant.kind, .reply)
        XCTAssertEqual(grant.note, "reply to Sam in #capstone")
        XCTAssertEqual(grant.tokensSpent, 2)
        XCTAssertEqual(grant.expiresAt, core.now.addingTimeInterval(180))
        XCTAssertEqual(core.state.tokens, 3)
        XCTAssertEqual(core.today.tokensSpent, 2)
        XCTAssertEqual(core.today.replies, 1)
        XCTAssertTrue(core.isAllowed(appID: discord))
        XCTAssertEqual(core.state.history.last?.kind, .reply)
        XCTAssertEqual(core.state.history.last?.text, "Reply mode in Discord — “reply to Sam in #capstone”")
    }

    /// `replyUnavailableReason` reports exactly what `buyReply` would throw, without changing anything.
    func testReplyErrorsInOrder() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10), tokens: 1)
        let discord = core.state.settings.apps[0].id
        func expect(_ error: EngineError, note: String, app: UUID? = nil) {
            XCTAssertEqual(core.replyUnavailableReason(appID: app ?? discord, note: note), error)
            XCTAssertThrowsError(try core.buyReply(appID: app ?? discord, note: note)) {
                XCTAssertEqual($0 as? EngineError, error)
            }
        }
        expect(.unknownApp, note: "reply to Sam", app: UUID())
        core.state.settings.apps[0].modes = [.quickLook]
        expect(.modeNotAllowed, note: "reply to Sam")
        core.state.settings.apps[0].modes = [.reply]
        core.state.focus = FocusSession(startedAt: core.now)
        expect(.focusActive, note: "reply to Sam")
        core.state.focus = nil
        expect(.noteTooShort, note: "  1234567  ")
        core.updateToday { $0.replies = 3 }
        expect(.notEnoughTokens, note: "12345678")
        core.state.tokens = 2
        expect(.replyLimitReached, note: "12345678")
        XCTAssertEqual(core.state.tokens, 2)
        XCTAssertTrue(core.state.grants.isEmpty)
        core.updateToday { $0.replies = 2 }
        XCTAssertNil(core.replyUnavailableReason(appID: discord, note: "12345678"))
    }

    func testReplyLimitIsFreshOnTheNewDay() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 3, 30), tokens: 4)
        let discord = core.state.settings.apps[0].id
        core.updateToday { $0.replies = 3 }
        XCTAssertEqual(core.replyUnavailableReason(appID: discord, note: "reply to Sam"), .replyLimitReached)
        sim.advance(3600)
        _ = core.update(sim.input)
        core.state.tokens = 2
        XCTAssertNil(core.replyUnavailableReason(appID: discord, note: "reply to Sam"))
        _ = try core.buyReply(appID: discord, note: "reply to Sam")
        XCTAssertEqual(core.today.replies, 1)
    }

    func testReplyAccessCanBeExtendedInItsLastSeconds() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10), tokens: 3)
        let discord = core.state.settings.apps[0].id
        let grant = try core.buyReply(appID: discord, note: "reply to Sam")
        sim.advance(169)
        _ = core.update(sim.input)
        XCTAssertFalse(core.canExtend(grantID: grant.id))
        sim.advance(1)
        _ = core.update(sim.input)
        XCTAssertTrue(core.canExtend(grantID: grant.id))
        try core.extendGrant(grantID: grant.id)
        XCTAssertEqual(core.activeGrant(appID: discord)?.expiresAt, grant.expiresAt.addingTimeInterval(30))
        XCTAssertEqual(core.state.tokens, 0)
    }
}
```

`Tests/MyTimeCoreTests/EmergencyTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

/// Emergency pass (spec §5.5). Release values: 1 per week, 10 minutes of access, reason of at least 15 characters.
/// 2026-09-14 is a Monday; its week key is "2026-W38".
final class EmergencyTests: XCTestCase {
    func testEmergencyGrantsAccessOncePerWeekWhateverTheAppsModes() throws {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0].id
        core.state.settings.apps[0].modes = []
        XCTAssertEqual(core.emergencyUsesLeftThisWeek, 1)
        let grant = try core.useEmergency(appID: discord, reason: "  teammate needs the build link  ")
        XCTAssertEqual(grant.kind, .emergency)
        XCTAssertEqual(grant.tokensSpent, 0)
        XCTAssertEqual(grant.note, "teammate needs the build link")
        XCTAssertEqual(grant.expiresAt, core.now.addingTimeInterval(600))
        XCTAssertTrue(core.isAllowed(appID: discord))
        XCTAssertEqual(core.emergencyUsesLeftThisWeek, 0)
        XCTAssertEqual(core.state.weekly["2026-W38"]?.emergencyUses, 1)
        XCTAssertEqual(core.state.history.last?.kind, .emergency)
        XCTAssertEqual(
            core.state.history.last?.text, "Emergency access to Discord — “teammate needs the build link”")
        XCTAssertThrowsError(try core.useEmergency(appID: discord, reason: "teammate needs the build link")) {
            XCTAssertEqual($0 as? EngineError, .emergencyUnavailable)
        }
    }

    func testEmergencyErrorsInOrder() {
        var (core, _) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0].id
        XCTAssertThrowsError(try core.useEmergency(appID: UUID(), reason: "teammate needs the build link")) {
            XCTAssertEqual($0 as? EngineError, .unknownApp)
        }
        core.state.weekly["2026-W38"] = WeeklyStats(emergencyUses: 1)
        XCTAssertThrowsError(try core.useEmergency(appID: discord, reason: "  abcdefghijklmn  ")) {
            XCTAssertEqual($0 as? EngineError, .reasonTooShort)
        }
        XCTAssertThrowsError(try core.useEmergency(appID: discord, reason: "abcdefghijklmno")) {
            XCTAssertEqual($0 as? EngineError, .emergencyUnavailable)
        }
        XCTAssertTrue(core.state.grants.isEmpty)
        core.state.weekly = [:]
        XCTAssertNoThrow(try core.useEmergency(appID: discord, reason: "abcdefghijklmno"))
    }

    func testEmergencyEndsFocusAndKeepsItsCredit() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let discord = core.state.settings.apps[0].id
        core.startFocus()
        sim.advance(100)
        sim.idle = 20
        _ = core.update(sim.input)
        _ = try core.useEmergency(appID: discord, reason: "teammate needs the build link")
        XCTAssertNil(core.state.focus)
        XCTAssertEqual(core.today.focusSeconds, 100, accuracy: 0.001)
        XCTAssertTrue(core.state.history.contains { $0.text == "Focus ended · 2 min" })
    }

    func testThePassReturnsMondayAtDayStart() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 20, 23))
        let discord = core.state.settings.apps[0].id
        _ = try core.useEmergency(appID: discord, reason: "teammate needs the build link")
        sim.advance(4 * 3600 + 59 * 60)  // Monday 03:59
        _ = core.update(sim.input)
        XCTAssertEqual(core.emergencyUsesLeftThisWeek, 0)
        sim.advance(60)  // Monday 04:00
        _ = core.update(sim.input)
        XCTAssertEqual(core.emergencyUsesLeftThisWeek, 1)
    }

    func testEmergencyAccessCannotBeExtended() throws {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10), tokens: 3)
        let discord = core.state.settings.apps[0].id
        let grant = try core.useEmergency(appID: discord, reason: "teammate needs the build link")
        sim.advance(595)
        _ = core.update(sim.input)
        XCTAssertFalse(core.canExtend(grantID: grant.id))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "ReplyTests|EmergencyTests"`
Expected: compile errors (`buyReply` / `useEmergency` not found).

- [ ] **Step 3: Implement** spec §5.3 "buyReply" and §5.5 exactly.
- Trim with `.whitespacesAndNewlines`.
- **`replyUnavailableReason`:** return the first failing check, in this order:
  1. unknown app → `.unknownApp`
  2. no `.reply` → `.modeNotAllowed`
  3. focusing → `.focusActive`
  4. trimmed count < `Constants.minReplyNote` → `.noteTooShort`
  5. `tokens < replyTokenCost` → `.notEnoughTokens`
  6. `today.replies >= replyPerDay` → `.replyLimitReached`

  Otherwise return `nil`.
- **`buyReply`:** throw that reason if there is one. Otherwise:
  - `tokens -= cost`, `today.tokensSpent += cost`, `today.replies += 1`
  - append a `.reply` grant (`expiresAt = now + replySeconds`, `tokensSpent = cost`, `note = trimmed`)
  - record `.reply` / `"Reply mode in \(app.name) — “\(trimmed)”"` (curly quotes, em dash)
- **`emergencyUsesLeftThisWeek`:** `max(0, emergencyPerWeek − weekly[weekKey(now)].emergencyUses)`. The week key uses `dayStartHour` and `timeZone`.
- **`useEmergency`:**
  - Throws, in this order: `.unknownApp`, then `.reasonTooShort`, then `.emergencyUnavailable`.
  - Then `weekly[weekKey(now)].emergencyUses += 1`, and `endFocus()` if focusing.
  - Append an `.emergency` grant (`expiresAt = now + emergencyAccessSeconds`, `tokensSpent 0`, `note = trimmed`).
  - Record `.emergency` / `"Emergency access to \(app.name) — “\(trimmed)”"`.
  - Don't check the app's modes.

- [ ] **Step 4: Run tests** — `swift test`, all pass.

- [ ] **Step 5: Checkpoint.** Do not commit.

---

### Task 2: Booking rules, intents, and booking-window choices

**Files:**
- Create: `Sources/MyTimeCore/Logic/BookingRules.swift`
- Test: `Tests/MyTimeCoreTests/BookingRulesTests.swift`

**Interfaces:**
- Consumes: `Booking` helpers, `activeBooking`, `CalendarKeys.weekKey`, `Constants.booking*`, `setting(.weeklyAllowanceSeconds / .bookingLeadSeconds / .bookingMaxSeconds / .bookingExtensionSeconds)`.
- Produces:

```swift
extension EngineCore {
    func chargedSeconds(of booking: Booking) -> Int          // internal; tests use it via @testable
    public func allowanceRemaining(weekOf date: Date) -> Int
    public func validateBooking(start: Date, durationSeconds: Int) -> EngineError?
    public mutating func createBooking(start: Date, durationSeconds: Int) throws -> Booking
    public mutating func cancelBooking(id: UUID) throws
    public mutating func endBooking(id: UUID)
    public func canExtendBooking(id: UUID) -> Bool
    public mutating func extendBooking(id: UUID) throws
    public var upcomingBookings: [Booking] { get }
    public var bookingDurations: [Int] { get }
    public func bookingDays() -> [Date]
    public func bookingStartSlots(onDayOf day: Date) -> [Date]
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/BookingRulesTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

/// Booked sessions (spec §5.4). Release values: book ≥ 10 min ahead and ≤ 7 days ahead; 30 min–3 h in 15 min steps;
/// 5 h per week; one +15 min extension; start slots every 5 min.
final class BookingRulesTests: XCTestCase {
    private let monday10 = date(2026, 9, 14, 10)

    func testValidationRulesInOrder() throws {
        var (core, _) = makeEngine(at: monday10)
        let now = core.now
        func check(_ minutesAhead: Double, _ duration: Int) -> EngineError? {
            core.validateBooking(start: now.addingTimeInterval(minutesAhead * 60), durationSeconds: duration)
        }
        XCTAssertEqual(check(9, 1800), .bookingTooSoon(leadSeconds: 600))
        XCTAssertEqual(check(9, 900), .bookingTooSoon(leadSeconds: 600))
        XCTAssertNil(check(10, 1800))
        XCTAssertEqual(check(7 * 24 * 60 + 1, 1800), .bookingTooFar)
        XCTAssertNil(check(7 * 24 * 60, 1800))
        XCTAssertEqual(check(60, 900), .invalidDuration(minSeconds: 1800, maxSeconds: 10800))
        XCTAssertEqual(check(60, 11700), .invalidDuration(minSeconds: 1800, maxSeconds: 10800))
        XCTAssertEqual(check(60, 2000), .invalidDuration(minSeconds: 1800, maxSeconds: 10800))
        XCTAssertNil(check(60, 10800))

        _ = try core.createBooking(start: now.addingTimeInterval(3600), durationSeconds: 3600)  // 11:00–12:00
        XCTAssertEqual(check(90, 1800), .bookingOverlap)
        XCTAssertEqual(check(30, 3600), .bookingOverlap)
        XCTAssertNil(check(120, 1800))
        XCTAssertNil(check(30, 1800))

        _ = try core.createBooking(start: now.addingTimeInterval(3 * 3600), durationSeconds: 10800)  // 13:00–16:00
        XCTAssertEqual(core.allowanceRemaining(weekOf: now), 3600)
        XCTAssertEqual(check(7 * 60, 4500), .allowanceExceeded)
        XCTAssertNil(check(7 * 60, 3600))
    }

    func testCanceledAndEndedSessionsDoNotBlockNewBookings() throws {
        var (core, sim) = makeEngine(at: monday10)
        let canceled = try core.createBooking(start: core.now.addingTimeInterval(3600), durationSeconds: 1800)  // 11:00
        try core.cancelBooking(id: canceled.id)
        XCTAssertNil(core.validateBooking(start: core.now.addingTimeInterval(3600), durationSeconds: 1800))
        let ended = try core.createBooking(start: core.now.addingTimeInterval(900), durationSeconds: 7200)  // 10:15–12:15
        sim.advance(1800)  // 10:30
        _ = core.update(sim.input)
        core.endBooking(id: ended.id)
        XCTAssertNil(core.validateBooking(start: core.now.addingTimeInterval(900), durationSeconds: 1800))  // 10:45
    }

    func testCreateBookingRecordsHistoryAndRejectsInvalidRequests() throws {
        var (core, _) = makeEngine(at: monday10)
        let booking = try core.createBooking(start: core.now.addingTimeInterval(1800), durationSeconds: 3600)
        XCTAssertEqual(core.state.bookings, [booking])
        XCTAssertEqual(booking.createdAt, core.now)
        XCTAssertEqual(booking.extensionSeconds, 0)
        XCTAssertFalse(booking.appOpened)
        XCTAssertEqual(core.state.history.last?.kind, .bookingCreated)
        XCTAssertEqual(core.state.history.last?.text, "Booked a session · 1h")
        XCTAssertThrowsError(try core.createBooking(start: core.now.addingTimeInterval(60), durationSeconds: 3600)) {
            XCTAssertEqual($0 as? EngineError, .bookingTooSoon(leadSeconds: 600))
        }
        XCTAssertEqual(core.state.bookings.count, 1)
    }

    func testChargedSecondsFollowWhatHappened() throws {
        var (core, sim) = makeEngine(at: monday10)
        let discord = core.state.settings.apps[0].id
        let canceled = try core.createBooking(start: core.now.addingTimeInterval(1800), durationSeconds: 1800)  // 10:30
        _ = try core.createBooking(start: core.now.addingTimeInterval(3600), durationSeconds: 1800)  // 11:00, never opened
        let early = try core.createBooking(start: core.now.addingTimeInterval(5400), durationSeconds: 3600)  // 11:30
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 7200)
        try core.cancelBooking(id: canceled.id)
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 5400)

        sim.advance(5400 + 1)  // 11:30:01: the 11:00 session finished unopened; the 11:30 one is live
        _ = core.update(sim.input)
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 3600)
        sim.running = [discord]
        sim.advance(619)  // 11:40:20
        _ = core.update(sim.input)
        core.endBooking(id: early.id)
        XCTAssertEqual(core.chargedSeconds(of: core.state.bookings[0]), 0)
        XCTAssertEqual(core.chargedSeconds(of: core.state.bookings[1]), 0)
        XCTAssertEqual(core.chargedSeconds(of: core.state.bookings[2]), 660)  // 10 min 20 s, rounded up
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 660)
    }

    func testAllowanceIsCountedByTheWeekASessionStartsIn() throws {
        var (core, _) = makeEngine(at: date(2026, 9, 18, 10))  // Friday
        _ = try core.createBooking(start: date(2026, 9, 20, 23), durationSeconds: 3600)  // Sunday night
        _ = try core.createBooking(start: date(2026, 9, 21, 3), durationSeconds: 1800)  // Monday 3 AM: same week
        _ = try core.createBooking(start: date(2026, 9, 21, 4), durationSeconds: 2700)  // Monday 4 AM: next week
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 5400)
        XCTAssertEqual(core.allowanceRemaining(weekOf: date(2026, 9, 21, 12)), 18000 - 2700)
        core.state.weekly["2026-W38"] = WeeklyStats(allowanceForfeited: true)
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 0)
        XCTAssertEqual(core.allowanceRemaining(weekOf: date(2026, 9, 21, 12)), 18000 - 2700)
    }

    func testOnlyUpcomingSessionsCanBeCanceled() throws {
        var (core, sim) = makeEngine(at: monday10)
        let soon = try core.createBooking(start: core.now.addingTimeInterval(600), durationSeconds: 1800)
        let later = try core.createBooking(start: core.now.addingTimeInterval(7200), durationSeconds: 2700)
        try core.cancelBooking(id: later.id)
        XCTAssertEqual(core.state.bookings[1].canceledAt, core.now)
        XCTAssertEqual(core.state.history.last?.kind, .bookingCanceled)
        XCTAssertEqual(core.state.history.last?.text, "Canceled a session · 45 min")
        XCTAssertThrowsError(try core.cancelBooking(id: later.id)) {
            XCTAssertEqual($0 as? EngineError, .cannotCancel)
        }
        sim.advance(600)
        _ = core.update(sim.input)
        XCTAssertThrowsError(try core.cancelBooking(id: soon.id)) {
            XCTAssertEqual($0 as? EngineError, .cannotCancel)
        }
        XCTAssertThrowsError(try core.cancelBooking(id: UUID())) {
            XCTAssertEqual($0 as? EngineError, .cannotCancel)
        }
    }

    func testExtensionRules() throws {
        var (core, sim) = makeEngine(at: monday10)
        let live = try core.createBooking(start: core.now.addingTimeInterval(600), durationSeconds: 1800)  // 10:10–10:40
        _ = try core.createBooking(start: core.now.addingTimeInterval(3300), durationSeconds: 1800)  // 10:55–11:25
        XCTAssertFalse(core.canExtendBooking(id: live.id))  // not live yet
        sim.advance(900)  // 10:15
        _ = core.update(sim.input)
        XCTAssertEqual(core.activeBooking?.id, live.id)
        XCTAssertTrue(core.canExtendBooking(id: live.id))  // the new end, 10:55, touches the next session
        try core.extendBooking(id: live.id)
        XCTAssertEqual(core.activeBooking?.extensionSeconds, 900)
        XCTAssertEqual(core.activeBooking?.end, date(2026, 9, 14, 10, 55))
        XCTAssertEqual(core.state.history.last?.kind, .bookingExtended)
        XCTAssertEqual(core.state.history.last?.text, "Extended session · +15 min")
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 2700 - 1800)
        XCTAssertFalse(core.canExtendBooking(id: live.id))  // only once
        XCTAssertThrowsError(try core.extendBooking(id: live.id)) {
            XCTAssertEqual($0 as? EngineError, .cannotExtendBooking)
        }
    }

    func testExtensionIsRefusedWhenItWouldOverlapOrExceedTheAllowance() throws {
        var (core, sim) = makeEngine(at: monday10)
        let live = try core.createBooking(start: core.now.addingTimeInterval(600), durationSeconds: 1800)  // 10:10–10:40
        _ = try core.createBooking(start: core.now.addingTimeInterval(3000), durationSeconds: 1800)  // 10:50–11:20
        sim.advance(900)
        _ = core.update(sim.input)
        XCTAssertFalse(core.canExtendBooking(id: live.id))  // 10:55 would overlap 10:50

        core.state.bookings.removeLast()
        core.state.settings[.weeklyAllowanceSeconds] = 2700  // 1800 used, exactly 900 left
        XCTAssertTrue(core.canExtendBooking(id: live.id))
        core.state.settings[.weeklyAllowanceSeconds] = 2600
        XCTAssertFalse(core.canExtendBooking(id: live.id))
        core.state.settings[.weeklyAllowanceSeconds] = 18000
        core.state.settings[.bookingExtensionSeconds] = 0
        XCTAssertFalse(core.canExtendBooking(id: live.id))
        XCTAssertFalse(core.canExtendBooking(id: UUID()))
    }

    func testUpcomingBookingsAreSortedAndExcludeCanceledAndLiveSessions() throws {
        var (core, sim) = makeEngine(at: monday10)
        let c = try core.createBooking(start: core.now.addingTimeInterval(14400), durationSeconds: 1800)  // 14:00
        let b = try core.createBooking(start: core.now.addingTimeInterval(7200), durationSeconds: 1800)  // 12:00
        let a = try core.createBooking(start: core.now.addingTimeInterval(600), durationSeconds: 1800)  // 10:10
        let d = try core.createBooking(start: core.now.addingTimeInterval(10800), durationSeconds: 1800)  // 13:00
        try core.cancelBooking(id: d.id)
        XCTAssertEqual(core.upcomingBookings.map(\.id), [a.id, b.id, c.id])
        sim.advance(600)
        _ = core.update(sim.input)
        XCTAssertEqual(core.upcomingBookings.map(\.id), [b.id, c.id])
    }

    func testBookingIsAllowedDuringFocus() {
        var (core, _) = makeEngine(at: monday10)
        core.startFocus()
        XCTAssertNoThrow(try core.createBooking(start: core.now.addingTimeInterval(3600), durationSeconds: 1800))
    }

    func testPickerChoices() {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10, 2, 30))
        XCTAssertEqual(core.bookingDurations, [1800, 2700, 3600, 4500, 5400, 6300, 7200, 8100, 9000, 9900, 10800])
        let today = core.bookingStartSlots(onDayOf: core.now)
        XCTAssertEqual(today.first, date(2026, 9, 14, 10, 15))
        XCTAssertEqual(today.last, date(2026, 9, 14, 23, 55))
        XCTAssertEqual(today.count, 165)
        let tomorrow = core.bookingStartSlots(onDayOf: date(2026, 9, 15, 12))
        XCTAssertEqual(tomorrow.first, date(2026, 9, 15, 0, 0))
        XCTAssertEqual(tomorrow.count, 288)
        XCTAssertEqual(core.bookingDays(), (14...20).map { date(2026, 9, $0, 0) })
        sim.advance(13 * 3600 + 53 * 60 + 30)  // 23:56: nothing bookable is left today
        _ = core.update(sim.input)
        XCTAssertTrue(core.bookingStartSlots(onDayOf: core.now).isEmpty)
        XCTAssertEqual(core.bookingDays(), (15...20).map { date(2026, 9, $0, 0) })
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter BookingRulesTests`
Expected: compile errors.

- [ ] **Step 3: Implement** spec §5.4 exactly (everything except "Transitions", which is Task 3):
- **Charged seconds:**
  - canceled → 0
  - not finished → `duration + extension`
  - finished and not opened → 0
  - otherwise `min(duration + extension, ceil(((endedAt ?? end) − start) / 60) × 60)`
- **`allowanceRemaining(weekOf:)`:**
  - 0 if that week is `allowanceForfeited`
  - otherwise `max(0, weeklyAllowanceSeconds − Σ charged)` over bookings whose **start** has the same week key
- **`validateBooking`:** rules 1–5 in order.
  - Rule 4 only considers bookings that are upcoming or active: `start < other.end && other.start < start + duration`.
  - Error values: `.bookingTooSoon(leadSeconds: bookingLeadSeconds)` and `.invalidDuration(minSeconds: Constants.bookingMinSeconds, maxSeconds: bookingMaxSeconds)`.
- **`createBooking`:** throw the validation error if any. Otherwise append the booking and record `.bookingCreated` / `"Booked a session · \(DurationFormat.short(duration))"`.
- **`cancelBooking`:**
  - If the booking is missing or not upcoming, throw `.cannotCancel`.
  - Otherwise set `canceledAt = now` and record `.bookingCanceled` / `"Canceled a session · \(short(duration))"`.
- **`endBooking`:** if the booking is active, set `endedAt = now`; otherwise do nothing. No history.
- **`canExtendBooking`:** all of these must hold:
  - the booking is active
  - `extensionSeconds == 0` and `bookingExtensionSeconds > 0`
  - `allowanceRemaining(weekOf: start) ≥ bookingExtensionSeconds`
  - no *other* upcoming booking overlaps `[start, end + bookingExtensionSeconds)`
- **`extendBooking`:**
  - If `canExtendBooking` is false, throw `.cannotExtendBooking`.
  - Otherwise set `extensionSeconds = bookingExtensionSeconds` and record `.bookingExtended` / `"Extended session · +\(short(extension))"`.
- **`upcomingBookings`:** upcoming bookings sorted by `start`.
- **Choices** (spec §5.4 "Booking window choices"). Use a Gregorian `Calendar` with `timeZone`:
  - `bookingDurations` = `stride(from: Constants.bookingMinSeconds, through: bookingMaxSeconds, by: Constants.bookingDurationStepSeconds)`.
  - `bookingStartSlots(onDayOf:)`:
    - `dayStart = startOfDay(day)`; `dayEnd` = the next day's start.
    - `earliest = max(dayStart, now + lead)`; `first = dayStart + ceil((earliest − dayStart) / step) × step`.
    - Step by `Constants.bookingStartStepSeconds` while `slot < dayEnd && slot ≤ now + bookingHorizonSeconds`.
  - `bookingDays()`: `startOfDay(now)` plus 0…6 days, keeping days whose `bookingStartSlots` isn't empty.

- [ ] **Step 4: Run tests** — `swift test`, all pass.

- [ ] **Step 5: Checkpoint.** Do not commit.

---

### Task 3: Booking transitions and session time labels

**Files:**
- Modify: `Sources/MyTimeCore/Logic/BookingRules.swift`, `Sources/MyTimeCore/Logic/EngineCore.swift`, `Sources/MyTimeCore/Logic/DurationFormat.swift`
- Test: `Tests/MyTimeCoreTests/BookingTransitionTests.swift`, `Tests/MyTimeCoreTests/SessionTimeFormatTests.swift`

**Interfaces:**
- Produces:

```swift
extension EngineCore {
    mutating func applyBookingTransitions(_ input: UpdateInput) -> [EngineEffect]   // internal — update step 6
}
extension DurationFormat {
    public static func timeOfDay(_ date: Date, timeZone: TimeZone, locale: Locale) -> String
    public static func dayLabel(_ date: Date, now: Date, timeZone: TimeZone, locale: Locale) -> String
    public static func sessionStart(_ date: Date, now: Date, timeZone: TimeZone, locale: Locale) -> String
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/MyTimeCoreTests/BookingTransitionTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

/// Booking transitions in `update` step 6 (spec §5.4). Heads-up is 5 minutes before the end in release builds.
final class BookingTransitionTests: XCTestCase {
    /// A 30-minute session from 10:15 to 10:45, booked at 10:00 on Monday. Discord has Sessions on; "Notes" doesn't.
    private func scenario() throws -> (core: EngineCore, sim: Sim, booking: Booking, discord: UUID, notes: UUID) {
        var (core, sim) = makeEngine(at: date(2026, 9, 14, 10))
        let notes = BlockedApp(name: "Notes", bundleIDs: ["com.example.notes"], modes: [.quickLook])
        core.state.settings.apps.append(notes)
        let booking = try core.createBooking(start: date(2026, 9, 14, 10, 15), durationSeconds: 1800)
        return (core, sim, booking, core.state.settings.apps[0].id, notes.id)
    }

    func testOpeningABookedAppDuringTheSessionIsRecorded() throws {
        var (core, sim, booking, discord, notes) = try scenario()
        sim.running = [discord]
        sim.advance(600)  // 10:10, before the start
        _ = core.update(sim.input)
        XCTAssertFalse(core.state.bookings[0].appOpened)
        XCTAssertFalse(core.isAllowed(appID: discord))
        sim.advance(360)  // 10:16
        _ = core.update(sim.input)
        XCTAssertEqual(core.activeBooking?.id, booking.id)
        XCTAssertTrue(core.state.bookings[0].appOpened)
        XCTAssertTrue(core.isAllowed(appID: discord))
        XCTAssertFalse(core.isAllowed(appID: notes))
    }

    func testHeadsUpIsEmittedOnceFiveMinutesBeforeTheEnd() throws {
        var (core, sim, booking, _, _) = try scenario()
        sim.advance(20 * 60)  // 10:20
        XCTAssertEqual(core.update(sim.input).effects, [])
        sim.advance(19 * 60 + 59)  // 10:39:59
        XCTAssertEqual(core.update(sim.input).effects, [])
        sim.advance(1)  // 10:40:00
        XCTAssertEqual(core.update(sim.input).effects, [.bookingHeadsUp(bookingID: booking.id)])
        XCTAssertTrue(core.state.bookings[0].warned)
        sim.advance(30)
        XCTAssertEqual(core.update(sim.input).effects, [])
    }

    func testSessionEndClosesOnlyAppsWithSessionsOn() throws {
        var (core, sim, _, discord, _) = try scenario()
        sim.advance(20 * 60)  // 10:20
        _ = core.update(sim.input)
        sim.advance(25 * 60)  // 10:45, the end
        let result = core.update(sim.input)
        XCTAssertNil(core.activeBooking)
        XCTAssertEqual(result.effects, [.terminateIfNotAllowed(appID: discord)])
        XCTAssertEqual(core.state.history.last?.kind, .bookingEnded)
        XCTAssertEqual(core.state.history.last?.text, "Session ended")
        XCTAssertFalse(core.isAllowed(appID: discord))
        sim.advance(60)
        XCTAssertEqual(core.update(sim.input).effects, [])
        XCTAssertEqual(core.state.history.filter { $0.kind == .bookingEnded }.count, 1)
    }

    func testEndingEarlyClosesAppsOnTheNextUpdateAndChargesOnlyTheMinutesUsed() throws {
        var (core, sim, booking, discord, _) = try scenario()
        sim.running = [discord]
        sim.advance(16 * 60)  // 10:16
        _ = core.update(sim.input)
        sim.advance(4 * 60 + 30)  // 10:20:30
        _ = core.update(sim.input)
        core.endBooking(id: booking.id)
        XCTAssertEqual(core.state.bookings[0].endedAt, core.now)
        XCTAssertNil(core.activeBooking)
        sim.advance(1)
        XCTAssertEqual(core.update(sim.input).effects, [.terminateIfNotAllowed(appID: discord)])
        XCTAssertEqual(core.chargedSeconds(of: core.state.bookings[0]), 360)  // 5 min 30 s, rounded up
        XCTAssertEqual(core.allowanceRemaining(weekOf: core.now), 18000 - 360)
    }

    func testEndBookingIgnoresSessionsThatAreNotLive() throws {
        var (core, _, booking, _, _) = try scenario()
        core.endBooking(id: booking.id)
        core.endBooking(id: UUID())
        XCTAssertNil(core.state.bookings[0].endedAt)
    }

    func testGrantExpiryAndSessionEndInTheSameUpdateCloseTheAppOnce() throws {
        var (core, sim, _, discord, _) = try scenario()
        sim.advance(1600)  // 10:26:40
        _ = core.update(sim.input)
        core.state.grants = [
            AccessGrant(appID: discord, kind: .quickLook, createdAt: core.now, expiresAt: date(2026, 9, 14, 10, 45))
        ]
        sim.advance(18 * 60 + 20)  // 10:45
        XCTAssertEqual(core.update(sim.input).effects, [.terminateIfNotAllowed(appID: discord)])
    }
}
```

`Tests/MyTimeCoreTests/SessionTimeFormatTests.swift`:

```swift
import XCTest

@testable import MyTimeCore

/// Labels for session times in the panel, the gate, and the booking window (spec §7.2, §7.3, §7.8).
/// "Today" and "Tomorrow" follow calendar days, not the 4 AM day start.
final class SessionTimeFormatTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private let now = date(2026, 9, 14, 22)  // Monday 10 PM

    private func day(_ date: Date) -> String {
        DurationFormat.dayLabel(date, now: now, timeZone: testTZ, locale: locale)
    }

    private func start(_ date: Date) -> String {
        DurationFormat.sessionStart(date, now: now, timeZone: testTZ, locale: locale)
    }

    func testDayLabels() {
        XCTAssertEqual(day(date(2026, 9, 14, 23, 55)), "Today")
        XCTAssertEqual(day(date(2026, 9, 15, 0, 0)), "Tomorrow")
        XCTAssertEqual(day(date(2026, 9, 16, 9)), "Wed")
        XCTAssertEqual(day(date(2026, 9, 20, 9)), "Sun")
    }

    func testTimeOfDayAndSessionStart() {
        XCTAssertEqual(DurationFormat.timeOfDay(date(2026, 9, 14, 20, 5), timeZone: testTZ, locale: locale), "8:05 PM")
        XCTAssertEqual(start(date(2026, 9, 14, 22, 5)), "Today 10:05 PM")
        XCTAssertEqual(start(date(2026, 9, 15, 8, 0)), "Tomorrow 8:00 AM")
        XCTAssertEqual(start(date(2026, 9, 17, 19, 30)), "Thu 7:30 PM")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter "BookingTransitionTests|SessionTimeFormatTests"`
Expected: compile errors (`dayLabel` not found) or failures (no transitions yet).

- [ ] **Step 3: Implement**
- **`applyBookingTransitions`:** spec §5.4 "Transitions", in order:
  1. If a booking is active: if any running app ID belongs to an app with `.booked`, set `appOpened = true`. If `!warned` and `end − now ≤ Constants.bookingHeadsUp`, set `warned = true` and append `.bookingHeadsUp(bookingID:)`.
  2. If `runtime.lastActiveBookingID` is non-nil and that booking isn't active now (or is gone), record `.bookingEnded` / `"Session ended"` and append `.terminateIfNotAllowed(appID:)` for every app with `.booked`.
  3. Set `runtime.lastActiveBookingID = activeBooking?.id`.

  Mutate `state.bookings[index]`, not a copy.
- **`EngineCore.update`:** after the grant-expiry effects are built, add step 6. Grant effects come first, then booking effects, skipping duplicates:

```swift
        // Step 6: booking transitions (spec §5.4). A grant expiring as a session ends closes the app once.
        for effect in applyBookingTransitions(input) where !effects.contains(effect) {
            effects.append(effect)
        }
```

- **`DurationFormat`:**
  - Use a `DateFormatter` with the given `locale` and `timeZone`.
  - `timeOfDay`: template `"j:mm"`. Replace `\u{202F}` and `\u{00A0}` with a normal space, like `hourOfDay`.
  - `dayLabel`: compare calendar days in `timeZone` (Gregorian). 0 → `"Today"`, 1 → `"Tomorrow"`, otherwise template `"EEE"`.
  - `sessionStart`: `"\(dayLabel) \(timeOfDay)"`.

- [ ] **Step 4: Run tests** — `swift build && swift test`, all pass (75 before this run + 28 new = 103).

- [ ] **Step 5: Checkpoint.** Do not commit.

---

### Task 4: Gate — reply card, sessions line, emergency sub-flow

**Files:**
- Create: `Sources/MyTimeApp/UI/GateSession.swift`, `Sources/MyTimeApp/UI/GateCards.swift`, `Sources/MyTimeApp/UI/EmergencyFlowView.swift`
- Modify: `Sources/MyTimeApp/UI/OverlayController.swift`, `Sources/MyTimeApp/UI/GateView.swift`

**Interfaces:**
- Produces:

```swift
// GateSession.swift (move GateSession and GateMode here unchanged, then add:)
enum GateStep: Equatable {
    case choose
    case emergencyReason
    case emergencyWaiting(until: Date)
    case emergencyReady
}
// GateSession gains:
var step: GateStep = .choose
var replyNote = ""
var emergencyReason = ""

// GateView.swift: OverlayActions gains
let reply: (String) -> Void
let openEmergency: () -> Void
let bookSession: () -> Void

// OverlayController
var pillFrame: NSRect? { get }   // pill panel frame if showing (for the heads-up, Task 6)
```

- [ ] **Step 1: Move `GateSession`/`GateMode`** to `GateSession.swift` and add `GateStep` and the three properties.

- [ ] **Step 2: `OverlayController`**
- Add these actions to the `OverlayActions` built in `show(...)`:

| Action | Behavior |
|---|---|
| `reply(note)` | Like `quickLook`: `session.touch()`, `try model.perform { try $0.buyReply(appID:note:) }`, close, `relaunch(bundleURL)`. On `EngineError`, set `session.errorMessage = error.userMessage`. |
| `openEmergency()` | Same pattern with `useEmergency(appID:reason: session.emergencyReason)`. |
| `bookSession()` | Capture the app ID, `closeGate()`, `model.perform { $0.recordBackedOff(appID:) }`, then `model.router.showBooking()`. Close first so the window isn't under the gate's `.modalPanel` level. `router` arrives in Task 5; until then, call it from Task 5's step, or add the property then. |

- In the `gateClock` closure, **before** the timeout check:

```swift
            if case .emergencyWaiting(let until) = session.step {
                session.touch()  // the 60 s timeout is suspended during the emergency wait (spec §6.5)
                if session.now >= until {
                    session.step = .emergencyReady
                }
            }
```

- Add `pillFrame` (returns `pillPanel?.frame`).

- [ ] **Step 3: Gate content (spec §7.3).** `GateView` keeps the icon, pause ring, title, and pause line, then shows either the choose phase (`session.step == .choose`) or `EmergencyFlowView`. After that come the error line, **Never mind** (unchanged), and the footer (choose phase only).
- **Subtitle:** if the app's modes are exactly `[.booked]`, `"\(app.name) is available during booked sessions."`; otherwise the existing tokens subtitle.
- **Choose phase**, in `GateCards.swift`:
  - **No tokens:** if `tokens == 0` and the app has `.quickLook` or `.reply`, show the existing no-tokens text and Start Focus instead of both cards.
  - **Quick look card:** existing, only if the app has `.quickLook`.
  - **Reply card**, only if the app has `.reply`. Same card surface as quick look:
    - Header: `Text("Reply mode").font(.headline)`, then `Spacer()`, then `"\(DurationFormat.short(replySeconds)) · \(cost) ◆ · \(left) of \(perDay) left today"` (secondary), where `left = max(0, replyPerDay − today.replies)`.
    - Row: `TextField("What are you here to do?", text: $session.replyNote)` with `.textFieldStyle(.roundedBorder)` and `.onChange(of: session.replyNote) { session.touch() }`, then `Button("Open") { actions.reply(session.replyNote) }`, disabled while pausing or while `model.core.replyUnavailableReason(appID:note:) != nil`.
    - When that reason is `.noteTooShort`, `.notEnoughTokens`, or `.replyLimitReached` (and not pausing), one secondary `.callout` line: "Write at least 8 characters" / `"Needs \(cost) \(cost == 1 ? "token" : "tokens")"` / "No replies left today".
    - No `.onSubmit` action.
  - **Sessions line**, only if the app has `.booked`:
    - With `model.core.upcomingBookings.first`: `"Next session: \(DurationFormat.sessionStart(start, now: model.displayNow, timeZone: .current, locale: .current))"` (secondary).
    - Otherwise: `"Sessions: none booked"` (secondary) and `Button("Book a session…") { actions.bookSession() }`, with `.buttonStyle(.link)`, disabled while pausing.
- **Footer** (choose phase only):
  - If `model.core.emergencyUsesLeftThisWeek > 0`: `Button("Emergency access") { session.step = .emergencyReason; session.touch() }`, with `.buttonStyle(.link)`, disabled while pausing. Write those as two statements.
  - Otherwise: `Text("Emergency access used · resets Monday").foregroundStyle(.tertiary)`.
- **`EmergencyFlowView(session:model:actions:)`**, where `wait = emergencyWaitSeconds` and `minutes = emergencyAccessSeconds / 60`:
  - `.emergencyReason`:
    - `Text("Emergency access").font(.headline)`
    - body `"Once a week. After a \(wait)-second wait you'll get \(minutes) \(minutes == 1 ? "minute" : "minutes")."`
    - `TextField("What's the emergency?", text: $session.emergencyReason)` (rounded border; `onChange` → `touch()`)
    - `HStack`: **Back** (`step = .choose`, touch) and **Start wait**. Start wait is enabled when the trimmed reason has ≥ `Constants.minEmergencyReason` characters and sets `step = .emergencyWaiting(until: Date().addingTimeInterval(Double(wait)))`.
  - `.emergencyWaiting(until)`:
    - `Text("Opening in \(max(0, Int(ceil(until.timeIntervalSince(session.now)))))s")` in `.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()`
    - **Cancel** (`step = .emergencyReason`, touch), captioned "Your pass won't be used." (secondary)
  - `.emergencyReady`: `Button("Open \(app.name) for \(minutes) min") { actions.openEmergency() }`.
  - Use `.bordered` buttons; Never mind stays the only prominent one.
- The panel resizes itself as content changes (verified), so don't add resizing code.

- [ ] **Step 4: Build** — `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`. If `router` doesn't exist yet, stub `bookSession` with the backed-off + close part and finish it in Task 5.

- [ ] **Step 5: Checkpoint.** Do not commit.

---

### Task 5: Booking window and panel Sessions block

**Files:**
- Create: `Sources/MyTimeApp/Engine/WindowRouter.swift`, `Sources/MyTimeApp/UI/BookingView.swift`, `Sources/MyTimeApp/UI/SessionsBlock.swift`
- Modify: `Sources/MyTimeApp/Engine/AppModel.swift`, `Sources/MyTimeApp/UI/PopoverView.swift`, `Sources/MyTimeApp/UI/OverlayController.swift` (finish `bookSession`)

**Interfaces:**
- Produces:

```swift
@MainActor final class WindowRouter {
    init(model: AppModel)
    func showBooking()
    func closeBooking()
}
// AppModel
@ObservationIgnored private(set) var router: WindowRouter!   // created in init like overlays
func createBooking(start: Date, durationSeconds: Int) throws   // try perform { _ = try $0.createBooking(...) }
func cancelBooking(id: UUID)                                   // perform { try? $0.cancelBooking(id:) }
func endBooking(id: UUID)                                      // perform { $0.endBooking(id:) }
func extendBooking(id: UUID)                                   // perform { try? $0.extendBooking(id:) }
struct BookingView: View { init(model: AppModel, onDone: @escaping () -> Void) }
struct SessionsBlock: View { init(model: AppModel) }
```

- [ ] **Step 1: `WindowRouter.showBooking()`**
  - `model.refresh(.intent)`, so the choices use the current time.
  - If a booking window already exists, bring it forward and return.
  - Otherwise create `NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)`. Set `title = "Book a Session"`, `isReleasedWhenClosed = false`, and `contentView = NSHostingView(rootView: BookingView(model: model, onDone: { [weak self] in self?.closeBooking() }))`, then `center()`.
  - Bring it forward: `NSApp.activate()`, `window.makeKeyAndOrderFront(nil)`, `window.orderFrontRegardless()`. The last call keeps it in front even if macOS declines activation for a background agent.
  - Clear the stored window when it closes, using `NSWindow.willCloseNotification`.
  - `closeBooking()` closes it.

- [ ] **Step 2: `BookingView`** (spec §7.8), a `Form` or `VStack` with 16 pt padding:
  - `@State private var day: Date?`, `start: Date?`, `duration: Int?`, `errorMessage: String?`.
  - `.onAppear`: `day = core.bookingDays().first`, `start = slots.first`, `duration = core.bookingDurations.first`.
  - `.onChange(of: day)`: `start = slots.first`.
  - `slots = day.map { core.bookingStartSlots(onDayOf: $0) } ?? []`. In DEV builds use `Array(slots.prefix(30))` (`#if DEV_TIMESCALE`).
  - Three `Picker`s with `.pickerStyle(.menu)`: "Day" (`DurationFormat.dayLabel(d, now: model.displayNow, timeZone: .current, locale: .current)`), "Start" (`timeOfDay`), and "Length" (`DurationFormat.short`). Tags are the `Date?`/`Int?` values.
  - If `start` is set: `"\(DurationFormat.short(Double(core.allowanceRemaining(weekOf: start)))) left in that week"` (secondary).
  - Validation line (secondary): `errorMessage ?? core.validateBooking(start:durationSeconds:)?.userMessage`, or a blank reserved line.
  - Buttons:
    - **Cancel** (`.keyboardShortcut(.cancelAction)`) → `onDone()`
    - **Book** (`.keyboardShortcut(.defaultAction)`) → `do { try model.createBooking(...); onDone() } catch let e as EngineError { errorMessage = e.userMessage }`. Disabled when start or duration is nil or validation fails.
  - Any picker change clears `errorMessage`.

- [ ] **Step 3: `SessionsBlock`** (spec §7.2 item 6), placed in `PopoverView` between the tokens row and the today strip:
  - Header `HStack`: `Text("Sessions").font(.headline)`, `Spacer()`, and `"\(DurationFormat.short(Double(core.allowanceRemaining(weekOf: core.now)))) left this week"` (secondary).
  - If `core.activeBooking`:
    - `"Live · \(DurationFormat.short(end − model.displayNow)) left"`
    - `Button("Extend \(DurationFormat.short(Double(bookingExtensionSeconds)))")`, only if `canExtendBooking`
    - `Button("End")`
  - `ForEach(core.upcomingBookings.prefix(3))`: `"\(DurationFormat.sessionStart(start, now: model.displayNow, timeZone: .current, locale: .current)) · \(DurationFormat.short(Double(durationSeconds)))"` with `Button("Cancel")`.
  - `Button("Book a Session…") { model.router.showBooking() }`.
  - Row buttons use `.buttonStyle(.borderless)` or `.bordered` with `.controlSize(.small)`.

- [ ] **Step 4:** Finish `OverlayController.bookSession()` with `model.router.showBooking()`.

- [ ] **Step 5: Build** — `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`.

- [ ] **Step 6: Checkpoint.** Do not commit.

---

### Task 6: Heads-up, menu bar booking row, effect handling

**Files:**
- Create: `Sources/MyTimeApp/UI/HeadsUpController.swift`, `Sources/MyTimeApp/UI/HeadsUpView.swift`
- Modify: `Sources/MyTimeApp/Engine/AppModel.swift`, `Sources/MyTimeApp/UI/MenuBarLabel.swift`

**Interfaces:**
- Produces:

```swift
@MainActor final class HeadsUpController {
    init(model: AppModel)
    func show(bookingID: UUID)
    func close()
}
// AppModel
@ObservationIgnored private(set) var headsUp: HeadsUpController!
var bookingCountdown: Double? { get }   // seconds to the active booking's end, only while a .booked app is running
```

- [ ] **Step 1: `AppModel.refresh` effects.** Replace the `if case` loop with an exhaustive switch:

```swift
        for effect in result.effects {
            switch effect {
            case let .terminateIfNotAllowed(appID):
                enforcer.terminateIfNotAllowed(appID: appID)
            case let .bookingHeadsUp(bookingID):
                headsUp.show(bookingID: bookingID)
            case .uninstall:
                break  // Run 4
            }
        }
```

- [ ] **Step 2: `bookingCountdown` and timers**
- `bookingCountdown`:
  - `nil` unless `core.activeBooking` exists and `monitor.runningBlocked(in: core)` contains an app with `.booked`.
  - Otherwise `max(0, booking.end.timeIntervalSince(displayNow))`.
- `showsClaimDot` also requires `bookingCountdown == nil`, because countdown rows never show the dot (§7.1).
- In `updateActivityAndTimers`, add a `RepeatingUITimer` `bookingLabelTimer`:
  - Start it (interval 60, body `uiNow = Date()`) when `grantCountdown == nil && bookingCountdown != nil`.
  - Stop it otherwise.
  - Session end is already a critical wake-up, so nothing faster is needed.

- [ ] **Step 3: `MenuBarLabel`.** Insert the booking row after the grant row (§7.1): `Image(systemName: "hourglass")` and `prefix + DurationFormat.short(remaining)`.

- [ ] **Step 4: `HeadsUpController` / `HeadsUpView`** (§7.6)
- **`show(bookingID:)`:**
  - Return unless a running blocked app has `.booked` and `core.state.bookings` contains that ID.
  - Close any existing heads-up.
  - Create `OverlayPanel(allowsKey: false)` with `setRoot(HeadsUpView(model:bookingID:onClose:))`.
  - Placement: if `model.overlays.pillFrame` is set, put the panel's top-right 8 pt below the pill's bottom-right. Otherwise put it 12 pt inside the top-right of `NSScreen.main?.visibleFrame`.
  - `orderFrontRegardless()`.
  - Start a one-shot `Timer` of `Constants.headsUpVisible` (tolerance 0.8) that calls `close()`.
- **`HeadsUpView`:**
  - Width 260, padding 16, same surface as the focus card (`.regularMaterial`, radius 22, 1 pt separator stroke).
  - `Text("Session ends in \(DurationFormat.short(booking.end.timeIntervalSince(model.displayNow)))")`.
  - If `model.core.canExtendBooking(id:)`: `Button("Extend \(DurationFormat.short(Double(bookingExtensionSeconds)))") { model.extendBooking(id:); onClose() }`.

- [ ] **Step 5: Build** — `swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test`.

- [ ] **Step 6: Checkpoint.** Do not commit.

---

### Task 7: Docs and final verification

**Files:**
- Modify: `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md`

- [ ] **Step 1:** Append `## Run 3` to `docs/MANUAL_TESTS.md` with spec §11.2 steps 16–18 verbatim.

- [ ] **Step 2:** Append `## Run 3` to `IMPLEMENTATION_NOTES.md` with `### Deviations` (or "None."), `### Not verified`, and `### Commands run`.

- [ ] **Step 3: Format and verify**

```bash
swift format --in-place --recursive Sources Tests
swift build && swift build -Xswiftc -DDEV_TIMESCALE && swift test && swift build -c release --arch arm64 -Xswiftc -DDEV_TIMESCALE
```

Expected: every build prints `Build complete!`, and the tests report 103 tests with 0 failures. Paste the summary line into the notes.

- [ ] **Step 4: Self-check before replying.** Confirm each item in your reply:
  - [ ] No code line in `Sources/` or `Tests/` exceeds ~130 characters (long comments or string literals excepted).
  - [ ] All five plan test files exist with the exact test method names from this plan.
  - [ ] No file in `Sources/` exceeds ~300 lines.
  - [ ] Nothing in the gate uses `.keyboardShortcut(.defaultAction)` or `.onSubmit`.
  - [ ] Every behavior change from the spec is listed in the notes.

- [ ] **Step 5: Stop.** Don't start Run 4 and don't commit. Reply with what you built, the test count, and every deviation.

---

## Self-review record (reviewer)

**Spec coverage for Run 3 (§12):**

| Spec item | Task |
|---|---|
| Reply mode (`buyReply`, reasons, limit) | 1 |
| Emergency pass | 1 (core), 4 (sub-flow) |
| `BookingRules` validation, allowance, intents | 2 |
| Booking transitions (appOpened, heads-up, end) | 3 |
| Gate reply card, sessions line, footer link | 4 |
| Panel Sessions block | 5 |
| `BookingView` + `WindowRouter` | 5 |
| `HeadsUpView` | 6 |
| Menu bar booking row (60 s label timer) | 6 |
| Tests: reply, BookingRules, transitions, Emergency, session labels | 1–3 |
| Manual steps 16–18 | 7 |

**Test validation:** every test in this plan was run against a reference implementation written straight from spec §5.3–§5.5 in a scratch copy (not committed). All 103 pass together with the 75 existing tests. As a mutation check, 13 deliberate rule breaks were tried, among them rounding charged minutes down, a strict heads-up comparison, no effect de-duplication, swapped reply error order, ended sessions blocking new bookings, a week key without the day start, charging unopened sessions, unaligned start slots, emergency not ending focus, and extensions ignoring the next session or the allowance. Each one makes at least one plan test fail. If a plan test fails on your implementation, the implementation diverges from the spec.

**Verified on the target Mac:** an `NSHostingView` borderless panel resizes itself to its SwiftUI content and keeps its top edge.

**Design decisions made while planning (now in spec revision 3):**
- `unknownApp` is checked first for reply and emergency.
- History lines are "Booked a session · …" and "Canceled a session · …". `endBooking` adds none, because the transition records "Session ended".
- `replyUnavailableReason` drives both `buyReply` and the gate's disabled line.
- Booking-window choices are Core functions with tests; days with no bookable time are omitted.
- Heads-up copy uses `short(end − now)` so DEV reads correctly; it sits below the pill when the pill is showing.
- Emergency copy pluralizes "minute", and Cancel during the wait returns to the reason step.
- Manual steps are renumbered: Run 2 is 8–15, Run 3 is 16–18, Run 4 is 19–24.
