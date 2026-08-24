import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class DemoEnvironmentTests: XCTestCase {
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

    func testDemoEventCreationPersistsInFetchedEvents() throws {
        let subject = DemoCalendarService(access: .granted)
        let start = Date(timeIntervalSince1970: 10_000)
        let id = try subject.createEvent(.init(title: "Walk", start: start, end: start.addingTimeInterval(1_800), isAllDay: false, calendarID: nil))

        let fetched = try subject.fetchEvents(in: DateInterval(start: start.addingTimeInterval(-1), end: start.addingTimeInterval(1_801)), calendarIDs: [])
        XCTAssertEqual(id, "demo-event-2")
        XCTAssertEqual(fetched.map(\.id), ["demo-event-2"])
        XCTAssertEqual(fetched.first?.title, "Walk")
    }

    func testDemoReminderCreationAndCompletionPersistInFetchedReminders() async throws {
        let subject = DemoRemindersService(access: .granted)
        let id = try subject.createReminder(.init(title: "Call", notes: "Mom", dueDate: nil, priority: 1))
        try subject.setCompleted(id: id, completed: true)

        let fetched = try await subject.fetchReminders(listIDs: [])
        XCTAssertEqual(fetched.map(\.id), ["demo-task", "demo-task-2"])
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.title, "Call")
        XCTAssertEqual(fetched.first(where: { $0.id == id })?.isCompleted, true)
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
