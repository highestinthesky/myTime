import SwiftUI
struct MyTimeScene: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: AppModel.shared)
        } label: {
            MenuBarLabel(model: AppModel.shared)
        }.menuBarExtraStyle(.window)
    }
}
