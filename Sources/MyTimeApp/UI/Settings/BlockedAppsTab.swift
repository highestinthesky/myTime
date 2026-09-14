import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MyTimeCore

@MainActor
struct BlockedAppsTab: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(model.core.state.settings.apps) { app in
                HStack {
                    Image(nsImage: icon(for: app))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(app.name)
                    Spacer()
                    ForEach(AccessMode.allCases, id: \.self) { mode in
                        HStack(spacing: 3) {
                            Toggle(mode.title, isOn: modeBinding(app: app, mode: mode))
                                .toggleStyle(.checkbox)
                            if let pending = pending(modeFieldKey(app: app, mode: mode)) {
                                Image(systemName: "clock")
                                    .help("On \(sessionStart(pending.applyAt))")
                            }
                        }
                    }
                    removeControl(for: app)
                }
            }

            Button("Add App…") {
                addApp()
            }
        }
    }

    @ViewBuilder
    private func removeControl(for app: BlockedApp) -> some View {
        let fieldKey = SettingChange.removeApp(id: app.id).fieldKey
        if let pending = pending(fieldKey) {
            Text("Removal \(sessionStart(pending.applyAt))")
                .foregroundStyle(.secondary)
        } else {
            Button("Remove…") {
                guard confirmLoosening() else {
                    return
                }
                model.submit(.removeApp(id: app.id))
            }
        }
    }

    private func modeBinding(app: BlockedApp, mode: AccessMode) -> Binding<Bool> {
        Binding(
            get: {
                app.modes.contains(mode)
            },
            set: { enabled in
                if enabled {
                    guard confirmLoosening() else {
                        return
                    }
                }
                model.submit(.setMode(appID: app.id, mode: mode, enabled: enabled))
            }
        )
    }

    private func modeFieldKey(app: BlockedApp, mode: AccessMode) -> String {
        SettingChange.setMode(appID: app.id, mode: mode, enabled: true).fieldKey
    }

    private func pending(_ fieldKey: String) -> PendingChange? {
        model.core.state.pending.first { pending in
            pending.change.fieldKey == fieldKey
        }
    }

    private func confirmLoosening() -> Bool {
        let applyAt = model.displayNow.addingTimeInterval(
            Double(model.core.setting(.looseningDelaySeconds))
        )
        return SettingsAlerts.confirm(
            title: "This loosens myTime",
            message: "It will apply \(sessionStart(applyAt)).",
            confirmTitle: "Schedule"
        )
    }

    private func sessionStart(_ date: Date) -> String {
        DurationFormat.sessionStart(
            date,
            now: model.displayNow,
            timeZone: .current,
            locale: .current
        )
    }

    private func icon(for app: BlockedApp) -> NSImage {
        for bundleID in app.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let bundleID = Bundle(url: url)?.bundleIdentifier
        if let problem = SettingsPolicy.addAppProblem(
            bundleID: bundleID,
            path: url.path,
            ownBundleID: Bundle.main.bundleIdentifier,
            apps: model.core.state.settings.apps
        ) {
            SettingsAlerts.inform(title: problem, message: "")
            return
        }

        guard let bundleID else {
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let isRunning = NSWorkspace.shared.runningApplications.contains { app in
            app.activationPolicy == .regular && app.bundleIdentifier == bundleID
        }
        if isRunning {
            let shouldAdd = SettingsAlerts.confirm(
                title: "\(name) is running and will be closed.",
                message: "",
                confirmTitle: "Add"
            )
            guard shouldAdd else {
                return
            }
        }

        model.submit(
            .addApp(
                BlockedApp(
                    name: name,
                    bundleIDs: [bundleID],
                    modes: [.quickLook, .reply, .booked]
                )))
    }
}
