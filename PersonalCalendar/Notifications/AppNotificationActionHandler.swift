import Foundation

@MainActor
final class AppNotificationActionHandler {
    private let routines: any RoutineRepository
    private let scheduler: any NotificationScheduling
    private let calendar: Calendar
    private let now: () -> Date
    private let isRoutineInNotificationScope: @MainActor (UUID) -> Bool

    init(
        routines: any RoutineRepository,
        scheduler: any NotificationScheduling,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        isRoutineInNotificationScope: @escaping @MainActor (UUID) -> Bool = { _ in true }
    ) {
        self.routines = routines
        self.scheduler = scheduler
        self.calendar = calendar
        self.now = now
        self.isRoutineInNotificationScope = isRoutineInNotificationScope
    }

    func handle(actionIdentifier: String, userInfo: [String: String]) async {
        guard actionIdentifier == NotificationActionIdentifier.routineComplete
                || actionIdentifier == NotificationActionIdentifier.routineSnooze15,
              let routineIDValue = userInfo[NotificationPayloadKey.routineID],
              let routineID = UUID(uuidString: routineIDValue),
              let encodedDay = userInfo[NotificationPayloadKey.localDay],
              let payloadDay = decodeLocalDay(encodedDay)
        else { return }

        let responseDate = now()
        let currentDay = LocalDay(date: responseDate, calendar: calendar)
        guard payloadDay == currentDay,
              isRoutineInNotificationScope(routineID),
              let routine = try? routines.list(includeArchived: true).first(where: { $0.id == routineID }),
              !routine.isPaused,
              !routine.isArchived,
              routine.reminderHour != nil,
              routine.reminderMinute != nil,
              routine.weekdays.contains(calendar.component(.weekday, from: responseDate))
        else { return }

        switch actionIdentifier {
        case NotificationActionIdentifier.routineComplete:
            guard (try? routines.isCompleted(routineID: routineID, day: currentDay)) == false else {
                return
            }
            try? routines.setCompleted(routineID: routineID, day: currentDay, completed: true)

        case NotificationActionIdentifier.routineSnooze15:
            guard let fireDate = calendar.date(byAdding: .minute, value: 15, to: responseDate) else {
                return
            }
            try? await scheduler.schedule(.init(
                identifier: "snooze|\(routine.id.uuidString)|\(encodedDay)",
                title: routine.title,
                body: "A gentle reminder for your routine.",
                fireDate: fireDate,
                categoryIdentifier: NotificationCategoryIdentifier.routineReminder,
                userInfo: userInfo
            ))

        default:
            return
        }
    }

    private func decodeLocalDay(_ value: String) -> LocalDay? {
        let bytes = Array(value.utf8)
        guard bytes.count == 10,
              bytes[4] == 45,
              bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48 ... 57).contains(byte)
              })
        else { return nil }

        let year = decimal(bytes[0 ... 3])
        let month = decimal(bytes[5 ... 6])
        let day = decimal(bytes[8 ... 9])
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day
        else { return nil }
        return .init(year: year, month: month, day: day)
    }

    private func decimal(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { partialResult, byte in
            (partialResult * 10) + Int(byte - 48)
        }
    }
}
