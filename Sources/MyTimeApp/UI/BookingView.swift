import MyTimeCore
import SwiftUI

@MainActor
struct BookingView: View {
    let model: AppModel
    let onDone: () -> Void
    @State private var day: Date?
    @State private var start: Date?
    @State private var duration: Int?
    @State private var errorMessage: String?

    init(model: AppModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Picker("Day", selection: $day) {
                    ForEach(model.core.bookingDays(), id: \.self) { choice in
                        Text(dayLabel(choice))
                            .tag(Optional(choice))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: day) {
                    start = slots.first
                    errorMessage = nil
                }

                Picker("Start", selection: $start) {
                    ForEach(visibleSlots, id: \.self) { choice in
                        Text(DurationFormat.timeOfDay(choice, timeZone: .current, locale: .current))
                            .tag(Optional(choice))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: start) {
                    errorMessage = nil
                }

                Picker("Length", selection: $duration) {
                    ForEach(model.core.bookingDurations, id: \.self) { choice in
                        Text(DurationFormat.short(Double(choice)))
                            .tag(Optional(choice))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: duration) {
                    errorMessage = nil
                }
            }

            Text(allowanceLine)
                .foregroundStyle(.secondary)
            Text(validationLine)
                .foregroundStyle(.secondary)
                .frame(height: 20)

            HStack {
                Spacer()
                Button("Cancel") {
                    onDone()
                }
                .keyboardShortcut(.cancelAction)
                Button("Book") {
                    book()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationError != nil || start == nil || duration == nil)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            let firstDay = model.core.bookingDays().first
            day = firstDay
            start = firstDay.flatMap { model.core.bookingStartSlots(onDayOf: $0).first }
            duration = model.core.bookingDurations.first
        }
    }

    private var slots: [Date] {
        day.map { model.core.bookingStartSlots(onDayOf: $0) } ?? []
    }

    private var visibleSlots: [Date] {
        #if DEV_TIMESCALE
            return Array(slots.prefix(30))
        #else
            return slots
        #endif
    }

    private var validationError: EngineError? {
        guard let start, let duration else {
            return nil
        }
        return model.core.validateBooking(start: start, durationSeconds: duration)
    }

    private var validationLine: String {
        errorMessage ?? validationError?.userMessage ?? " "
    }

    private var allowanceLine: String {
        guard let start else {
            return " "
        }
        let remaining = model.core.allowanceRemaining(weekOf: start)
        return "\(DurationFormat.short(Double(remaining))) left in that week"
    }

    private func dayLabel(_ date: Date) -> String {
        DurationFormat.dayLabel(
            date,
            now: model.displayNow,
            timeZone: .current,
            locale: .current
        )
    }

    private func book() {
        guard let start, let duration else {
            return
        }
        do {
            try model.createBooking(start: start, durationSeconds: duration)
            onDone()
        } catch let error as EngineError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = nil
        }
    }
}
