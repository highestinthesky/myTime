import SwiftUI
import MyTimeCore

/// The General tab (spec §7.9). Every value is typed: durations as a whole number plus a unit, counts as a number,
/// and the day start from an hour menu. Edits stay in a draft until Apply Changes.
@MainActor
struct GeneralSettingsTab: View {
    let model: AppModel
    @State private var draft: [SettingKey: DraftValue] = [:]
    @State private var alertMessage = ""
    @State private var showsAlert = false

    private struct DraftValue {
        var text: String
        var unit: DurationUnit
    }

    var body: some View {
        VStack(spacing: 12) {
            Form {
                ForEach(SettingGroup.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(keys(in: group), id: \.self) { key in
                            row(for: key)
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
                .disabled(!hasChanges)
                Button("Apply Changes") {
                    applyChanges()
                }
                .disabled(!hasChanges || hasProblems)
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

    private func row(for key: SettingKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(key.title) {
                HStack(spacing: 6) {
                    switch key.unit {
                    case .hourOfDay:
                        hourPicker(for: key)
                    case .count:
                        numberField(for: key)
                    case .seconds:
                        numberField(for: key)
                        unitPicker(for: key)
                    }
                }
            }
            if let problem = problem(for: key) {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func numberField(for key: SettingKey) -> some View {
        TextField("", text: textBinding(for: key))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 72)
    }

    private func unitPicker(for key: SettingKey) -> some View {
        Picker("", selection: unitBinding(for: key)) {
            ForEach(DurationUnit.allCases) { unit in
                Text(unit.title)
                    .tag(unit)
            }
        }
        .labelsHidden()
        .frame(width: 100)
    }

    private func hourPicker(for key: SettingKey) -> some View {
        Picker("", selection: hourBinding(for: key)) {
            ForEach(Array(key.range), id: \.self) { hour in
                Text(DurationFormat.hourOfDay(hour, locale: .current))
                    .tag(hour)
            }
        }
        .labelsHidden()
        .frame(width: 120)
    }

    // MARK: - Draft

    private func keys(in group: SettingGroup) -> [SettingKey] {
        SettingKey.allCases.filter { $0.group == group }
    }

    private func textBinding(for key: SettingKey) -> Binding<String> {
        Binding(
            get: {
                draft[key]?.text ?? ""
            },
            set: { text in
                draft[key]?.text = text
            }
        )
    }

    private func unitBinding(for key: SettingKey) -> Binding<DurationUnit> {
        Binding(
            get: {
                draft[key]?.unit ?? .seconds
            },
            set: { unit in
                draft[key]?.unit = unit
            }
        )
    }

    private func hourBinding(for key: SettingKey) -> Binding<Int> {
        Binding(
            get: {
                value(for: key) ?? model.core.setting(key)
            },
            set: { hour in
                draft[key]?.text = "\(hour)"
            }
        )
    }

    /// The draft as stored seconds (or count, or hour), or nil when the text isn't a whole number.
    private func value(for key: SettingKey) -> Int? {
        guard let entry = draft[key] else {
            return nil
        }
        guard let number = Int(entry.text.trimmingCharacters(in: .whitespaces)), number >= 0 else {
            return nil
        }
        guard key.unit == .seconds else {
            return number
        }
        let (seconds, overflow) = number.multipliedReportingOverflow(by: entry.unit.seconds)
        return overflow ? nil : seconds
    }

    private func problem(for key: SettingKey) -> String? {
        guard draft[key] != nil else {
            return nil
        }
        guard let value = value(for: key) else {
            return "Enter a whole number."
        }
        return key.range.contains(value) ? nil : key.rangeMessage(locale: .current)
    }

    private var hasChanges: Bool {
        SettingKey.allCases.contains { key in
            draft[key] != nil && value(for: key) != model.core.setting(key)
        }
    }

    private var hasProblems: Bool {
        SettingKey.allCases.contains { key in
            problem(for: key) != nil
        }
    }

    private func refillDraft() {
        var values: [SettingKey: DraftValue] = [:]
        for key in SettingKey.allCases {
            let current = model.core.setting(key)
            if key.unit == .seconds {
                let unit = DurationUnit.natural(for: current)
                values[key] = DraftValue(text: "\(current / unit.seconds)", unit: unit)
            } else {
                values[key] = DraftValue(text: "\(current)", unit: .seconds)
            }
        }
        draft = values
    }

    private func applyChanges() {
        var lines: [String] = []
        for key in SettingKey.allCases {
            guard let value = value(for: key), value != model.core.setting(key) else {
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
