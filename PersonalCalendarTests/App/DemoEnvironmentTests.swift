import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class DemoEnvironmentTests: XCTestCase {
    func testReduceMotionOverrideRequiresExplicitDemoArgument() {
        XCTAssertFalse(AppEnvironment.live(container: makeContainer()).reduceMotionOverride)
        XCTAssertFalse(AppEnvironment.demo(container: makeContainer(), arguments: []).reduceMotionOverride)
        XCTAssertTrue(AppEnvironment.demo(container: makeContainer(), arguments: ["-reduce-motion"]).reduceMotionOverride)
    }

    func testDemoSkipsOnboardingUnlessExplicitlyRequested() {
        XCTAssertTrue(AppEnvironment.demo(container: makeContainer(), arguments: []).settings.didCompleteOnboarding)
        XCTAssertFalse(AppEnvironment.demo(container: makeContainer(), arguments: ["-show-onboarding"]).settings.didCompleteOnboarding)
    }

    func testCalendarDenialLeavesDemoRemindersAndRoutinesUsable() async throws {
        let environment = AppEnvironment.demo(container: makeContainer(), arguments: ["-calendar-denied"])
        let day = LocalDay(year: 2026, month: 8, day: 24)
        let interval = DateInterval(start: day.startDate(in: .current), end: day.startDate(in: .current).addingTimeInterval(86_400))

        let reminders = try await environment.reminders.fetchReminders(listIDs: [])
        XCTAssertEqual(try environment.calendar.fetchEvents(in: interval, calendarIDs: []), [])
        XCTAssertEqual(reminders.map(\.id), ["demo-task"])
        XCTAssertEqual(try environment.routines.list(includeArchived: false).map(\.title), ["Read"])
    }

    func testDemoSourcesFilterSelectedIDsAndTreatEmptySelectionAsAll() async throws {
        let environment = AppEnvironment.demo(container: makeContainer(), arguments: [])
        let now = Date()
        let interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400))

        let missingReminders = try await environment.reminders.fetchReminders(listIDs: ["missing"])
        let allReminders = try await environment.reminders.fetchReminders(listIDs: [])
        XCTAssertEqual(try environment.calendar.fetchEvents(in: interval, calendarIDs: ["missing"]), [])
        XCTAssertEqual(try environment.calendar.fetchEvents(in: interval, calendarIDs: []).map(\.id), ["demo-event"])
        XCTAssertEqual(missingReminders, [])
        XCTAssertEqual(allReminders.map(\.id), ["demo-task"])
    }

    func testMultiSourceDemoKeepsOtherCalendarContentWhenOneSourceIsHidden() throws {
        let subject = DemoCalendarService(access: .granted, multipleSources: true)
        let now = Date()
        let interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400))

        XCTAssertEqual(subject.calendars().map(\.id), ["demo-calendar", "demo-calendar-work"])
        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: ["demo-calendar-work"]).map(\.title), ["Planning"])
        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: ["demo-calendar"]).map(\.title), ["Coffee"])
    }

    func testMultiSourceDemoEnvironmentIncludesAlternateReminderList() {
        let environment = AppEnvironment.demo(container: makeContainer(), arguments: ["-demo-multiple-sources"])

        XCTAssertEqual(environment.reminders.lists().map(\.id), ["demo-list", "demo-list-alternate"])
    }

    func testDeniedAndRestrictedDemoRequestsAndMutationsDoNotGrantOrChangeContent() async throws {
        for access in [AccessState.denied, .restricted] {
            let calendar = DemoCalendarService(access: access)
            let reminders = DemoRemindersService(access: access)
            let calendarResult = await calendar.requestFullAccess()
            let reminderResult = await reminders.requestFullAccess()
            XCTAssertEqual(calendarResult, access)
            XCTAssertEqual(reminderResult, access)
            XCTAssertThrowsError(try calendar.createEvent(.init(title: "No", start: .now, end: .now.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
            XCTAssertThrowsError(try reminders.createReminder(.init(title: "No", notes: nil, dueDate: nil, priority: 0)))
            XCTAssertThrowsError(try reminders.setCompleted(id: "demo-task", completed: true))
            let values = try await reminders.fetchReminders(listIDs: [])
            XCTAssertEqual(values, [])
        }
    }

    func testDemoEventCreationPersistsInFetchedEvents() throws {
        let subject = DemoCalendarService(access: .granted)
        let start = Date(timeIntervalSince1970: 10_000)
        let id = try subject.createEvent(.init(title: "Walk", start: start, end: start.addingTimeInterval(1_800), isAllDay: false, calendarID: nil))

        let fetched = try subject.fetchEvents(in: DateInterval(start: start.addingTimeInterval(-1), end: start.addingTimeInterval(1_801)), calendarIDs: [])
        XCTAssertEqual(id, "demo-event-2")
        XCTAssertEqual(fetched.map(\.id), ["demo-event-2"])
        XCTAssertEqual(fetched.first?.title, "Walk")
        XCTAssertEqual(fetched.first?.calendarID, "demo-calendar")
        XCTAssertEqual(fetched.first?.calendarTitle, "Personal")
    }

    func testDemoEventCreationUsesExactWritableDestinationAndRejectsInvalidIDs() throws {
        let subject = DemoCalendarService(access: .granted, multipleSources: true, includeReadOnlySource: true)
        let start = Date(timeIntervalSince1970: 20_000)

        let id = try subject.createEvent(.init(title: "Work", start: start, end: start.addingTimeInterval(600), isAllDay: false, calendarID: "demo-calendar-work"))

        let fetched = try subject.fetchEvents(in: DateInterval(start: start.addingTimeInterval(-1), end: start.addingTimeInterval(601)), calendarIDs: ["demo-calendar-work"])
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.calendarID, "demo-calendar-work")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.calendarTitle, "Work")
        XCTAssertThrowsError(try subject.createEvent(.init(title: "Missing", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "missing")))
        XCTAssertThrowsError(try subject.createEvent(.init(title: "Read only", start: start, end: start.addingTimeInterval(60), isAllDay: false, calendarID: "demo-calendar-read-only")))
    }

    func testDemoReminderCreationAndCompletionPersistInFetchedReminders() async throws {
        let subject = DemoRemindersService(access: .granted)
        let id = try subject.createReminder(.init(title: "Call", notes: "Mom", dueDate: nil, priority: 1))
        try subject.setCompleted(id: id, completed: true)

        let fetched = try await subject.fetchReminders(listIDs: [])
        XCTAssertEqual(fetched.map(\.id), ["demo-task", "demo-task-2"])
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.title, "Call")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.isCompleted, true)
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.listID, "demo-list")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.listTitle, "Tasks")
    }

    func testDemoReminderCreationUsesExactWritableDestinationAndRejectsInvalidIDs() async throws {
        let subject = DemoRemindersService(access: .granted, multipleSources: true, includeReadOnlySource: true)

        let id = try subject.createReminder(.init(title: "Alternate", notes: nil, dueDate: nil, priority: 1, listID: "demo-list-alternate"))

        let fetched = try await subject.fetchReminders(listIDs: ["demo-list-alternate"])
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.listID, "demo-list-alternate")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.listTitle, "Alternate")
        XCTAssertThrowsError(try subject.createReminder(.init(title: "Missing", notes: nil, dueDate: nil, priority: 1, listID: "missing")))
        XCTAssertThrowsError(try subject.createReminder(.init(title: "Read only", notes: nil, dueDate: nil, priority: 1, listID: "demo-list-read-only")))
    }

    func testDemoRoutineMutationsPersist() throws {
        let subject = DemoRoutineRepository()
        let id = try subject.create(.init(title: "Stretch", weekdays: [1], window: .morning, reminderHour: 8, reminderMinute: 0))
        let day = LocalDay(year: 2026, month: 8, day: 24)
        try subject.setPaused(id: id, paused: true)
        try subject.setCompleted(routineID: id, day: day, completed: true)

        XCTAssertEqual(try subject.list(includeArchived: false).first(where: { $0.id == id })?.isPaused, true)
        XCTAssertTrue(try subject.isCompleted(routineID: id, day: day))
    }

    private func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: RoutineRecord.self, RoutineCompletionRecord.self, configurations: configuration)
    }
}
