import AppKit
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { AppModel.shared.launch() }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.saveNow() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.router.showSettings(tab: .general)
        return false
    }
}
