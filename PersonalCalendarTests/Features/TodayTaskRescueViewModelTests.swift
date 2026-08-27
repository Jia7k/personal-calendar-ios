import XCTest
@testable import PersonalCalendar

@MainActor
final class TodayTaskRescueViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_777_271_400) // 2026-04-29 09:30 Asia/Singapore

    func testOverdueTasksExposePositiveCalendarDayAgeAndStableDueOrder() async throws {
        let calendar = singaporeCalendar()
        let today = calendar.startOfDay(for: now)
        let twoDaysAgoLate = try XCTUnwrap(calendar.date(byAdding: .minute, value: -1, to: calendar.date(byAdding: .day, value: -1, to: today)!))
        let yesterdayEarly = try XCTUnwrap(calendar.date(byAdding: .minute, value: 1, to: calendar.date(byAdding: .day, value: -1, to: today)!))
        let service = FakeRemindersService(access: .granted, reminders: [
            reminder(id: "b", dueDate: yesterdayEarly),
            reminder(id: "two-days", dueDate: twoDaysAgoLate),
            reminder(id: "a", dueDate: yesterdayEarly)
        ])
        let subject = makeSubject(service: service, calendar: calendar)

        await subject.load()

        XCTAssertEqual(subject.overdueTasks.map(\.id), ["two-days", "a", "b"])
        XCTAssertEqual(subject.overdueTasks.map(\.daysOverdue), [2, 1, 1])
        XCTAssertTrue(subject.overdueTasks.allSatisfy { $0.daysOverdue > 0 })
    }

    func testOverdueTasksAreRemovedFromGenericAgendaWithoutRemovingTodaysTasks() async throws {
        let calendar = singaporeCalendar()
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let service = FakeRemindersService(access: .granted, reminders: [
            reminder(id: "overdue", dueDate: yesterday, priority: 9),
            reminder(id: "today", dueDate: now, priority: 9)
        ])
        let subject = makeSubject(service: service, calendar: calendar)

        await subject.load()

        XCTAssertEqual(subject.overdueTasks.map(\.id), ["overdue"])
        let agendaReminderIDs = subject.agenda.allDay.compactMap(\.reminderID)
            + subject.agenda.scheduled.compactMap(\.reminderID)
            + subject.agenda.priority.compactMap(\.reminderID)
        XCTAssertEqual(agendaReminderIDs, ["today"])
    }

    func testDateOnlyAndTimedOverdueDescriptionsRetainTheirProviderSchedule() async throws {
        let calendar = singaporeCalendar()
        let dateOnlyDue = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: now)))
        let timedDue = try XCTUnwrap(calendar.date(byAdding: .hour, value: 16, to: calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))!))
        let service = FakeRemindersService(access: .granted, reminders: [
            reminder(id: "date-only", dueDate: dateOnlyDue, dueHasTime: false),
            reminder(id: "timed", dueDate: timedDue, dueHasTime: true)
        ])
        let subject = makeSubject(service: service, calendar: calendar)

        await subject.load()

        let dateOnly = try XCTUnwrap(subject.overdueTasks.first { $0.id == "date-only" })
        let timed = try XCTUnwrap(subject.overdueTasks.first { $0.id == "timed" })
        XCTAssertEqual(dateOnly.reminder.dueDate, dateOnlyDue)
        XCTAssertFalse(dateOnly.reminder.dueHasTime)
        XCTAssertEqual(timed.reminder.dueDate, timedDue)
        XCTAssertTrue(timed.reminder.dueHasTime)
    }

    func testTodayQuickRescheduleWritesOneExactPreservingDraftAndPublishesUndo() async throws {
        let calendar = singaporeCalendar()
        let original = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let item = reminder(id: "overdue", dueDate: original, title: "Cached", notes: "Keep", priority: 7)
        let service = FakeRemindersService(access: .granted, reminders: [item])
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        service.reminders = [reminder(id: "overdue", dueDate: original, title: "Live", notes: "Live notes", priority: 9)]

        await subject.quickRescheduleTask(id: item.id, command: .tomorrow)

        let expected = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
            .addingTimeInterval(TimeInterval(calendar.dateComponents([.hour, .minute, .second], from: original).hour! * 3_600
                + calendar.dateComponents([.hour, .minute, .second], from: original).minute! * 60
                + calendar.dateComponents([.hour, .minute, .second], from: original).second!))
        XCTAssertEqual(service.reminderUpdateCalls.count, 1)
        let call = try XCTUnwrap(service.reminderUpdateCalls.first)
        XCTAssertEqual(call.id, "overdue")
        XCTAssertEqual(call.draft.title, "Live")
        XCTAssertEqual(call.draft.notes, "Live notes")
        XCTAssertEqual(call.draft.priority, 9)
        XCTAssertEqual(call.draft.schedule, .replace(.init(date: expected, hasTime: true)))
        XCTAssertEqual(call.draft.alarm, .preserve)
        XCTAssertEqual(call.draft.recurrence, .preserve)
        XCTAssertNil(call.draft.listID)
        XCTAssertEqual(subject.latestRescheduleUndo, .init(reminderID: "overdue", previousSchedule: .init(date: original, hasTime: true)))
        XCTAssertNil(subject.rescheduleError)
        XCTAssertTrue(subject.overdueTasks.isEmpty)
    }

    func testTodayUndoRestoresTheExactPreviousScheduleOnce() async throws {
        let calendar = singaporeCalendar()
        let original = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
        let service = FakeRemindersService(access: .granted, reminders: [
            reminder(id: "date-only", dueDate: original, dueHasTime: false)
        ])
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.quickRescheduleTask(id: "date-only", command: .tomorrow)

        await subject.undoLastTaskReschedule()

        XCTAssertEqual(service.reminderUpdateCalls.count, 2)
        XCTAssertEqual(service.reminderUpdateCalls[1].draft.schedule, .replace(.init(date: original, hasTime: false)))
        XCTAssertNil(subject.latestRescheduleUndo)
        XCTAssertEqual(subject.overdueTasks.map(\.id), ["date-only"])
        await subject.undoLastTaskReschedule()
        XCTAssertEqual(service.reminderUpdateCalls.count, 2)
    }

    func testCompletionUndoAndRescheduleUndoCanCoexistForDifferentItems() async throws {
        let calendar = singaporeCalendar()
        let overdueDue = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let service = FakeRemindersService(
            access: .granted,
            reminders: [
                reminder(id: "overdue", dueDate: overdueDue),
                reminder(id: "complete", dueDate: now)
            ],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        let completionItem = try XCTUnwrap(subject.agenda.scheduled.first { $0.reminderID == "complete" })
        await subject.setTaskCompleted(completionItem, completed: true)
        XCTAssertEqual(subject.latestTaskUndo?.rawID, "complete")

        await subject.quickRescheduleTask(id: "overdue", command: .tomorrow)

        XCTAssertEqual(subject.latestTaskUndo?.rawID, "complete")
        XCTAssertEqual(subject.latestRescheduleUndo?.reminderID, "overdue")
        await subject.undoLastTaskReschedule()
        XCTAssertEqual(subject.latestTaskUndo?.rawID, "complete")
        XCTAssertNil(subject.latestRescheduleUndo)
    }

    func testProfileChangeAccessLossProviderDeletionAndExternalScheduleEditClearRescheduleUndoWithoutWriting() async throws {
        let calendar = singaporeCalendar()
        let original = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let changed = try XCTUnwrap(calendar.date(byAdding: .day, value: 4, to: now))

        let profileService = FakeRemindersService(access: .granted, reminders: [reminder(id: "profile", dueDate: original, listID: "school")], descriptors: [descriptor(id: "school"), descriptor(id: "work")])
        var profileScope = scope(id: UUID(), reminderListIDs: ["school"])
        let profileSubject = makeSubject(service: profileService, calendar: calendar, currentScope: { profileScope })
        await profileSubject.load()
        await profileSubject.quickRescheduleTask(id: "profile", command: .tomorrow)
        profileScope = scope(id: UUID(), reminderListIDs: ["work"])
        await profileSubject.undoLastTaskReschedule()
        XCTAssertEqual(profileService.reminderUpdateCalls.count, 1)
        XCTAssertNil(profileSubject.latestRescheduleUndo)

        let accessService = FakeRemindersService(access: .granted, reminders: [reminder(id: "access", dueDate: original)])
        let accessSubject = makeSubject(service: accessService, calendar: calendar)
        await accessSubject.load()
        await accessSubject.quickRescheduleTask(id: "access", command: .tomorrow)
        accessService.accessState = .denied
        await accessSubject.undoLastTaskReschedule()
        XCTAssertEqual(accessService.reminderUpdateCalls.count, 1)
        XCTAssertNil(accessSubject.latestRescheduleUndo)

        let deletedService = FakeRemindersService(access: .granted, reminders: [reminder(id: "deleted", dueDate: original)])
        let deletedSubject = makeSubject(service: deletedService, calendar: calendar)
        await deletedSubject.load()
        await deletedSubject.quickRescheduleTask(id: "deleted", command: .tomorrow)
        deletedService.reminders = []
        await deletedSubject.undoLastTaskReschedule()
        XCTAssertEqual(deletedService.reminderUpdateCalls.count, 1)
        XCTAssertNil(deletedSubject.latestRescheduleUndo)

        let editedService = FakeRemindersService(access: .granted, reminders: [reminder(id: "edited", dueDate: original)])
        let editedSubject = makeSubject(service: editedService, calendar: calendar)
        await editedSubject.load()
        await editedSubject.quickRescheduleTask(id: "edited", command: .tomorrow)
        editedService.reminders = [reminder(id: "edited", dueDate: changed)]
        await editedSubject.undoLastTaskReschedule()
        XCTAssertEqual(editedService.reminderUpdateCalls.count, 1)
        XCTAssertEqual(editedService.reminders.first?.dueDate, changed)
        XCTAssertNil(editedSubject.latestRescheduleUndo)
    }

    func testRecurringReadOnlyCompletedAndOutOfProfileTasksNeverReschedule() async throws {
        let calendar = singaporeCalendar()
        let original = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let profileID = UUID()
        let service = FakeRemindersService(
            access: .granted,
            reminders: [
                reminder(id: "recurring", dueDate: original, listID: "school", hasRecurrence: true),
                reminder(id: "read-only", dueDate: original, listID: "school", allowsModification: false),
                reminder(id: "completed", dueDate: original, listID: "school", isCompleted: true),
                reminder(id: "out-of-profile", dueDate: original, listID: "work")
            ],
            descriptors: [descriptor(id: "school"), descriptor(id: "work")]
        )
        let subject = makeSubject(
            service: service,
            calendar: calendar,
            currentScope: { self.scope(id: profileID, reminderListIDs: ["school"]) }
        )
        await subject.load()

        for id in ["recurring", "read-only", "completed", "out-of-profile"] {
            await subject.quickRescheduleTask(id: id, command: .tomorrow)
        }

        XCTAssertTrue(service.reminderUpdateCalls.isEmpty)
        XCTAssertNotNil(subject.scopedIncompleteReminder(id: "recurring"))
        XCTAssertNotNil(subject.scopedIncompleteReminder(id: "read-only"))
        XCTAssertNil(subject.scopedIncompleteReminder(id: "completed"))
        XCTAssertNil(subject.scopedIncompleteReminder(id: "out-of-profile"))
        service.reminders.removeAll { $0.id == "recurring" }
        XCTAssertNil(subject.scopedIncompleteReminder(id: "recurring"))
    }

    func testEmptyReminderScopeDoesNotFetchAllLists() async {
        let calendar = singaporeCalendar()
        let service = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "hidden", dueDate: now, listID: "hidden")],
            descriptors: [descriptor(id: "hidden")]
        )
        let subject = makeSubject(
            service: service,
            calendar: calendar,
            currentScope: { self.scope(id: UUID(), reminderListIDs: []) }
        )

        await subject.load()

        XCTAssertTrue(service.fetchListIDs.isEmpty)
        XCTAssertTrue(subject.overdueTasks.isEmpty)
        XCTAssertTrue(subject.agenda.allDay.isEmpty)
        XCTAssertTrue(subject.agenda.scheduled.isEmpty)
        XCTAssertTrue(subject.agenda.priority.isEmpty)
    }

    private func makeSubject(
        service: any RemindersServicing,
        calendar: Calendar,
        currentScope: (@MainActor () throws -> ProfileScope)? = nil
    ) -> TodayViewModel {
        if let currentScope {
            return TodayViewModel(
                calendar: FakeCalendarService(access: .granted),
                reminders: service,
                routines: FakeRoutineRepository(),
                composer: AgendaComposer(),
                settings: AppSettingsStore(defaults: .ephemeral),
                currentScope: currentScope,
                calendarProvider: { calendar },
                now: { self.now }
            )
        }
        return TodayViewModel(
            calendar: FakeCalendarService(access: .granted),
            reminders: service,
            routines: FakeRoutineRepository(),
            composer: AgendaComposer(),
            settings: AppSettingsStore(defaults: .ephemeral),
            calendarProvider: { calendar },
            now: { self.now }
        )
    }

    private func reminder(
        id: String,
        dueDate: Date?,
        listID: String = "list",
        title: String? = nil,
        notes: String? = "Keep",
        priority: Int = 1,
        allowsModification: Bool = true,
        hasRecurrence: Bool = false,
        dueHasTime: Bool = true,
        isCompleted: Bool = false
    ) -> ReminderSnapshot {
        .init(
            id: id,
            title: title ?? id,
            notes: notes,
            dueDate: dueDate,
            dueHasTime: dueHasTime,
            priority: priority,
            listID: listID,
            listTitle: listID,
            isCompleted: isCompleted,
            allowsModification: allowsModification,
            hasRecurrence: hasRecurrence
        )
    }

    private func descriptor(id: String, writable: Bool = true) -> ReminderListDescriptor {
        .init(id: id, title: id, colorHex: "#000000", allowsContentModifications: writable)
    }

    private func scope(id: UUID, reminderListIDs: Set<String>) -> ProfileScope {
        .init(
            identity: .saved(id),
            calendarIDs: [],
            reminderListIDs: reminderListIDs,
            routineIDs: [],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )
    }

    private func singaporeCalendar() -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }
}

private extension AgendaItem {
    var reminderID: String? {
        guard case let .reminder(id) = origin else { return nil }
        return id
    }
}
