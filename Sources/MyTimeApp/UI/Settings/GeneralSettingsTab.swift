import SwiftUI
import MyTimeCore

@MainActor
struct GeneralSettingsTab: View {
    let model: AppModel
    @State private var draft: [SettingKey: Int] = [:]
    @State private var alertMessage = ""
    @State private var showsAlert = false

    var body: some View {
        VStack(spacing: 12) {
            Form {
                ForEach(SettingGroup.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(keys(in: group), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Stepper(value: binding(for: key), in: key.range, step: key.step) {
                                    HStack {
                                        Text(key.title)
                                        Spacer()
                                        Text(formattedValue(for: key))
                                            .monospacedDigit()
                                    }
                                }
                                if key == .dayStartHour {
                                    Text(
                                        "Changing this always waits "
                                            + "\(DurationFormat.short(Double(model.core.setting(.looseningDelaySeconds))))."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Revert") {
                    refillDraft()
                }
                Button("Apply Changes") {
                    applyChanges()
                }
                .disabled(!hasChanges)
            }
        }
        .onAppear {
            refillDraft()
        }
        .alert("Settings updated", isPresented: $showsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var hasChanges: Bool {
        SettingKey.allCases.contains { key in
            draft[key] != model.core.setting(key)
        }
    }

    private func keys(in group: SettingGroup) -> [SettingKey] {
        SettingKey.allCases.filter { $0.group == group }
    }

    private func binding(for key: SettingKey) -> Binding<Int> {
        Binding(
            get: {
                draft[key] ?? model.core.setting(key)
            },
            set: { value in
                draft[key] = value
            }
        )
    }

    private func formattedValue(for key: SettingKey) -> String {
        DurationFormat.setting(
            key,
            draft[key] ?? model.core.setting(key),
            locale: .current
        )
    }

    private func refillDraft() {
        draft = Dictionary(
            uniqueKeysWithValues: SettingKey.allCases.map { key in
                (key, model.core.setting(key))
            }
        )
    }

    private func applyChanges() {
        var lines: [String] = []
        for key in SettingKey.allCases where draft[key] != model.core.setting(key) {
            guard let value = draft[key] else {
                continue
            }
            let change = SettingChange.setNumber(key: key, value: value)
            let text = model.core.summary(of: change, locale: .current)
            switch model.submit(change) {
            case .applied:
                lines.append("Applied now: \(text)")
            case let .scheduled(at):
                let when = DurationFormat.sessionStart(
                    at,
                    now: model.displayNow,
                    timeZone: .current,
                    locale: .current
                )
                lines.append("Applies \(when): \(text)")
            case .noChange:
                break
            }
        }
        refillDraft()
        alertMessage = lines.joined(separator: "\n")
        showsAlert = true
    }
}
