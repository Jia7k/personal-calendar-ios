import XCTest
@testable import PersonalCalendar

@MainActor
final class TaskQuickRescheduleViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 777_636_000)

    func testTasksPublishOverdueSeparatelyFromToday() async {
        let calendar = singaporeCalendar()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let service = FakeRemindersService(access: .granted, reminders: [
            reminder(id: "overdue", dueDate: yesterday),
            reminder(id: "today", dueDate: now),
            reminder(id: "upcoming", dueDate: tomorrow)
        ])
        let subject = makeSubject(service: service, calendar: calendar)

        await subject.load()

        XCTAssertEqual(subject.overdue.map(\.id), ["overdue"])
        XCTAssertEqual(subject.today.map(\.id), ["today"])
        XCTAssertEqual(subject.upcoming.map(\.id), ["upcoming"])
    }

    func testQuickRescheduleSendsOneExactUpdateAndPublishesUndo() async {
        let calendar = singaporeCalendar()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let item = reminder(id: "overdue", dueDate: original)
        let service = FakeRemindersService(access: .granted, reminders: [item])
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()

        await subject.quickReschedule(id: item.id, command: .tomorrow)

        let expected = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(service.reminderUpdateCalls.count, 1)
        XCTAssertEqual(service.reminderUpdateCalls[0].id, "overdue")
        XCTAssertEqual(service.reminderUpdateCalls[0].draft.schedule, .replace(.init(date: expected, hasTime: true)))
        XCTAssertEqual(service.reminderUpdateCalls[0].draft.alarm, .preserve)
        XCTAssertEqual(service.reminderUpdateCalls[0].draft.recurrence, .preserve)
        XCTAssertNil(service.reminderUpdateCalls[0].draft.listID)
        XCTAssertEqual(subject.rescheduleUndo, .init(reminderID: "overdue", previousSchedule: .init(date: original, hasTime: true)))
    }

    func testQuickRescheduleFailureRetainsConfirmedSections() async {
        let calendar = singaporeCalendar()
        let item = reminder(id: "overdue", dueDate: calendar.date(byAdding: .day, value: -1, to: now)!)
        let service = FakeRemindersService(access: .granted, reminders: [item])
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        service.updateError = RescheduleTestError.failed

        await subject.quickReschedule(id: item.id, command: .tomorrow)

        XCTAssertEqual(subject.overdue.map(\.id), ["overdue"])
        XCTAssertTrue(subject.today.isEmpty)
        XCTAssertNil(subject.rescheduleUndo)
        XCTAssertTrue(service.reminderUpdateCalls.isEmpty)
    }

    func testUndoRestoresTheExactPreviousScheduleOnce() async {
        let calendar = singaporeCalendar()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let item = reminder(id: "overdue", dueDate: original)
        let service = FakeRemindersService(access: .granted, reminders: [item])
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.quickReschedule(id: item.id, command: .tomorrow)

        await subject.undoQuickReschedule()

        XCTAssertEqual(service.reminderUpdateCalls.count, 2)
        XCTAssertEqual(service.reminderUpdateCalls[1].draft.schedule, .replace(.init(date: original, hasTime: true)))
        XCTAssertNil(subject.rescheduleUndo)
        await subject.undoQuickReschedule()
        XCTAssertEqual(service.reminderUpdateCalls.count, 2)
    }

    func testStaleProfileTaskCannotBeRescheduledOrUndone() async {
        let calendar = singaporeCalendar()
        let profileA = UUID()
        let profileB = UUID()
        var activeScope = scope(id: profileA, reminderListIDs: ["school"])
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let item = reminder(id: "overdue", dueDate: original, listID: "school")
        let service = FakeRemindersService(access: .granted, reminders: [item])
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { activeScope },
            calendar: calendar,
            now: { self.now }
        )
        await subject.load()

        activeScope = scope(id: profileB, reminderListIDs: ["work"])
        await subject.quickReschedule(id: item.id, command: .tomorrow)
        XCTAssertTrue(service.reminderUpdateCalls.isEmpty)
        XCTAssertNil(subject.rescheduleUndo)

        activeScope = scope(id: profileA, reminderListIDs: ["school"])
        await subject.load()
        await subject.quickReschedule(id: item.id, command: .tomorrow)
        XCTAssertEqual(service.reminderUpdateCalls.count, 1)
        activeScope = scope(id: profileB, reminderListIDs: ["work"])
        await subject.undoQuickReschedule()
        XCTAssertEqual(service.reminderUpdateCalls.count, 1)
    }

    private func makeSubject(service: FakeRemindersService, calendar: Calendar) -> TasksViewModel {
        TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            calendar: calendar,
            now: { self.now }
        )
    }

    private func reminder(id: String, dueDate: Date, listID: String = "list") -> ReminderSnapshot {
        .init(id: id, title: id, notes: "Keep", dueDate: dueDate, dueHasTime: true, priority: 1, listID: listID, listTitle: listID, isCompleted: false, allowsModification: true, hasRecurrence: false)
    }

    private func scope(id: UUID, reminderListIDs: Set<String>) -> ProfileScope {
        .init(identity: .saved(id), calendarIDs: [], reminderListIDs: reminderListIDs, routineIDs: [], defaultCalendarID: nil, defaultReminderListID: nil)
    }

    private func singaporeCalendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }
}

private enum RescheduleTestError: Error {
    case failed
}
