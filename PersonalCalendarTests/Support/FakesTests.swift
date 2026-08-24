import XCTest
@testable import PersonalCalendar

@MainActor
final class FakesTests: XCTestCase {
    func testCalendarFetchFiltersSelectedSourcesAndTreatsEmptySelectionAsAll() throws {
        let home = event(id: "home-event", calendarID: "home")
        let work = event(id: "work-event", calendarID: "work")
        let subject = FakeCalendarService(access: .granted, events: [home, work])
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: ["home"]).map(\.id), ["home-event"])
        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: ["missing"]), [])
        XCTAssertEqual(try subject.fetchEvents(in: interval, calendarIDs: []).map(\.id), ["home-event", "work-event"])
    }

    func testReminderFetchFiltersSelectedSourcesAndTreatsEmptySelectionAsAll() async throws {
        let home = reminder(id: "home-task", listID: "home")
        let work = reminder(id: "work-task", listID: "work")
        let subject = FakeRemindersService(access: .granted, reminders: [home, work])

        let selected = try await subject.fetchReminders(listIDs: ["home"])
        let missing = try await subject.fetchReminders(listIDs: ["missing"])
        let all = try await subject.fetchReminders(listIDs: [])

        XCTAssertEqual(selected.map(\.id), ["home-task"])
        XCTAssertEqual(missing, [])
        XCTAssertEqual(all.map(\.id), ["home-task", "work-task"])
    }

    private func event(id: String, calendarID: String) -> CalendarEventSnapshot {
        .init(id: id, title: id, start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20), isAllDay: false, calendarID: calendarID, calendarTitle: calendarID, allowsModification: true, hasRecurrence: false)
    }

    private func reminder(id: String, listID: String) -> ReminderSnapshot {
        .init(id: id, title: id, notes: nil, dueDate: nil, dueHasTime: false, priority: 0, listID: listID, listTitle: listID, isCompleted: false, allowsModification: true, hasRecurrence: false)
    }
}
