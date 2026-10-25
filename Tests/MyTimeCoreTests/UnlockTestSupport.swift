import Foundation

@testable import MyTimeCore

/// Discord (Unlock + Sessions), TextEdit (Unlock only), Notes (Sessions only).
struct UnlockFixture {
    var core: EngineCore
    var sim: Sim
    let discord: UUID
    let textEdit: UUID
    let notes: UUID

    @discardableResult
    mutating func advance(to target: Date) -> UpdateResult {
        sim.advance(target.timeIntervalSince(sim.wall))
        return core.update(sim.input)
    }

    /// Buys at the price currently quoted for that length.
    @discardableResult
    mutating func buy(_ lengthSeconds: Int, app: UUID? = nil) throws -> ActiveUnlock {
        let option = core.unlockQuote(at: core.now).options.first { $0.lengthSeconds == lengthSeconds }
        return try core.buyUnlock(appID: app ?? discord, lengthSeconds: lengthSeconds, expectedCost: option?.cost ?? 0)
    }
}

func makeUnlockFixture(at wall: Date, tokens: Int) -> UnlockFixture {
    var state = PersistedState.fresh(now: wall, timeZone: testTZ)
    state.tokens = tokens
    state.settings.apps[0].modes.insert(.unlock)
    let textEdit = BlockedApp(name: "TextEdit", bundleIDs: ["com.apple.TextEdit"], modes: [.unlock])
    let notes = BlockedApp(name: "Notes", bundleIDs: ["com.apple.Notes"], modes: [.booked])
    state.settings.apps.append(textEdit)
    state.settings.apps.append(notes)
    var core = EngineCore(state: state, timeZone: testTZ)
    let sim = Sim(wall: wall)
    _ = core.start(sim.input)
    return UnlockFixture(
        core: core, sim: sim, discord: state.settings.apps[0].id, textEdit: textEdit.id, notes: notes.id)
}
