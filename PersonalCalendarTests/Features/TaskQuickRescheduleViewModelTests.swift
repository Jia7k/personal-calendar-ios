import XCTest
@testable import PersonalCalendar

@MainActor
final class TaskQuickRescheduleViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 777_636_000)

    func testUndatedRemindersPublishOnlyInNeedsScheduling() async {
        let calendar = singaporeCalendar()
        let future = calendar.date(byAdding: .day, value: 1, to: now)!
        let service = FakeRemindersService(access: .granted, reminders: [
            reminder(id: "undated", dueDate: nil, dueHasTime: false),
            reminder(id: "future", dueDate: future),
            reminder(id: "completed-undated", dueDate: nil, dueHasTime: false, isCompleted: true)
        ])
        let subject = makeSubject(service: service, calendar: calendar)

        await subject.load()

        XCTAssertEqual(subject.overdue.map(\.id), [])
        XCTAssertEqual(subject.today.map(\.id), [])
        XCTAssertEqual(subject.needsScheduling.map(\.id), ["undated"])
        XCTAssertEqual(subject.upcoming.map(\.id), ["future"])
        XCTAssertEqual(subject.completed.map(\.id), ["completed-undated"])
    }

    func testNeedsSchedulingIsClearedWhenTheActiveProfileChanges() async {
        let calendar = singaporeCalendar()
        let profileA = UUID()
        let profileB = UUID()
        var activeScope = scope(id: profileA, reminderListIDs: ["school"])
        let service = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "undated", dueDate: nil, listID: "school", dueHasTime: false)]
        )
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { activeScope },
            calendar: calendar,
            now: { self.now }
        )
        await subject.load()
        XCTAssertEqual(subject.needsScheduling.map(\.id), ["undated"])

        activeScope = scope(id: profileB, reminderListIDs: ["work"])
        await subject.quickReschedule(id: "undated", command: .today)

        XCTAssertEqual(subject.needsScheduling.map(\.id), [])
    }

    func testTodayCommandPublishesUndoWhosePreviousScheduleIsNil() async {
        let calendar = singaporeCalendar()
        let item = reminder(id: "undated", dueDate: nil, dueHasTime: false)
        let service = FakeRemindersService(access: .granted, reminders: [item])
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()

        await subject.quickReschedule(id: item.id, command: .today)

        XCTAssertEqual(
            service.reminderUpdateCalls.first?.draft.schedule,
            .replace(.init(date: calendar.date(from: DateComponents(year: 2025, month: 8, day: 23))!, hasTime: false))
        )
        XCTAssertEqual(subject.rescheduleUndo, .init(reminderID: item.id, previousSchedule: nil))
    }

    func testUndoTodayCommandClearsTheScheduleExactlyOnce() async {
        let calendar = singaporeCalendar()
        let item = reminder(id: "undated", dueDate: nil, dueHasTime: false)
        let service = FakeRemindersService(access: .granted, reminders: [item])
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.quickReschedule(id: item.id, command: .today)

        await subject.undoQuickReschedule()

        XCTAssertEqual(service.reminderUpdateCalls.count, 2)
        XCTAssertEqual(service.reminderUpdateCalls[1].draft.schedule, .clear)
        XCTAssertNil(service.reminders.first?.dueDate)
        XCTAssertNil(subject.rescheduleUndo)
        await subject.undoQuickReschedule()
        XCTAssertEqual(service.reminderUpdateCalls.count, 2)
    }

    func testRecurringReadOnlyAndOutOfProfileUndatedRemindersNeverQuickWrite() async {
        let calendar = singaporeCalendar()
        let profileA = UUID()
        let profileB = UUID()
        var activeScope = scope(id: profileA, reminderListIDs: ["school"])
        let recurring = reminder(id: "recurring", dueDate: nil, listID: "school", hasRecurrence: true, dueHasTime: false)
        let readOnly = reminder(id: "read-only", dueDate: nil, listID: "school", allowsModification: false, dueHasTime: false)
        let outOfProfile = reminder(id: "out-of-profile", dueDate: nil, listID: "school", dueHasTime: false)
        let service = FakeRemindersService(access: .granted, reminders: [recurring, readOnly, outOfProfile])
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { activeScope },
            calendar: calendar,
            now: { self.now }
        )
        await subject.load()

        await subject.quickReschedule(id: recurring.id, command: .today)
        await subject.quickReschedule(id: readOnly.id, command: .today)
        activeScope = scope(id: profileB, reminderListIDs: ["work"])
        await subject.quickReschedule(id: outOfProfile.id, command: .today)

        XCTAssertTrue(service.reminderUpdateCalls.isEmpty)
        XCTAssertTrue(service.reminders.allSatisfy { $0.dueDate == nil })
    }

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

    func testQuickRescheduleRejectsLiveReminderMovedOutsideSameProfile() async {
        let calendar = singaporeCalendar()
        let profileID = UUID()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let provider = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "overdue", dueDate: original, listID: "school")],
            descriptors: [descriptor(id: "school"), descriptor(id: "work")]
        )
        let service = RescheduleMutationAttemptRecorder(base: provider)
        let activeScope = scope(id: profileID, reminderListIDs: ["school"])
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { activeScope },
            calendar: calendar,
            now: { self.now }
        )
        await subject.load()
        provider.reminders = [reminder(id: "overdue", dueDate: original, listID: "work")]

        await subject.quickReschedule(id: "overdue", command: .tomorrow)

        XCTAssertTrue(service.updateAttempts.isEmpty)
        XCTAssertEqual(provider.reminders.first?.listID, "work")
        XCTAssertEqual(provider.reminders.first?.dueDate, original)
        XCTAssertNil(subject.rescheduleUndo)
    }

    func testQuickRescheduleRejectsLiveDeletedReminderWithoutProviderWrite() async {
        let calendar = singaporeCalendar()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let provider = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "overdue", dueDate: original)],
            descriptors: [descriptor(id: "list")]
        )
        let service = RescheduleMutationAttemptRecorder(base: provider)
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        provider.reminders = []

        await subject.quickReschedule(id: "overdue", command: .tomorrow)

        XCTAssertTrue(service.updateAttempts.isEmpty)
        XCTAssertEqual(provider.successfulWriteCount, 0)
        XCTAssertNil(subject.rescheduleUndo)
    }

    func testQuickRescheduleRejectsLiveReadOnlyReminderWithoutProviderWrite() async {
        let calendar = singaporeCalendar()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let provider = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "overdue", dueDate: original)],
            descriptors: [descriptor(id: "list")]
        )
        let service = RescheduleMutationAttemptRecorder(base: provider)
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        provider.reminders = [reminder(id: "overdue", dueDate: original, allowsModification: false)]
        provider.descriptors = [descriptor(id: "list", allowsContentModifications: false)]

        await subject.quickReschedule(id: "overdue", command: .tomorrow)

        XCTAssertTrue(service.updateAttempts.isEmpty)
        XCTAssertEqual(provider.successfulWriteCount, 0)
        XCTAssertEqual(provider.reminders.first?.dueDate, original)
        XCTAssertNil(subject.rescheduleUndo)
    }

    func testQuickRescheduleRejectsLiveRecurringReminderWithoutProviderWrite() async {
        let calendar = singaporeCalendar()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let provider = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "overdue", dueDate: original)],
            descriptors: [descriptor(id: "list")]
        )
        let service = RescheduleMutationAttemptRecorder(base: provider)
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        provider.reminders = [reminder(id: "overdue", dueDate: original, hasRecurrence: true)]

        await subject.quickReschedule(id: "overdue", command: .tomorrow)

        XCTAssertTrue(service.updateAttempts.isEmpty)
        XCTAssertEqual(provider.successfulWriteCount, 0)
        XCTAssertEqual(provider.reminders.first?.dueDate, original)
        XCTAssertNil(subject.rescheduleUndo)
    }

    func testQuickReschedulePreservesLiveTitleAndNotesWhenCachedSnapshotIsStale() async {
        let calendar = singaporeCalendar()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let provider = FakeRemindersService(
            access: .granted,
            reminders: [reminder(
                id: "overdue",
                dueDate: original,
                title: "Cached title",
                notes: "Cached notes",
                priority: 1
            )],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: provider, calendar: calendar)
        await subject.load()
        provider.reminders = [reminder(
            id: "overdue",
            dueDate: original,
            title: "Live provider title",
            notes: "Live provider notes",
            priority: 9
        )]

        await subject.quickReschedule(id: "overdue", command: .tomorrow)

        XCTAssertEqual(provider.reminders.first?.title, "Live provider title")
        XCTAssertEqual(provider.reminders.first?.notes, "Live provider notes")
        XCTAssertEqual(provider.reminders.first?.priority, 9)
    }

    func testUndoInvalidatesWhenLiveScheduleChangedAfterQuickReschedule() async {
        let calendar = singaporeCalendar()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let externallyEdited = calendar.date(byAdding: .day, value: 4, to: now)!
        let provider = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "overdue", dueDate: original)],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: provider, calendar: calendar)
        await subject.load()
        await subject.quickReschedule(id: "overdue", command: .tomorrow)
        XCTAssertNotNil(subject.rescheduleUndo)
        provider.reminders = [reminder(id: "overdue", dueDate: externallyEdited)]

        await subject.undoQuickReschedule()

        XCTAssertEqual(provider.reminderUpdateCalls.count, 1)
        XCTAssertEqual(provider.reminders.first?.dueDate, externallyEdited)
        XCTAssertNil(subject.rescheduleUndo)
    }

    func testAuthoritativeLoadClearsUndoForDeletedReminder() async {
        let calendar = singaporeCalendar()
        let original = calendar.date(byAdding: .day, value: -1, to: now)!
        let provider = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "overdue", dueDate: original)],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: provider, calendar: calendar)
        await subject.load()
        await subject.quickReschedule(id: "overdue", command: .tomorrow)
        XCTAssertNotNil(subject.rescheduleUndo)
        provider.reminders = []

        await subject.load()

        XCTAssertNil(subject.rescheduleUndo)
        XCTAssertEqual(provider.reminderUpdateCalls.count, 1)
    }

    func testProviderMinutePrecisionKeepsUndoValidAfterSuccessfulReschedule() async {
        let calendar = singaporeCalendar()
        let nowWithSeconds = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 24, hour: 20, minute: 0, second: 47
        ))!
        let original = calendar.date(byAdding: .day, value: -1, to: nowWithSeconds)!
        let provider = FakeRemindersService(
            access: .granted,
            reminders: [reminder(id: "overdue", dueDate: original)],
            descriptors: [descriptor(id: "list")]
        )
        let service = RescheduleMutationAttemptRecorder(
            base: provider,
            normalizingSavedDueWith: calendar
        )
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            calendar: calendar,
            now: { nowWithSeconds }
        )
        await subject.load()

        await subject.quickReschedule(id: "overdue", command: .laterToday)

        XCTAssertNotNil(subject.rescheduleUndo)
        XCTAssertEqual(
            calendar.component(.second, from: try! XCTUnwrap(provider.reminders.first?.dueDate)),
            0
        )

        await subject.undoQuickReschedule()

        XCTAssertEqual(provider.reminderUpdateCalls.count, 2)
        XCTAssertNil(subject.rescheduleUndo)
    }

    func testCompletionPublishesNamedUndoAndRestoresTheTaskExactlyOnce() async throws {
        let calendar = singaporeCalendar()
        let item = reminder(
            id: "opaque|task",
            dueDate: now,
            title: "Submit lab notes"
        )
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()

        await subject.setCompleted(id: item.id, completed: true)

        XCTAssertEqual(subject.latestTaskUndo?.title, "Submit lab notes")
        XCTAssertEqual(subject.latestTaskUndo?.rawID, "opaque|task")
        XCTAssertEqual(subject.latestTaskUndo?.snapshot, item)
        XCTAssertEqual(subject.completed.map(\.id), ["opaque|task"])

        await subject.undoLastTaskCompletion()

        XCTAssertEqual(
            service.completedCalls,
            [
                .init(id: "opaque|task", completed: true),
                .init(id: "opaque|task", completed: false)
            ]
        )
        XCTAssertEqual(subject.today.map(\.id), ["opaque|task"])
        XCTAssertNil(subject.latestTaskUndo)

        await subject.undoLastTaskCompletion()
        XCTAssertEqual(service.completedCalls.count, 2)
    }

    func testCompletionUndoClearsWithoutWritingAfterProfileIdentityChanges() async {
        let calendar = singaporeCalendar()
        var activeScope = scope(id: UUID(), reminderListIDs: ["school"])
        let item = reminder(id: "task", dueDate: now, listID: "school")
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "school"), descriptor(id: "work")]
        )
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { activeScope },
            calendar: calendar,
            now: { self.now }
        )
        await subject.load()
        await subject.setCompleted(id: item.id, completed: true)
        XCTAssertNotNil(subject.latestTaskUndo)
        let completedCalls = service.completedCalls

        activeScope = scope(id: UUID(), reminderListIDs: ["work"])
        await subject.undoLastTaskCompletion()

        XCTAssertEqual(service.completedCalls, completedCalls)
        XCTAssertNil(subject.latestTaskUndo)
        XCTAssertTrue(subject.today.isEmpty)
        XCTAssertTrue(subject.completed.isEmpty)
    }

    func testCompletionUndoClearsWithoutWritingAfterSameProfileListSelectionChanges() async {
        let calendar = singaporeCalendar()
        let profileID = UUID()
        var activeScope = scope(id: profileID, reminderListIDs: ["school"])
        let item = reminder(id: "task", dueDate: now, listID: "school")
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "school"), descriptor(id: "work")]
        )
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { activeScope },
            calendar: calendar,
            now: { self.now }
        )
        await subject.load()
        await subject.setCompleted(id: item.id, completed: true)
        XCTAssertNotNil(subject.latestTaskUndo)
        let completedCalls = service.completedCalls

        activeScope = scope(id: profileID, reminderListIDs: ["work"])
        await subject.undoLastTaskCompletion()

        XCTAssertEqual(service.completedCalls, completedCalls)
        XCTAssertNil(subject.latestTaskUndo)
        XCTAssertTrue(subject.completed.isEmpty)
    }

    func testCompletionUndoRejectsLiveTaskMovedOutsideProfileWithoutWriting() async {
        let calendar = singaporeCalendar()
        let profileID = UUID()
        let item = reminder(id: "task", dueDate: now, listID: "school")
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "school"), descriptor(id: "work")]
        )
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { self.scope(id: profileID, reminderListIDs: ["school"]) },
            calendar: calendar,
            now: { self.now }
        )
        await subject.load()
        await subject.setCompleted(id: item.id, completed: true)
        XCTAssertNotNil(subject.latestTaskUndo)
        let completedCalls = service.completedCalls
        service.reminders = [reminder(
            id: item.id,
            dueDate: now,
            listID: "work",
            isCompleted: true
        )]

        await subject.undoLastTaskCompletion()

        XCTAssertEqual(service.completedCalls, completedCalls)
        XCTAssertTrue(service.reminders.first?.isCompleted == true)
        XCTAssertNil(subject.latestTaskUndo)
    }

    func testCompletionUndoRejectsDeletedLiveTaskWithoutWriting() async {
        let calendar = singaporeCalendar()
        let item = reminder(id: "task", dueDate: now)
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.setCompleted(id: item.id, completed: true)
        XCTAssertNotNil(subject.latestTaskUndo)
        let completedCalls = service.completedCalls
        service.reminders = []

        await subject.undoLastTaskCompletion()

        XCTAssertEqual(service.completedCalls, completedCalls)
        XCTAssertNil(subject.latestTaskUndo)
    }

    func testAuthoritativeLoadClearsCompletionUndoWhenTaskDisappears() async {
        let calendar = singaporeCalendar()
        let item = reminder(id: "task", dueDate: now)
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.setCompleted(id: item.id, completed: true)
        XCTAssertNotNil(subject.latestTaskUndo)
        let completedCalls = service.completedCalls
        service.reminders = []

        await subject.load()
        await subject.undoLastTaskCompletion()

        XCTAssertEqual(service.completedCalls, completedCalls)
        XCTAssertNil(subject.latestTaskUndo)
    }

    func testCompletionUndoRejectsListThatBecomesReadOnlyWithoutWriting() async {
        let calendar = singaporeCalendar()
        let item = reminder(id: "task", dueDate: now)
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.setCompleted(id: item.id, completed: true)
        XCTAssertNotNil(subject.latestTaskUndo)
        let completedCalls = service.completedCalls
        service.descriptors = [descriptor(
            id: "list",
            allowsContentModifications: false
        )]

        await subject.undoLastTaskCompletion()

        XCTAssertEqual(service.completedCalls, completedCalls)
        XCTAssertTrue(service.reminders.first?.isCompleted == true)
        XCTAssertNil(subject.latestTaskUndo)
    }

    func testFailedCompletionUndoRetryRejectsLiveTaskMovedOutsideProfile() async {
        let calendar = singaporeCalendar()
        let profileID = UUID()
        let item = reminder(id: "task", dueDate: now, listID: "school")
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "school"), descriptor(id: "work")]
        )
        let subject = TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            currentScope: { self.scope(id: profileID, reminderListIDs: ["school"]) },
            calendar: calendar,
            now: { self.now }
        )
        await subject.load()
        await subject.setCompleted(id: item.id, completed: true)
        service.completionError = RescheduleTestError.failed
        await subject.undoLastTaskCompletion()
        XCTAssertEqual(
            subject.failedMutationOperation,
            .init(id: "task", completed: false)
        )
        service.completionError = nil
        service.reminders = [reminder(
            id: item.id,
            dueDate: now,
            listID: "work",
            isCompleted: true
        )]
        let completedCalls = service.completedCalls

        await subject.retryFailedMutation()

        XCTAssertEqual(service.completedCalls, completedCalls)
        XCTAssertTrue(service.reminders.first?.isCompleted == true)
        XCTAssertNil(subject.failedMutationOperation)
        XCTAssertNil(subject.latestTaskUndo)
    }

    func testFailedCompletionUndoRetryKeepsNewerCompletionUndoForAnotherTask() async {
        let calendar = singaporeCalendar()
        let first = reminder(id: "first", dueDate: now, title: "First")
        let second = reminder(id: "second", dueDate: now, title: "Second")
        let service = FakeRemindersService(
            access: .granted,
            reminders: [first, second],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.setCompleted(id: first.id, completed: true)
        service.completionError = RescheduleTestError.failed
        await subject.undoLastTaskCompletion()
        service.completionError = nil
        await subject.setCompleted(id: second.id, completed: true)
        XCTAssertEqual(subject.latestTaskUndo?.rawID, "second")
        XCTAssertEqual(
            subject.failedMutationOperation,
            .init(id: "first", completed: false)
        )

        await subject.retryFailedMutation()

        XCTAssertEqual(
            service.completedCalls,
            [
                .init(id: "first", completed: true),
                .init(id: "second", completed: true),
                .init(id: "first", completed: false)
            ]
        )
        XCTAssertFalse(service.reminders.first { $0.id == "first" }!.isCompleted)
        XCTAssertTrue(service.reminders.first { $0.id == "second" }!.isCompleted)
        XCTAssertNil(subject.failedMutationOperation)
        XCTAssertEqual(subject.latestTaskUndo?.rawID, "second")
    }

    func testCompletionUndoStaysPendingAndDoesNotWriteTwice() async {
        let calendar = singaporeCalendar()
        let item = reminder(id: "task", dueDate: now, title: "Task")
        let service = FakeRemindersService(
            access: .granted,
            reminders: [item],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.setCompleted(id: item.id, completed: true)
        service.suspendFetchAfterUndo = true

        let undo = Task { await subject.undoLastTaskCompletion() }
        for _ in 0..<30 where !service.isFetchSuspended { await Task.yield() }

        XCTAssertTrue(service.isFetchSuspended)
        XCTAssertTrue(subject.latestTaskUndo?.isPending == true)
        await subject.undoLastTaskCompletion()
        XCTAssertEqual(service.completedCalls.filter { !$0.completed }.count, 1)

        service.resumeSuspendedFetch()
        await undo.value
        XCTAssertNil(subject.latestTaskUndo)
    }

    func testNewestCompletionReplacesOlderCompletionUndoWithoutDiscardingRescheduleUndo() async {
        let calendar = singaporeCalendar()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let first = reminder(id: "first", dueDate: now, title: "First")
        let second = reminder(id: "second", dueDate: now, title: "Second")
        let rescheduled = reminder(id: "rescheduled", dueDate: yesterday)
        let service = FakeRemindersService(
            access: .granted,
            reminders: [first, second, rescheduled],
            descriptors: [descriptor(id: "list")]
        )
        let subject = makeSubject(service: service, calendar: calendar)
        await subject.load()
        await subject.quickReschedule(id: rescheduled.id, command: .tomorrow)
        let expectedRescheduleUndo = subject.rescheduleUndo

        await subject.setCompleted(id: first.id, completed: true)
        XCTAssertEqual(subject.latestTaskUndo?.rawID, "first")
        await subject.setCompleted(id: second.id, completed: true)

        XCTAssertEqual(subject.latestTaskUndo?.rawID, "second")
        XCTAssertEqual(subject.latestTaskUndo?.title, "Second")
        XCTAssertEqual(subject.rescheduleUndo, expectedRescheduleUndo)
    }

    private func makeSubject(service: any RemindersServicing, calendar: Calendar) -> TasksViewModel {
        TasksViewModel(
            service: service,
            settings: AppSettingsStore(defaults: .ephemeral),
            calendar: calendar,
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

    private func descriptor(
        id: String,
        allowsContentModifications: Bool = true
    ) -> ReminderListDescriptor {
        .init(
            id: id,
            title: id,
            colorHex: "#000000",
            allowsContentModifications: allowsContentModifications
        )
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

@MainActor
private final class RescheduleMutationAttemptRecorder: RemindersServicing {
    let base: FakeRemindersService
    private(set) var updateAttempts: [ReminderUpdateCall] = []
    private let normalizingCalendar: Calendar?

    init(base: FakeRemindersService, normalizingSavedDueWith calendar: Calendar? = nil) {
        self.base = base
        normalizingCalendar = calendar
    }

    var accessState: AccessState { base.accessState }

    func requestFullAccess() async -> AccessState {
        await base.requestFullAccess()
    }

    func lists() -> [ReminderListDescriptor] {
        base.lists()
    }

    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        try await base.fetchReminders(listIDs: listIDs)
    }

    func createReminder(_ draft: ReminderDraft) throws -> String? {
        try base.createReminder(draft)
    }

    func setCompleted(id: String, completed: Bool) throws {
        try base.setCompleted(id: id, completed: completed)
    }

    func reminder(id: String) -> ReminderSnapshot? {
        base.reminder(id: id)
    }

    func updateReminder(id: String, draft: ReminderDraft) throws {
        updateAttempts.append(.init(id: id, draft: draft))
        try base.updateReminder(id: id, draft: draft)
        guard let normalizingCalendar,
              let index = base.reminders.firstIndex(where: { $0.id == id }),
              let savedDue = base.reminders[index].dueDate else { return }
        let old = base.reminders[index]
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        let components = normalizingCalendar.dateComponents(fields, from: savedDue)
        let normalizedDue = normalizingCalendar.date(from: components)!
        base.reminders[index] = ReminderSnapshot(
            id: old.id,
            title: old.title,
            notes: old.notes,
            dueDate: normalizedDue,
            dueHasTime: old.dueHasTime,
            priority: old.priority,
            listID: old.listID,
            listTitle: old.listTitle,
            isCompleted: old.isCompleted,
            allowsModification: old.allowsModification,
            hasRecurrence: old.hasRecurrence,
            alarm: old.alarm,
            recurrence: old.recurrence
        )
    }

    func deleteReminder(id: String) throws {
        try base.deleteReminder(id: id)
    }
}
