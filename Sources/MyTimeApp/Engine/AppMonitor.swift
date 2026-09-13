import AppKit
import MyTimeCore
@MainActor final class AppMonitor {
    func blockedApp(for process: NSRunningApplication, in core: EngineCore) -> BlockedApp? {
        guard !process.isTerminated, process.activationPolicy == .regular, let id = process.bundleIdentifier else {
            return nil
        }
        return core.app(bundleID: id)
    }
    func runningBlocked(in core: EngineCore) -> [(app: BlockedApp, process: NSRunningApplication)] {
        NSWorkspace.shared.runningApplications.compactMap { process in
            blockedApp(for: process, in: core).map { ($0, process) }
        }
    }
    func runningBlockedAppIDs(in core: EngineCore) -> Set<UUID> { Set(runningBlocked(in: core).map(\.app.id)) }
}
