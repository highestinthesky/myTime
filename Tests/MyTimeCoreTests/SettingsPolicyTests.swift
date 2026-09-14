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
