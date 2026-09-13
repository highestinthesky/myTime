import Foundation
@testable import MyTimeCore

let testTZ = TimeZone(identifier: "America/New_York")!

/// Local date in `testTZ`. 2026-09-13 is a Sunday; 2026-09-14 is a Monday.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = testTZ
    return cal.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

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
        UpdateInput(
            wall: wall, continuous: continuous, uptime: uptime, bootSessionID: boot,
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
