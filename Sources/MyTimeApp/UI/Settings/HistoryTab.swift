import SwiftUI
import MyTimeCore

@MainActor
struct HistoryTab: View {
    let model: AppModel

    var body: some View {
        if days.isEmpty {
            Text("No history yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(days, id: \.self) { day in
                    Section(dayTitle(day)) {
                        ForEach(eventsByDay[day] ?? []) { event in
                            HStack(alignment: .firstTextBaseline) {
                                Text(
                                    DurationFormat.timeOfDay(
                                        event.date,
                                        timeZone: .current,
                                        locale: .current
                                    )
                                )
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                                Text(event.text)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentEvents: [HistoryEvent] {
        let cutoff = model.displayNow.addingTimeInterval(-7 * 86_400)
        return model.core.state.history
            .filter { $0.date >= cutoff }
            .reversed()
    }

    private var eventsByDay: [Date: [HistoryEvent]] {
        Dictionary(grouping: recentEvents) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }

    private var days: [Date] {
        eventsByDay.keys.sorted(by: >)
    }

    private func dayTitle(_ day: Date) -> String {
        DurationFormat.historyDay(
            day,
            now: model.displayNow,
            timeZone: .current,
            locale: .current
        )
    }
}
