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
    static func selfHeal() {
        guard let exe = executablePath, exe.contains(".app/Contents/MacOS/") else { return }
        let args = NSDictionary(contentsOf: plistURL)?["ProgramArguments"] as? [String]
        if args?.first != exe { try? writePlist(executable: exe) }
    }
    private static func writePlist(executable: String) throws {
        let plist: [String: Any] = [
            "Label": label, "ProgramArguments": [executable, "--agent"], "RunAtLoad": true, "KeepAlive": true,
            "ThrottleInterval": 5, "ProcessType": "Interactive", "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
    }
    @discardableResult private static func launchctl(_ arguments: [String]) -> Int32 {
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
