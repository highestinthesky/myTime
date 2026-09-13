import Foundation
import MyTimeCore

/// Loads and saves the HMAC-protected state file (spec §5.7).
/// The "has run before" sentinel lives in UserDefaults, not next to the file, so deleting the data
/// folder alone doesn't look like a fresh install.
@MainActor final class StateStore {
    enum Outcome { case existing, fresh, tampered }

    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("myTime", isDirectory: true)

    #if DEV_TIMESCALE
        private var fileURL: URL { directory.appendingPathComponent("state-dev.json") }
        private let sentinelKey = "mytime.dev.initialized"
    #else
        private var fileURL: URL { directory.appendingPathComponent("state.json") }
        private let sentinelKey = "mytime.initialized"
    #endif

    func load() -> (state: PersistedState, outcome: Outcome) {
        let now = Date()
        guard let data = try? Data(contentsOf: fileURL) else {
            if UserDefaults.standard.bool(forKey: sentinelKey) {
                return (.penalized(now: now, timeZone: .current), .tampered)
            }
            return (.fresh(now: now, timeZone: .current), .fresh)
        }
        switch StateCodec.decode(data) {
        case let .ok(state):
            return (state, .existing)
        case .tampered:
            let aside = directory.appendingPathComponent("state.tampered-\(Int(now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            return (.penalized(now: now, timeZone: .current), .tampered)
        }
    }

    func save(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try StateCodec.encode(state).write(to: fileURL, options: .atomic)
        UserDefaults.standard.set(true, forKey: sentinelKey)
    }
}
