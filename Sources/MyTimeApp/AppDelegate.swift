import AppKit
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { AppModel.shared.launch() }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.saveNow() }
}
