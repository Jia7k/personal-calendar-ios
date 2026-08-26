import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class AppRouteHostResolverTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testCalendarNavigationSignalPreservesDayAndIsConsumedOnce() {
        let signal = CalendarDeepLinkSignal(
            id: UUID(),
            day: .init(year: 2026, month: 8, day: 27),
            entryID: nil
        )
        var resolver = CalendarDeepLinkResolver()

        XCTAssertEqual(
            resolver.resolve(signal, events: []),
            .navigate(day: signal.day)
        )
        XCTAssertEqual(resolver.lastSignalID, signal.id)
        XCTAssertNil(resolver.resolve(signal, events: []))
    }

    func testCalendarResolverMatchesBothDisplayIdentityAndOccurrenceStart() {
        let targetStart = Date(timeIntervalSince1970: 1_788_000_000)
        let wrongOccurrence = event(
            id: "target-display-id",
            title: "Wrong occurrence",
            start: targetStart.addingTimeInterval(3_600)
        )
        let wrongDisplayIdentity = event(
            id: "other-display-id",
            title: "Wrong event",
            start: targetStart
        )
        let target = event(
            id: "target-display-id",
            title: "Target class",
            start: targetStart
        )
        let day = AppRouteDay(year: 2026, month: 8, day: 27)
        let signal = CalendarDeepLinkSignal(
            id: UUID(),
            day: day,
            entryID: AppRouteEntryIdentity.make(
                displayID: target.id,
                occurrenceStart: target.start
            )
        )
        var resolver = CalendarDeepLinkResolver()

        XCTAssertEqual(
            resolver.resolve(
                signal,
                events: [wrongOccurrence, wrongDisplayIdentity, target]
            ),
            .open(day: day, event: target)
        )
        XCTAssertNil(
            resolver.resolve(
                signal,
                events: [wrongOccurrence, wrongDisplayIdentity, target]
            )
        )
    }

    func testCalendarResolverFailsClosedForMissingOpaqueEntry() {
        let signal = CalendarDeepLinkSignal(
            id: UUID(),
            day: .init(year: 2026, month: 8, day: 27),
            entryID: "entry-does-not-exist"
        )
        var resolver = CalendarDeepLinkResolver()

        XCTAssertEqual(
            resolver.resolve(
                signal,
                events: [event(
                    id: "available-event",
                    title: "Must not be opened",
                    start: Date(timeIntervalSince1970: 1_788_000_000)
                )]
            ),
            .unavailable
        )
        XCTAssertEqual(resolver.lastSignalID, signal.id)
        XCTAssertNil(resolver.resolve(signal, events: []))
    }

    func testTaskResolverReturnsOnlyTheCurrentExactReminderAndConsumesSignalOnce() {
        let other = reminder(id: "other-task", title: "Other")
        let target = reminder(id: "target-task", title: "Target")
        let signal = TaskDeepLinkSignal(id: UUID(), reminderID: target.id)
        var resolver = TaskDeepLinkResolver()

        XCTAssertEqual(
            resolver.resolve(signal, reminders: [other, target]),
            .open(target)
        )
        XCTAssertEqual(resolver.lastSignalID, signal.id)
        XCTAssertNil(resolver.resolve(signal, reminders: [target]))

        let repeatedTarget = TaskDeepLinkSignal(
            id: UUID(),
            reminderID: target.id
        )
        XCTAssertEqual(
            resolver.resolve(repeatedTarget, reminders: [target]),
            .open(target)
        )
    }

    func testTaskResolverFailsClosedWhenCurrentReminderIsMissing() {
        let signal = TaskDeepLinkSignal(id: UUID(), reminderID: "missing-task")
        var resolver = TaskDeepLinkResolver()

        XCTAssertEqual(
            resolver.resolve(
                signal,
                reminders: [reminder(id: "available-task", title: "Must not open")]
            ),
            .unavailable
        )
        XCTAssertEqual(resolver.lastSignalID, signal.id)
        XCTAssertNil(resolver.resolve(signal, reminders: []))
    }

    func testCalendarViewModelJumpConvertsRouteDayAndLoadsItsMonth() async {
        let routeDay = AppRouteDay(year: 2027, month: 1, day: 12)
        let targetDay = LocalDay(year: 2027, month: 1, day: 12)
        let start = targetDay.startDate(in: calendar).addingTimeInterval(9 * 3_600)
        let target = event(id: "january-class", title: "January class", start: start)
        let calendarService = FakeCalendarService(
            access: .granted,
            events: [target],
            descriptors: [
                .init(
                    id: "school",
                    title: "School",
                    colorHex: "#4868A8",
                    allowsContentModifications: true
                )
            ]
        )
        let scope = ProfileScope(
            identity: .saved(UUID()),
            calendarIDs: ["school"],
            reminderListIDs: [],
            routineIDs: [],
            defaultCalendarID: "school",
            defaultReminderListID: nil
        )
        let model = CalendarViewModel(
            today: .init(year: 2026, month: 8, day: 27),
            calendarService: calendarService,
            remindersService: FakeRemindersService(access: .granted),
            routines: FakeRoutineRepository(),
            composer: AgendaComposer(),
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { scope },
            systemCalendar: calendar
        )

        await model.jump(to: routeDay)

        XCTAssertEqual(model.selectedDay, targetDay)
        XCTAssertEqual(model.displayedMonth, LocalDay(year: 2027, month: 1, day: 1))
        XCTAssertEqual(model.agenda.scheduled.map(\.title), ["January class"])
        XCTAssertEqual(calendarService.fetchCalendarIDs, [["school"]])
        XCTAssertEqual(calendarService.fetchIntervals.last?.contains(start), true)
    }

    func testCalendarRouteRequiresAuthoritativeFetchInsteadOfStaleCachedEvent() async {
        let routeDay = AppRouteDay(year: 2026, month: 8, day: 27)
        let targetDay = LocalDay(year: 2026, month: 8, day: 27)
        let start = targetDay.startDate(in: calendar).addingTimeInterval(9 * 3_600)
        let target = event(id: "cached-class", title: "Cached class", start: start)
        let calendarService = FakeCalendarService(
            access: .granted,
            events: [target],
            descriptors: [
                .init(
                    id: "school",
                    title: "School",
                    colorHex: "#4868A8",
                    allowsContentModifications: true
                )
            ]
        )
        let scope = ProfileScope(
            identity: .saved(UUID()),
            calendarIDs: ["school"],
            reminderListIDs: [],
            routineIDs: [],
            defaultCalendarID: "school",
            defaultReminderListID: nil
        )
        let model = CalendarViewModel(
            today: targetDay,
            calendarService: calendarService,
            remindersService: FakeRemindersService(access: .granted),
            routines: FakeRoutineRepository(),
            composer: AgendaComposer(),
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { scope },
            systemCalendar: calendar
        )
        await model.load()
        XCTAssertEqual(model.routeEvents, [target])

        calendarService.fetchError = RouteFetchError.failed

        XCTAssertNil(model.authoritativeRouteEvents(for: routeDay))
        XCTAssertEqual(model.routeEvents, [target])
    }

    func testCancelledHostRouteFailsOnlyWhenNoLocalPresentationIsDeferringIt() {
        XCTAssertTrue(HostRouteCancellationPolicy.shouldFinishAsUnavailable(
            taskIsCancelled: true,
            signalIsCurrent: true,
            localPresentationIsActive: false,
            presentationGenerationIsUnchanged: true
        ))
        XCTAssertFalse(HostRouteCancellationPolicy.shouldFinishAsUnavailable(
            taskIsCancelled: true,
            signalIsCurrent: true,
            localPresentationIsActive: true,
            presentationGenerationIsUnchanged: true
        ))
        XCTAssertFalse(HostRouteCancellationPolicy.shouldFinishAsUnavailable(
            taskIsCancelled: true,
            signalIsCurrent: false,
            localPresentationIsActive: false,
            presentationGenerationIsUnchanged: true
        ))
        XCTAssertFalse(HostRouteCancellationPolicy.shouldFinishAsUnavailable(
            taskIsCancelled: false,
            signalIsCurrent: true,
            localPresentationIsActive: false,
            presentationGenerationIsUnchanged: true
        ))
        XCTAssertFalse(HostRouteCancellationPolicy.shouldFinishAsUnavailable(
            taskIsCancelled: true,
            signalIsCurrent: true,
            localPresentationIsActive: false,
            presentationGenerationIsUnchanged: false
        ))
    }

    private func event(
        id: String,
        title: String,
        start: Date
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: id,
            title: title,
            start: start,
            end: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func reminder(id: String, title: String) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id,
            title: title,
            notes: nil,
            dueDate: nil,
            priority: 0,
            listID: "school-list",
            listTitle: "School",
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
    }
}

private enum RouteFetchError: Error {
    case failed
}
