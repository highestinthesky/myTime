import Foundation

extension EngineCore {
    mutating func applyBookingTransitions(_ input: UpdateInput) -> [EngineEffect] {
        var effects: [EngineEffect] = []
        if let activeIndex = state.bookings.firstIndex(where: { $0.isActive(at: now) }) {
            if state.bookings[activeIndex].id != runtime.lastActiveBookingID {
                effects.append(.bookingStarted(bookingID: state.bookings[activeIndex].id))
            }
            let bookedAppIsRunning = input.runningAppIDs.contains { appID in
                app(id: appID)?.modes.contains(.booked) == true
            }
            if bookedAppIsRunning {
                state.bookings[activeIndex].appOpened = true
            }
            if !state.bookings[activeIndex].warned
                && state.bookings[activeIndex].end.timeIntervalSince(now) <= Constants.bookingHeadsUp
            {
                state.bookings[activeIndex].warned = true
                effects.append(.bookingHeadsUp(bookingID: state.bookings[activeIndex].id))
            }
        }

        if let previousID = runtime.lastActiveBookingID {
            let isStillActive = state.bookings.contains { booking in
                booking.id == previousID && booking.isActive(at: now)
            }
            if !isStillActive {
                record(.bookingEnded, "Session ended")
                for app in state.settings.apps where app.modes.contains(.booked) {
                    effects.append(.terminateIfNotAllowed(appID: app.id))
                }
            }
        }
        runtime.lastActiveBookingID = activeBooking?.id
        return effects
    }

    func chargedSeconds(of booking: Booking) -> Int {
        if booking.canceledAt != nil {
            return 0
        }
        let bookedSeconds = booking.durationSeconds + booking.extensionSeconds
        if !booking.isFinished(at: now) {
            return bookedSeconds
        }
        guard booking.appOpened else {
            return 0
        }
        let actualEnd = booking.endedAt ?? booking.end
        let elapsed = max(0, actualEnd.timeIntervalSince(booking.start))
        let roundedMinutes = Int(ceil(elapsed / 60))
        return min(bookedSeconds, roundedMinutes * 60)
    }

    public func allowanceRemaining(weekOf date: Date) -> Int {
        let weekKey = CalendarKeys.weekKey(date, dayStartHour: dayStartHour, timeZone: timeZone)
        if state.weekly[weekKey]?.allowanceForfeited == true {
            return 0
        }
        let charged = state.bookings
            .filter {
                CalendarKeys.weekKey($0.start, dayStartHour: dayStartHour, timeZone: timeZone) == weekKey
            }
            .reduce(0) { total, booking in
                total + chargedSeconds(of: booking)
            }
        return max(0, setting(.weeklyAllowanceSeconds) - charged)
    }

    public func validateBooking(start: Date, durationSeconds: Int) -> EngineError? {
        let leadSeconds = setting(.bookingLeadSeconds)
        if start < now.addingTimeInterval(Double(leadSeconds)) {
            return .bookingTooSoon(leadSeconds: leadSeconds)
        }
        if start > now.addingTimeInterval(Double(Constants.bookingHorizonSeconds)) {
            return .bookingTooFar
        }
        let maximum = setting(.bookingMaxSeconds)
        if durationSeconds < Constants.bookingMinSeconds
            || durationSeconds > maximum
            || durationSeconds % Constants.bookingDurationStepSeconds != 0
        {
            return .invalidDuration(minSeconds: Constants.bookingMinSeconds, maxSeconds: maximum)
        }
        let end = start.addingTimeInterval(Double(durationSeconds))
        let overlaps = state.bookings.contains { booking in
            (booking.isUpcoming(at: now) || booking.isActive(at: now))
                && start < booking.end
                && booking.start < end
        }
        if overlaps {
            return .bookingOverlap
        }
        if allowanceRemaining(weekOf: start) < durationSeconds {
            return .allowanceExceeded
        }
        return nil
    }

    public mutating func createBooking(start: Date, durationSeconds: Int) throws -> Booking {
        if let error = validateBooking(start: start, durationSeconds: durationSeconds) {
            throw error
        }
        let booking = Booking(start: start, durationSeconds: durationSeconds, createdAt: now)
        state.bookings.append(booking)
        record(.bookingCreated, "Booked a session · \(DurationFormat.short(Double(durationSeconds)))")
        return booking
    }

    public mutating func cancelBooking(id: UUID) throws {
        guard let index = state.bookings.firstIndex(where: { $0.id == id }) else {
            throw EngineError.cannotCancel
        }
        guard state.bookings[index].isUpcoming(at: now) else {
            throw EngineError.cannotCancel
        }
        let duration = state.bookings[index].durationSeconds
        state.bookings[index].canceledAt = now
        record(.bookingCanceled, "Canceled a session · \(DurationFormat.short(Double(duration)))")
    }

    public mutating func endBooking(id: UUID) {
        guard let index = state.bookings.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard state.bookings[index].isActive(at: now) else {
            return
        }
        state.bookings[index].endedAt = now
    }

    public func canExtendBooking(id: UUID) -> Bool {
        guard let booking = state.bookings.first(where: { $0.id == id }) else {
            return false
        }
        guard booking.isActive(at: now) else {
            return false
        }
        let extensionSeconds = setting(.bookingExtensionSeconds)
        guard booking.extensionSeconds == 0 && extensionSeconds > 0 else {
            return false
        }
        guard allowanceRemaining(weekOf: booking.start) >= extensionSeconds else {
            return false
        }
        let extendedEnd = booking.end.addingTimeInterval(Double(extensionSeconds))
        return !state.bookings.contains { other in
            other.id != booking.id
                && other.isUpcoming(at: now)
                && booking.start < other.end
                && other.start < extendedEnd
        }
    }

    public mutating func extendBooking(id: UUID) throws {
        guard canExtendBooking(id: id) else {
            throw EngineError.cannotExtendBooking
        }
        guard let index = state.bookings.firstIndex(where: { $0.id == id }) else {
            throw EngineError.cannotExtendBooking
        }
        let extensionSeconds = setting(.bookingExtensionSeconds)
        state.bookings[index].extensionSeconds = extensionSeconds
        record(.bookingExtended, "Extended session · +\(DurationFormat.short(Double(extensionSeconds)))")
    }

    public var upcomingBookings: [Booking] {
        state.bookings
            .filter { $0.isUpcoming(at: now) }
            .sorted { $0.start < $1.start }
    }

    public var bookingDurations: [Int] {
        Array(
            stride(
                from: Constants.bookingMinSeconds,
                through: setting(.bookingMaxSeconds),
                by: Constants.bookingDurationStepSeconds
            )
        )
    }

    public func bookingDays() -> [Date] {
        let calendar = bookingCalendar
        let today = calendar.startOfDay(for: now)
        return (0...6).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return nil
            }
            return bookingStartSlots(onDayOf: day).isEmpty ? nil : day
        }
    }

    public func bookingStartSlots(onDayOf day: Date) -> [Date] {
        let calendar = bookingCalendar
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        let earliest = max(dayStart, now.addingTimeInterval(Double(setting(.bookingLeadSeconds))))
        let step = Double(Constants.bookingStartStepSeconds)
        let offset = earliest.timeIntervalSince(dayStart)
        let firstOffset = ceil(offset / step) * step
        var slot = dayStart.addingTimeInterval(firstOffset)
        let horizon = now.addingTimeInterval(Double(Constants.bookingHorizonSeconds))
        var slots: [Date] = []
        while slot < dayEnd && slot <= horizon {
            slots.append(slot)
            slot = slot.addingTimeInterval(step)
        }
        return slots
    }

    private var bookingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
