import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class QuickEntryViewModelTests: XCTestCase {
    func testDestinationOptionsExposeEveryWritableSourceSortedRegardlessOfVisibility() {
        let calendars = [
            calendarDescriptor("z", "Zulu"),
            calendarDescriptor("a", "Alpha"),
            calendarDescriptor("r", "Read Only", writable: false)
        ]
        let lists = [
            listDescriptor("z-list", "Zulu"),
            listDescriptor("a-list", "Alpha"),
            listDescriptor("r-list", "Read Only", writable: false)
        ]
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.replaceSelectedCalendarIDs(["z"], availableIDs: Set(calendars.map(\.id)))
        settings.replaceSelectedReminderListIDs(["z-list"], availableIDs: Set(lists.map(\.id)))
        let calendar = FakeCalendarService(access: .granted, descriptors: calendars, defaultCalendarID: "a")
        let reminders = FakeRemindersService(access: .granted, descriptors: lists, defaultListID: "a-list")

        let options = QuickEntryDestinationOptions.resolve(calendar: calendar, reminders: reminders, settings: settings)

        XCTAssertEqual(options.calendars.map(\.id), ["a", "z"])
        XCTAssertEqual(options.reminderLists.map(\.id), ["a-list", "z-list"])
        XCTAssertEqual(options.visibleCalendarIDs, ["z"])
        XCTAssertEqual(options.visibleReminderListIDs, ["z-list"])
    }

    func testDestinationOptionsSeedOnlyCurrentlyWritableSavedDefaults() {
        let calendars = [calendarDescriptor("work", "Work"), calendarDescriptor("readonly", "Read Only", writable: false)]
        let lists = [listDescriptor("tasks", "Tasks"), listDescriptor("readonly-list", "Read Only", writable: false)]
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.setDefaultCalendarID("work", descriptors: calendars, access: .granted)
        settings.setDefaultReminderListID("readonly-list", descriptors: lists, access: .granted)

        let options = QuickEntryDestinationOptions.resolve(
            calendar: FakeCalendarService(access: .granted, descriptors: calendars, defaultCalendarID: "work"),
            reminders: FakeRemindersService(access: .granted, descriptors: lists, defaultListID: "tasks"),
            settings: settings
        )

        XCTAssertEqual(options.defaultCalendarID, "work")
        XCTAssertNil(options.defaultReminderListID)
    }

    func testDestinationOptionsBecomeUnavailableWithoutAccess() {
        let calendars = [calendarDescriptor("work", "Work")]
        let lists = [listDescriptor("tasks", "Tasks")]
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.setDefaultCalendarID("work", descriptors: calendars, access: .granted)
        settings.setDefaultReminderListID("tasks", descriptors: lists, access: .granted)

        let options = QuickEntryDestinationOptions.resolve(
            calendar: FakeCalendarService(access: .denied, descriptors: calendars, defaultCalendarID: "work"),
            reminders: FakeRemindersService(access: .restricted, descriptors: lists, defaultListID: "tasks"),
            settings: settings
        )

        XCTAssertEqual(options.calendarAccess, .denied)
        XCTAssertEqual(options.remindersAccess, .restricted)
        XCTAssertTrue(options.calendars.isEmpty)
        XCTAssertTrue(options.reminderLists.isEmpty)
        XCTAssertNil(options.defaultCalendarID)
        XCTAssertNil(options.defaultReminderListID)
    }

    func testTitleOnlyTaskUsesFirstWritableProfileListWhenNoDefaultIsConfigured() {
        let profileID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let creationProfile = creationProfile(
            id: profileID,
            calendarIDs: [],
            reminderListIDs: ["alpha", "locked", "zulu"],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )
        let resolvedOptions = QuickEntryDestinationOptions.resolve(
            calendar: FakeCalendarService(access: .granted, descriptors: []),
            reminders: FakeRemindersService(
                access: .granted,
                descriptors: [
                    listDescriptor("outside", "Aardvark"),
                    listDescriptor("zulu", "Zulu"),
                    listDescriptor("alpha", "Alpha"),
                    listDescriptor("locked", "Locked", writable: false)
                ]
            ),
            context: creationProfile
        )
        let saver = RecordingQuickEntrySaver(steps: [.success(.task(id: "saved-task"))])
        let subject = makeSubject(
            result: .success(taskPreview(due: nil, dueHasTime: false)),
            saver: saver,
            options: resolvedOptions,
            creationProfile: creationProfile
        )
        subject.text = "Call Alex"

        subject.parse()

        XCTAssertEqual(resolvedOptions.defaultReminderListID, "alpha")
        XCTAssertEqual(subject.preview?.destinationID, "alpha")
        XCTAssertNil(subject.preview?.dueDate)
        XCTAssertFalse(subject.preview?.dueHasTime ?? true)
        XCTAssertNil(subject.preview?.reminderDate)
        XCTAssertNil(subject.preview?.recurrence)
        XCTAssertTrue(subject.canSave)

        subject.confirmSave()

        XCTAssertEqual(subject.phase, .committed(.task(id: "saved-task")))
        XCTAssertEqual(saver.received.count, 1)
        XCTAssertEqual(saver.received.first?.title, "Submit report")
        XCTAssertEqual(saver.received.first?.destinationID, "alpha")
        XCTAssertNil(saver.received.first?.dueDate)
        XCTAssertFalse(saver.received.first?.dueHasTime ?? true)
        XCTAssertNil(saver.received.first?.reminderDate)
        XCTAssertNil(saver.received.first?.recurrence)
    }

    func testTaskFallbackStaysBlockedWhenNoWritableListBelongsToTheProfile() {
        let creationProfile = creationProfile(
            id: UUID(uuidString: "66666666-7777-4888-8999-AAAAAAAAAAAA")!,
            calendarIDs: [],
            reminderListIDs: ["locked"],
            defaultCalendarID: nil,
            defaultReminderListID: nil
        )
        let resolvedOptions = QuickEntryDestinationOptions.resolve(
            calendar: FakeCalendarService(access: .granted, descriptors: []),
            reminders: FakeRemindersService(
                access: .granted,
                descriptors: [
                    listDescriptor("outside", "Outside"),
                    listDescriptor("locked", "Locked", writable: false)
                ]
            ),
            context: creationProfile
        )
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(
            result: .success(taskPreview(due: nil, dueHasTime: false)),
            saver: saver,
            options: resolvedOptions,
            creationProfile: creationProfile
        )
        subject.text = "Call Alex"

        subject.parse()

        XCTAssertNil(resolvedOptions.defaultReminderListID)
        XCTAssertNil(subject.preview?.destinationID)
        XCTAssertFalse(subject.canSave)

        subject.confirmSave()

        XCTAssertEqual(subject.phase, .confirmation(.failed(.explicitDestinationRequired)))
        XCTAssertTrue(saver.received.isEmpty)
    }

    func testConfiguredProfileTaskDefaultWinsOverEarlierSortedWritableMember() {
        let creationProfile = creationProfile(
            id: UUID(uuidString: "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF")!,
            calendarIDs: [],
            reminderListIDs: ["alpha", "zulu"],
            defaultCalendarID: nil,
            defaultReminderListID: "zulu"
        )

        let resolvedOptions = QuickEntryDestinationOptions.resolve(
            calendar: FakeCalendarService(access: .granted, descriptors: []),
            reminders: FakeRemindersService(
                access: .granted,
                descriptors: [
                    listDescriptor("alpha", "Alpha"),
                    listDescriptor("zulu", "Zulu")
                ]
            ),
            context: creationProfile
        )

        XCTAssertEqual(resolvedOptions.defaultReminderListID, "zulu")
    }

    func testParseMovesToConfirmationSeedsEventDefaultAndNeverSaves() {
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(result: .success(eventPreview()), saver: saver, options: options(defaultCalendarID: "work"))
        subject.text = "Dentist Friday at 3pm"

        subject.parse()

        XCTAssertEqual(subject.phase, .confirmation(.ready))
        XCTAssertEqual(subject.preview?.destinationID, "work")
        XCTAssertTrue(saver.received.isEmpty)
    }

    func testShortcutCaptureRemainsMarkedThroughReviewWithoutSaving() {
        let saver = RecordingQuickEntrySaver()
        let subject = QuickEntryViewModel(
            parser: StubQuickEntryParser(result: .success(eventPreview())),
            saver: saver,
            context: context(),
            destinations: options(defaultCalendarID: "work"),
            captureSource: .shortcut
        )
        subject.text = "Dentist Friday at 3pm"

        subject.parse()

        XCTAssertEqual(subject.captureSource, .shortcut)
        XCTAssertEqual(subject.phase, .confirmation(.ready))
        XCTAssertTrue(saver.received.isEmpty)
        XCTAssertEqual(
            makeSubject(result: .success(eventPreview())).captureSource,
            .inApp
        )
    }

    func testParseSeedsTaskDefaultButNeverAssignsDestinationToRoutine() {
        let task = makeSubject(result: .success(taskPreview()), options: options(defaultListID: "tasks"))
        task.text = "Submit report tomorrow"
        task.parse()
        XCTAssertEqual(task.preview?.destinationID, "tasks")

        let routine = makeSubject(result: .success(routinePreview()), options: options(defaultCalendarID: "work", defaultListID: "tasks"))
        routine.text = "Read every night"
        routine.parse()
        XCTAssertNil(routine.preview?.destinationID)
    }

    func testParsePreservesAParserSuppliedDestination() {
        var parsed = eventPreview()
        parsed.destinationID = "parser-calendar"
        let subject = makeSubject(result: .success(parsed), options: options(defaultCalendarID: "work"))
        subject.text = "Dentist Friday"

        subject.parse()

        XCTAssertEqual(subject.preview?.destinationID, "parser-calendar")
    }

    func testReviewingUnchangedInputPreservesExactEditedPreview() {
        let parser = LockedSequenceParser([
            .success(eventPreview()),
            .failure(.ambiguousExpression)
        ])
        let subject = QuickEntryViewModel(
            parser: parser,
            saver: RecordingQuickEntrySaver(),
            context: context(),
            destinations: options(defaultCalendarID: "work")
        )
        let categoryID = UUID(uuidString: "01234567-89AB-4CDE-8F01-23456789ABCD")!
        let edited = QuickEntryPreview(
            kind: .event,
            title: "Edited dentist appointment",
            startDate: date(2026, 8, 26, 14),
            endDate: date(2026, 8, 26, 15, 30),
            reminderDate: date(2026, 8, 26, 13, 45),
            destinationID: "home",
            categoryID: categoryID
        )
        subject.text = "Dentist Friday at 3pm"
        subject.parse()
        subject.preview = edited
        subject.returnToEntry()

        subject.parse()

        XCTAssertEqual(subject.phase, .confirmation(.ready))
        XCTAssertEqual(subject.preview, edited)
    }

    func testReviewingUnchangedInputPreservesSelectedKindAndDestinationNamespaces() {
        let parser = LockedSequenceParser([
            .success(eventPreview()),
            .failure(.ambiguousExpression)
        ])
        let subject = QuickEntryViewModel(
            parser: parser,
            saver: RecordingQuickEntrySaver(),
            context: context(),
            destinations: options(defaultCalendarID: "work", defaultListID: "tasks")
        )
        subject.text = "Plan tomorrow"
        subject.parse()
        subject.selectDestination("home")
        subject.selectKind(.task)
        subject.selectDestination("personal-tasks")
        let editedTask = subject.preview
        subject.returnToEntry()

        subject.parse()

        XCTAssertEqual(subject.preview, editedTask)
        XCTAssertEqual(subject.preview?.kind, .task)
        XCTAssertEqual(subject.preview?.destinationID, "personal-tasks")

        subject.selectKind(.event)
        XCTAssertEqual(subject.preview?.destinationID, "home")
    }

    func testReviewingUnchangedEventPreservesExplicitSystemDefaultSelectionAcrossRefresh() {
        let parser = LockedSequenceParser([
            .success(eventPreview()),
            .success(eventPreview())
        ])
        let subject = QuickEntryViewModel(
            parser: parser,
            saver: RecordingQuickEntrySaver(),
            context: context(),
            destinations: options(calendarAccess: .denied, calendars: [])
        )
        subject.text = "Dentist"
        subject.parse()
        subject.selectDestination(nil)
        subject.returnToEntry()
        subject.parse()

        subject.updateDestinationOptions(
            options(
                calendarAccess: .granted,
                calendars: [calendarDescriptor("work", "Work")],
                defaultCalendarID: "work"
            )
        )

        XCTAssertNil(subject.preview?.destinationID)
    }

    func testReviewingUnchangedTaskPreservesExplicitSystemDefaultSelectionAcrossRefresh() {
        let parser = LockedSequenceParser([
            .success(taskPreview()),
            .success(taskPreview())
        ])
        let subject = QuickEntryViewModel(
            parser: parser,
            saver: RecordingQuickEntrySaver(),
            context: context(),
            destinations: options(remindersAccess: .notDetermined, reminderLists: [])
        )
        subject.text = "Submit"
        subject.parse()
        subject.selectDestination(nil)
        subject.returnToEntry()
        subject.parse()

        subject.updateDestinationOptions(
            options(
                remindersAccess: .granted,
                reminderLists: [listDescriptor("tasks", "Tasks")],
                defaultListID: "tasks"
            )
        )

        XCTAssertNil(subject.preview?.destinationID)
    }

    func testUnchangedEventReviewReconcilesUntouchedDestinationRefreshedWhileBackInEntry() {
        let subject = makeSubject(
            result: .success(eventPreview()),
            options: options(calendarAccess: .denied, calendars: [])
        )
        subject.text = "Dentist"
        subject.parse()
        subject.preview?.title = "Corrected dentist"
        subject.returnToEntry()

        subject.updateDestinationOptions(
            options(
                calendarAccess: .granted,
                calendars: [calendarDescriptor("work", "Work")],
                defaultCalendarID: "work"
            )
        )
        subject.parse()

        XCTAssertEqual(subject.preview?.title, "Corrected dentist")
        XCTAssertEqual(subject.preview?.destinationID, "work")
        XCTAssertTrue(subject.canSave)
    }

    func testUnchangedTaskReviewReconcilesUntouchedDestinationRefreshedWhileBackInEntry() {
        let subject = makeSubject(
            result: .success(taskPreview()),
            options: options(remindersAccess: .notDetermined, reminderLists: [])
        )
        subject.text = "Submit"
        subject.parse()
        subject.preview?.title = "Corrected submission"
        subject.returnToEntry()

        subject.updateDestinationOptions(
            options(
                remindersAccess: .granted,
                reminderLists: [listDescriptor("tasks", "Tasks")],
                defaultListID: "tasks"
            )
        )
        subject.parse()

        XCTAssertEqual(subject.preview?.title, "Corrected submission")
        XCTAssertEqual(subject.preview?.destinationID, "tasks")
        XCTAssertTrue(subject.canSave)
    }

    func testUnchangedEventReviewKeepsExplicitSystemDefaultWhenRefreshedWhileBackInEntry() {
        let subject = makeSubject(
            result: .success(eventPreview()),
            options: options(calendarAccess: .denied, calendars: [])
        )
        subject.text = "Dentist"
        subject.parse()
        subject.preview?.title = "Corrected dentist"
        subject.selectDestination(nil)
        subject.returnToEntry()

        subject.updateDestinationOptions(
            options(
                calendarAccess: .granted,
                calendars: [calendarDescriptor("work", "Work")],
                defaultCalendarID: "work"
            )
        )
        subject.parse()

        XCTAssertEqual(subject.preview?.title, "Corrected dentist")
        XCTAssertNil(subject.preview?.destinationID)
        XCTAssertTrue(subject.canSave)
    }

    func testUnchangedTaskReviewKeepsExplicitSystemDefaultWhenRefreshedWhileBackInEntry() {
        let subject = makeSubject(
            result: .success(taskPreview()),
            options: options(remindersAccess: .notDetermined, reminderLists: [])
        )
        subject.text = "Submit"
        subject.parse()
        subject.preview?.title = "Corrected submission"
        subject.selectDestination(nil)
        subject.returnToEntry()

        subject.updateDestinationOptions(
            options(
                remindersAccess: .granted,
                reminderLists: [listDescriptor("tasks", "Tasks")],
                defaultListID: "tasks"
            )
        )
        subject.parse()

        XCTAssertEqual(subject.preview?.title, "Corrected submission")
        XCTAssertNil(subject.preview?.destinationID)
        XCTAssertTrue(subject.canSave)
    }

    func testReviewingTextWithAnyChangeParsesAFresh() {
        let parser = LockedSequenceParser([
            .success(eventPreview()),
            .success(taskPreview(due: nil, dueHasTime: false))
        ])
        let subject = QuickEntryViewModel(
            parser: parser,
            saver: RecordingQuickEntrySaver(),
            context: context(),
            destinations: options(defaultListID: "tasks")
        )
        subject.text = "Plan"
        subject.parse()
        subject.preview?.title = "Edited stale title"
        subject.returnToEntry()
        subject.text = "Plan "

        subject.parse()

        XCTAssertEqual(subject.phase, .confirmation(.ready))
        XCTAssertEqual(subject.preview?.kind, .task)
        XCTAssertEqual(subject.preview?.title, "Submit report")
        XCTAssertEqual(subject.preview?.destinationID, "tasks")
    }

    func testEveryTypedParseFailureRetainsInputClearsStalePreviewAndStaysEntry() {
        let errors: [QuickEntryParseError] = [.emptyInput, .noUsableTitle, .invalidClock, .invalidDate, .nonexistentLocalTime, .ambiguousExpression]
        for error in errors {
            let parser = LockedSequenceParser([.success(taskPreview()), .failure(error)])
            let subject = QuickEntryViewModel(parser: parser, saver: RecordingQuickEntrySaver(), context: context(), destinations: options())
            subject.text = "First"
            subject.parse()
            XCTAssertNotNil(subject.preview)
            subject.returnToEntry()
            subject.text = "Still here"

            subject.parse()

            XCTAssertEqual(subject.phase, .entry(parseError: error), "Unexpected phase for \(error)")
            XCTAssertNil(subject.preview)
            XCTAssertEqual(subject.text, "Still here")
        }
    }

    func testConfirmOutsideConfirmationIsANoOp() {
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(result: .success(taskPreview()), saver: saver)

        subject.confirmSave()

        XCTAssertEqual(subject.phase, .entry(parseError: nil))
        XCTAssertTrue(saver.received.isEmpty)
    }

    func testSavingPhaseIsPublishedBeforeProviderCall() {
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(result: .success(taskPreview()), saver: saver)
        subject.text = "Submit"
        subject.parse()
        saver.onSave = { XCTAssertEqual(subject.phase, .saving(.task)) }

        subject.confirmSave()

        XCTAssertEqual(subject.phase, .committed(.task(id: "saved-task")))
    }

    func testRepeatedConfirmationAndPostCommitActionsWriteExactlyOnce() {
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(result: .success(taskPreview()), saver: saver)
        subject.text = "Submit"
        subject.parse()

        subject.confirmSave()
        subject.confirmSave()
        subject.parse()
        subject.returnToEntry()

        XCTAssertEqual(saver.received.count, 1)
        XCTAssertEqual(subject.phase, .committed(.task(id: "saved-task")))
    }

    func testFailedSaveKeepsExactEditedPreviewAndInputForRetry() {
        let saver = RecordingQuickEntrySaver(steps: [.failure, .success(.task(id: "saved-task"))])
        let subject = makeSubject(result: .success(taskPreview()), saver: saver)
        subject.text = "Submit report tomorrow"
        subject.parse()
        subject.preview?.title = "Submit revised report"

        subject.confirmSave()

        XCTAssertEqual(subject.phase, .confirmation(.failed(.writeFailed)))
        XCTAssertEqual(subject.preview?.title, "Submit revised report")
        XCTAssertEqual(subject.text, "Submit report tomorrow")
        XCTAssertEqual(saver.received.map(\.title), ["Submit revised report"])
    }

    func testRetryUsesLatestEditedPreviewAndCommitsExactlyOnce() {
        let saver = RecordingQuickEntrySaver(steps: [.failure, .success(.task(id: nil))])
        var commits: [QuickEntrySaveOutcome] = []
        let subject = makeSubject(result: .success(taskPreview()), saver: saver, onCommitted: { commits.append($0) })
        subject.text = "Submit"
        subject.parse()
        subject.confirmSave()
        subject.preview?.title = "Latest title"

        subject.confirmSave()
        subject.confirmSave()

        XCTAssertEqual(saver.received.map(\.title), ["Submit report", "Latest title"])
        XCTAssertEqual(subject.phase, .committed(.task(id: nil)))
        XCTAssertEqual(commits, [.task(id: nil)])
    }

    func testKnownRoutingFailuresMapToExactConfirmationFailures() {
        let cases: [(QuickEntrySaveError, QuickEntryFailure)] = [
            (.invalidTitle, .validation), (.invalidEventSchedule, .validation), (.invalidTaskSchedule, .validation),
            (.invalidRoutineSchedule, .validation), (.invalidRecurrence, .validation), (.unsupportedCategory, .validation),
            (.accessUnavailable, .accessUnavailable), (.systemDefaultUnavailable, .systemDefaultUnavailable),
            (.destinationMissing, .invalidDestination), (.destinationReadOnly, .invalidDestination)
        ]
        for (error, expected) in cases {
            let saver = RecordingQuickEntrySaver(error: error)
            let subject = makeSubject(result: .success(taskPreview()), saver: saver)
            subject.text = "Submit"
            subject.parse()
            subject.confirmSave()
            XCTAssertEqual(subject.phase, .confirmation(.failed(expected)), "Unexpected mapping for \(error)")
        }
    }

    func testEventPastWarningRecomputesAfterScheduleEdit() {
        let subject = makeSubject(result: .success(eventPreview(start: date(2026, 8, 24, 6), end: date(2026, 8, 24, 7))))
        subject.text = "Breakfast at 6"
        subject.parse()
        XCTAssertNotNil(subject.warningMessage)

        subject.preview?.startDate = date(2026, 8, 24, 9)
        subject.preview?.endDate = date(2026, 8, 24, 10)

        XCTAssertNil(subject.warningMessage)
    }

    func testTaskPastWarningUsesLocalDayAndRecomputesAfterEdit() {
        let subject = makeSubject(result: .success(taskPreview(due: date(2026, 8, 23), dueHasTime: false)))
        subject.text = "Submit yesterday"
        subject.parse()
        XCTAssertNotNil(subject.warningMessage)

        subject.preview?.dueDate = date(2026, 8, 24)

        XCTAssertNil(subject.warningMessage)
    }

    func testHiddenExplicitDestinationProducesNonblockingHint() {
        let subject = makeSubject(result: .success(eventPreview()), options: options(visibleCalendarIDs: ["home"]))
        subject.text = "Dentist"
        subject.parse()
        subject.preview?.destinationID = "work"

        XCTAssertTrue(subject.canSave)
        XCTAssertNotNil(subject.destinationVisibilityHint)
    }

    func testAccessLossAfterConfirmationPreventsSaverCallAndCanRecover() {
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(result: .success(eventPreview()), saver: saver, options: options())
        subject.text = "Dentist"
        subject.parse()
        subject.updateDestinationOptions(options(calendarAccess: .denied))

        subject.confirmSave()

        XCTAssertEqual(subject.phase, .confirmation(.failed(.accessUnavailable)))
        XCTAssertTrue(saver.received.isEmpty)

        subject.updateDestinationOptions(options())
        subject.confirmSave()
        XCTAssertEqual(saver.received.count, 1)
    }

    func testEventAuthorityRefreshSeedsNewWritableDefaultWhenDestinationWasUntouched() {
        let saver = RecordingQuickEntrySaver(steps: [.success(.event(id: "saved-event"))])
        let subject = makeSubject(
            result: .success(eventPreview()),
            saver: saver,
            options: options(
                calendarAccess: .denied,
                calendars: [],
                defaultCalendarID: nil
            )
        )
        subject.text = "Dentist"
        subject.parse()
        XCTAssertNil(subject.preview?.destinationID)

        subject.updateDestinationOptions(
            options(
                calendarAccess: .granted,
                calendars: [calendarDescriptor("work", "Work")],
                defaultCalendarID: "work"
            )
        )

        XCTAssertEqual(subject.preview?.destinationID, "work")
        XCTAssertTrue(subject.canSave)
        subject.confirmSave()
        XCTAssertEqual(saver.received.count, 1)
        XCTAssertEqual(saver.received.first?.destinationID, "work")
    }

    func testTaskAuthorityRefreshSeedsNewWritableDefaultWhenDestinationWasUntouched() {
        let saver = RecordingQuickEntrySaver(steps: [.success(.task(id: "saved-task"))])
        let subject = makeSubject(
            result: .success(taskPreview()),
            saver: saver,
            options: options(
                remindersAccess: .notDetermined,
                reminderLists: [],
                defaultListID: nil
            )
        )
        subject.text = "Submit"
        subject.parse()
        XCTAssertNil(subject.preview?.destinationID)

        subject.updateDestinationOptions(
            options(
                remindersAccess: .granted,
                reminderLists: [listDescriptor("tasks", "Tasks")],
                defaultListID: "tasks"
            )
        )

        XCTAssertEqual(subject.preview?.destinationID, "tasks")
        XCTAssertTrue(subject.canSave)
        subject.confirmSave()
        XCTAssertEqual(saver.received.count, 1)
        XCTAssertEqual(saver.received.first?.destinationID, "tasks")
    }

    func testEventAuthorityRefreshPreservesExplicitSystemDefaultSelection() {
        let saver = RecordingQuickEntrySaver(steps: [.success(.event(id: nil))])
        let subject = makeSubject(
            result: .success(eventPreview()),
            saver: saver,
            options: options(
                calendarAccess: .denied,
                calendars: [],
                defaultCalendarID: nil
            )
        )
        subject.text = "Dentist"
        subject.parse()
        subject.selectDestination(nil)

        subject.updateDestinationOptions(
            options(
                calendarAccess: .granted,
                calendars: [calendarDescriptor("work", "Work")],
                defaultCalendarID: "work"
            )
        )

        XCTAssertNil(subject.preview?.destinationID)
        XCTAssertTrue(subject.canSave)
        subject.confirmSave()
        XCTAssertEqual(saver.received.count, 1)
        XCTAssertNil(saver.received[0].destinationID)
    }

    func testTaskAuthorityRefreshPreservesExplicitSystemDefaultSelection() {
        let saver = RecordingQuickEntrySaver(steps: [.success(.task(id: nil))])
        let subject = makeSubject(
            result: .success(taskPreview()),
            saver: saver,
            options: options(
                remindersAccess: .notDetermined,
                reminderLists: [],
                defaultListID: nil
            )
        )
        subject.text = "Submit"
        subject.parse()
        subject.selectDestination(nil)

        subject.updateDestinationOptions(
            options(
                remindersAccess: .granted,
                reminderLists: [listDescriptor("tasks", "Tasks")],
                defaultListID: "tasks"
            )
        )

        XCTAssertNil(subject.preview?.destinationID)
        XCTAssertTrue(subject.canSave)
        subject.confirmSave()
        XCTAssertEqual(saver.received.count, 1)
        XCTAssertNil(saver.received[0].destinationID)
    }

    func testDeniedEventAuthorityRefreshImmediatelyUnblocksOneConfirm() {
        let saver = RecordingQuickEntrySaver(steps: [.success(.event(id: "saved-event"))])
        let subject = makeSubject(
            result: .success(eventPreview()),
            saver: saver,
            options: options(calendarAccess: .denied, calendars: [])
        )
        subject.text = "Dentist"
        subject.parse()
        XCTAssertFalse(subject.canSave)

        subject.updateDestinationOptions(
            options(
                calendarAccess: .granted,
                calendars: [calendarDescriptor("work", "Work")]
            )
        )

        XCTAssertTrue(subject.canSave)
        subject.confirmSave()
        XCTAssertEqual(saver.received.count, 1)
    }

    func testNotDeterminedTaskAuthorityRefreshImmediatelyUnblocksOneConfirm() {
        let saver = RecordingQuickEntrySaver(steps: [.success(.task(id: "saved-task"))])
        let subject = makeSubject(
            result: .success(taskPreview()),
            saver: saver,
            options: options(remindersAccess: .notDetermined, reminderLists: [])
        )
        subject.text = "Submit"
        subject.parse()
        XCTAssertFalse(subject.canSave)

        subject.updateDestinationOptions(
            options(
                remindersAccess: .granted,
                reminderLists: [listDescriptor("tasks", "Tasks")]
            )
        )

        XCTAssertTrue(subject.canSave)
        subject.confirmSave()
        XCTAssertEqual(saver.received.count, 1)
    }

    func testSourceActionDistinguishesAllowSettingsAndRestrictedExplanation() {
        let notDetermined = makeSubject(result: .success(eventPreview()), options: options(calendarAccess: .notDetermined))
        notDetermined.text = "Dentist"
        notDetermined.parse()
        XCTAssertEqual(notDetermined.sourceAction, .requestAccess)

        let denied = makeSubject(result: .success(taskPreview()), options: options(remindersAccess: .denied))
        denied.text = "Submit"
        denied.parse()
        XCTAssertEqual(denied.sourceAction, .openSettings)

        let restricted = makeSubject(result: .success(eventPreview()), options: options(calendarAccess: .restricted))
        restricted.text = "Dentist"
        restricted.parse()
        XCTAssertEqual(restricted.sourceAction, .none)
        XCTAssertNotNil(restricted.sourceExplanation)
    }

    func testUserFacingParseAccessAndWriteErrorsUseActionSpecificCopy() {
        let parseFailure = makeSubject(result: .failure(.invalidClock))
        parseFailure.text = "Call at 25:00"
        parseFailure.parse()
        XCTAssertEqual(parseFailure.errorMessage, "Enter a valid time.")

        let denied = makeSubject(
            result: .success(eventPreview()),
            options: options(calendarAccess: .denied)
        )
        denied.text = "Dentist"
        denied.parse()
        XCTAssertEqual(
            denied.sourceExplanation,
            "Calendar access is unavailable. Choose Task or Routine, or enable Calendar access in Settings."
        )

        let saver = RecordingQuickEntrySaver(steps: [.failure])
        let failed = makeSubject(result: .success(eventPreview()), saver: saver)
        failed.text = "Dentist"
        failed.parse()
        failed.confirmSave()
        XCTAssertEqual(failed.errorMessage, "Your event was not saved. Edit it and try again.")
    }

    func testExplicitDestinationThatDisappearsRemainsSelectedAndCannotWrite() {
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(result: .success(eventPreview()), saver: saver, options: options())
        subject.text = "Dentist"
        subject.parse()
        subject.preview?.destinationID = "work"
        subject.updateDestinationOptions(options(calendars: [calendarDescriptor("home", "Home")]))

        subject.confirmSave()

        XCTAssertEqual(subject.preview?.destinationID, "work")
        XCTAssertEqual(subject.phase, .confirmation(.failed(.invalidDestination)))
        XCTAssertTrue(saver.received.isEmpty)
    }

    func testNonnilCategoryIsForwardedToTheSaver() {
        let saver = RecordingQuickEntrySaver()
        var parsed = taskPreview()
        let categoryID = UUID()
        parsed.categoryID = categoryID
        let subject = makeSubject(result: .success(parsed), saver: saver)
        subject.text = "Submit"
        subject.parse()

        subject.confirmSave()

        XCTAssertEqual(subject.phase, .committed(.task(id: "saved-task")))
        XCTAssertEqual(saver.received.map(\.categoryID), [categoryID])
    }

    func testNilSystemDefaultRequiresAtLeastOneWritableSource() {
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(result: .success(eventPreview()), saver: saver, options: options(calendars: []))
        subject.text = "Dentist"
        subject.parse()

        XCTAssertFalse(subject.canSave)
        subject.confirmSave()

        XCTAssertEqual(subject.phase, .confirmation(.failed(.systemDefaultUnavailable)))
        XCTAssertTrue(saver.received.isEmpty)
    }

    func testDirtyEntryConfirmationAndFailureRequireExplicitDiscard() {
        let entry = makeSubject(result: .success(taskPreview()))
        XCTAssertEqual(entry.requestDismissal(), .dismiss)
        entry.text = "Draft"
        XCTAssertEqual(entry.requestDismissal(), .confirmDiscard)

        let confirmation = makeSubject(result: .success(taskPreview()))
        confirmation.text = "Draft"
        confirmation.parse()
        XCTAssertEqual(confirmation.requestDismissal(), .confirmDiscard)

        let failure = makeSubject(result: .success(taskPreview()), saver: RecordingQuickEntrySaver(steps: [.failure]))
        failure.text = "Draft"
        failure.parse()
        failure.confirmSave()
        XCTAssertEqual(failure.requestDismissal(), .confirmDiscard)
        failure.confirmDiscard()
        XCTAssertEqual(failure.requestDismissal(), .dismiss)
    }

    func testCommittedDismissesWithoutDiscardAndSavingCannotDismiss() {
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(result: .success(taskPreview()), saver: saver)
        subject.text = "Draft"
        subject.parse()
        saver.onSave = { XCTAssertEqual(subject.requestDismissal(), .blocked) }
        subject.confirmSave()
        XCTAssertEqual(subject.requestDismissal(), .dismiss)
    }

    func testEventToTaskMapsExactDueAndClearsEventFields() {
        var parsed = eventPreview(start: date(2026, 8, 25, 15), end: date(2026, 8, 25, 16))
        parsed.recurrence = weekly([3])
        parsed.reminderDate = date(2026, 8, 25, 14, 45)
        let subject = makeSubject(result: .success(parsed), options: options(defaultListID: "tasks"))
        subject.text = "Dentist"
        subject.parse()

        subject.selectKind(.task)

        XCTAssertEqual(subject.preview?.dueDate, date(2026, 8, 25, 15))
        XCTAssertEqual(subject.preview?.dueHasTime, true)
        XCTAssertEqual(subject.preview?.recurrence, weekly([3]))
        XCTAssertEqual(subject.preview?.reminderDate, date(2026, 8, 25, 14, 45))
        XCTAssertNil(subject.preview?.startDate)
        XCTAssertNil(subject.preview?.endDate)
        XCTAssertEqual(subject.preview?.destinationID, "tasks")
    }

    func testEventToRoutineMapsWeekdaysWindowAndTransformationNotice() {
        var parsed = eventPreview(start: date(2026, 8, 25, 15), end: date(2026, 8, 25, 16))
        parsed.recurrence = .init(frequency: .monthly, interval: 2, weekdays: [], endDate: date(2026, 12, 1))
        parsed.reminderDate = date(2026, 8, 25, 14, 45)
        let subject = makeSubject(result: .success(parsed))
        subject.text = "Review"
        subject.parse()

        subject.selectKind(.routine)

        XCTAssertEqual(subject.preview?.weekdays, [3])
        XCTAssertEqual(subject.preview?.routineWindow, .afternoon)
        XCTAssertNil(subject.preview?.recurrence)
        XCTAssertNil(subject.preview?.destinationID)
        XCTAssertNotNil(subject.transformationNotice)
        XCTAssertEqual(subject.preview?.reminderDate, date(2026, 8, 25, 14, 45))
    }

    func testTimedAndDateOnlyTasksMapToExactEventIntervals() {
        let timed = makeSubject(result: .success(taskPreview(due: date(2026, 8, 25, 15), dueHasTime: true)), options: options(defaultCalendarID: "work"))
        timed.text = "Submit"
        timed.parse()
        timed.selectKind(.event)
        XCTAssertEqual(timed.preview?.startDate, date(2026, 8, 25, 15))
        XCTAssertEqual(timed.preview?.endDate, date(2026, 8, 25, 16))
        XCTAssertEqual(timed.preview?.isAllDay, false)

        let dateOnly = makeSubject(result: .success(taskPreview(due: date(2026, 8, 25), dueHasTime: false)), options: options(defaultCalendarID: "work"))
        dateOnly.text = "Submit"
        dateOnly.parse()
        dateOnly.selectKind(.event)
        XCTAssertEqual(dateOnly.preview?.startDate, date(2026, 8, 25))
        XCTAssertEqual(dateOnly.preview?.endDate, date(2026, 8, 26))
        XCTAssertEqual(dateOnly.preview?.isAllDay, true)
        XCTAssertEqual(dateOnly.preview?.destinationID, "work")
    }

    func testDateOnlyTaskToEventUsesNextLocalDayAcrossDST() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let due = newYork.date(from: DateComponents(timeZone: newYork.timeZone, year: 2026, month: 3, day: 8))!
        let now = newYork.date(from: DateComponents(timeZone: newYork.timeZone, year: 2026, month: 3, day: 7, hour: 12))!
        let localContext = QuickEntryParseContext(now: now, calendar: newYork, locale: Locale(identifier: "en_US"), timeZone: newYork.timeZone)
        let subject = makeSubject(
            result: .success(taskPreview(due: due, dueHasTime: false)),
            options: options(defaultCalendarID: "work"),
            parseContext: localContext
        )
        subject.text = "Submit March 8"
        subject.parse()

        subject.selectKind(.event)

        let end = newYork.date(from: DateComponents(timeZone: newYork.timeZone, year: 2026, month: 3, day: 9))!
        XCTAssertEqual(subject.preview?.startDate, due)
        XCTAssertEqual(subject.preview?.endDate, end)
        XCTAssertEqual(end.timeIntervalSince(due), 23 * 3_600)
    }

    func testUnscheduledTaskToEventUsesNextWholeLocalHourStrictlyAfterNow() {
        let subject = makeSubject(result: .success(taskPreview(due: nil, dueHasTime: false)), options: options(defaultCalendarID: "work"))
        subject.text = "Call Alex"
        subject.parse()

        subject.selectKind(.event)

        XCTAssertEqual(subject.preview?.startDate, date(2026, 8, 24, 8))
        XCTAssertEqual(subject.preview?.endDate, date(2026, 8, 24, 9))
    }

    func testTaskToRoutineUsesDueWeekdayWindowAndOnlyExplicitAlert() {
        var parsed = taskPreview(due: date(2026, 8, 25, 18), dueHasTime: true)
        parsed.reminderDate = nil
        let subject = makeSubject(result: .success(parsed))
        subject.text = "Read"
        subject.parse()

        subject.selectKind(.routine)

        XCTAssertEqual(subject.preview?.weekdays, [3])
        XCTAssertEqual(subject.preview?.routineWindow, .evening)
        XCTAssertNil(subject.preview?.reminderDate)
        XCTAssertNil(subject.preview?.dueDate)
    }

    func testRoutineToEventUsesNextEligibleOccurrenceCanonicalRepeatAndReminderTime() {
        var parsed = routinePreview(days: [3], window: .morning)
        parsed.reminderDate = date(2026, 8, 20, 8, 30)
        let subject = makeSubject(result: .success(parsed), options: options(defaultCalendarID: "work"))
        subject.text = "Read"
        subject.parse()

        subject.selectKind(.event)

        XCTAssertEqual(subject.preview?.startDate, date(2026, 8, 25, 9))
        XCTAssertEqual(subject.preview?.endDate, date(2026, 8, 25, 10))
        XCTAssertEqual(subject.preview?.recurrence, weekly([3]))
        XCTAssertEqual(subject.preview?.reminderDate, date(2026, 8, 25, 8, 30))
    }

    func testRoutineToTaskUsesNextEligibleDayAndCanonicalRepeat() {
        var parsed = routinePreview(days: Set(1...7), window: .anytime)
        parsed.reminderDate = date(2026, 8, 20, 8, 30)
        let subject = makeSubject(result: .success(parsed), options: options(defaultListID: "tasks"))
        subject.text = "Read"
        subject.parse()

        subject.selectKind(.task)

        XCTAssertEqual(subject.preview?.dueDate, date(2026, 8, 24))
        XCTAssertEqual(subject.preview?.dueHasTime, false)
        XCTAssertEqual(subject.preview?.recurrence, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil))
        XCTAssertEqual(subject.preview?.reminderDate, date(2026, 8, 24, 8, 30))
        XCTAssertEqual(subject.preview?.destinationID, "tasks")
    }

    func testKindSwitchesRestoreOnlyTheirOwnDestinationNamespace() {
        let subject = makeSubject(result: .success(eventPreview()), options: options(defaultCalendarID: "work", defaultListID: "tasks"))
        subject.text = "Plan"
        subject.parse()
        subject.preview?.destinationID = "home"
        subject.selectKind(.task)
        XCTAssertEqual(subject.preview?.destinationID, "tasks")
        subject.preview?.destinationID = "personal-tasks"

        subject.selectKind(.event)
        XCTAssertEqual(subject.preview?.destinationID, "home")
        subject.selectKind(.task)
        XCTAssertEqual(subject.preview?.destinationID, "personal-tasks")
        subject.selectKind(.routine)
        XCTAssertNil(subject.preview?.destinationID)
    }

    func testEditorHooksUseCapturedCalendarAndKeepTaskDueRecurrenceValid() {
        let subject = makeSubject(result: .success(taskPreview(due: nil, dueHasTime: false)))
        subject.text = "Read"
        subject.parse()

        subject.setRecurrenceEnabled(true)

        XCTAssertEqual(subject.preview?.dueDate, date(2026, 8, 24, 8))
        XCTAssertEqual(subject.preview?.dueHasTime, true)
        XCTAssertEqual(subject.preview?.recurrence, .init(frequency: .daily, interval: 1, weekdays: [], endDate: nil))

        subject.setTaskDueEnabled(false)

        XCTAssertNil(subject.preview?.dueDate)
        XCTAssertEqual(subject.preview?.dueHasTime, false)
        XCTAssertNil(subject.preview?.recurrence)
    }

    func testReminderAndRecurrenceEndHooksSeedFromCapturedSchedule() {
        let subject = makeSubject(result: .success(eventPreview()))
        subject.text = "Dentist"
        subject.parse()

        subject.setReminderEnabled(true)
        subject.setRecurrenceEnabled(true)
        subject.setRecurrenceEndEnabled(true)

        XCTAssertEqual(subject.preview?.reminderDate, date(2026, 8, 24, 8, 50))
        XCTAssertEqual(subject.preview?.recurrence?.endDate, date(2026, 9, 24, 9))
        XCTAssertEqual(subject.weekdayOrder.count, 7)
        XCTAssertFalse(subject.weekdayName(subject.weekdayOrder[0]).isEmpty)
    }

    func testSelectingRecentItemReturnsExactTextToEntryWithoutSaving() {
        let profileID = UUID()
        let profileIdentity: ProfileIdentity = .saved(profileID)
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.record(
            text: "Study session tomorrow at 3pm",
            profileIdentity: profileIdentity,
            at: date(2026, 8, 23, 12)
        )
        let saver = RecordingQuickEntrySaver()
        let subject = makeSubject(
            result: .success(eventPreview()),
            saver: saver,
            creationProfile: creationProfile(id: profileID),
            historyStore: history
        )

        XCTAssertEqual(subject.recentEntries.count, 1)
        guard let recentID = subject.recentEntries.first?.id else { return }
        subject.selectRecent(id: recentID)

        XCTAssertEqual(subject.text, "Study session tomorrow at 3pm")
        XCTAssertEqual(subject.phase, .entry(parseError: nil))
        XCTAssertNil(subject.preview)
        XCTAssertTrue(saver.received.isEmpty)
    }

    func testSelectingRecentItemForUnchangedTextForcesAFreshParse() {
        let profileID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.record(
            text: "Study session tomorrow at 3pm",
            profileIdentity: .saved(profileID),
            at: date(2026, 8, 23, 12)
        )
        let parser = LockedSequenceParser([
            .success(eventPreview()),
            .success(taskPreview(due: nil, dueHasTime: false))
        ])
        let subject = QuickEntryViewModel(
            parser: parser,
            saver: RecordingQuickEntrySaver(),
            context: context(),
            destinations: options(defaultListID: "tasks"),
            creationProfile: creationProfile(id: profileID),
            historyStore: history
        )
        subject.text = "Study session tomorrow at 3pm"
        subject.parse()
        subject.preview?.title = "Edited stale title"
        subject.returnToEntry()
        guard let recentID = subject.recentEntries.first?.id else {
            return XCTFail("Expected a recent entry")
        }

        subject.selectRecent(id: recentID)
        subject.parse()

        XCTAssertEqual(subject.preview?.kind, .task)
        XCTAssertEqual(subject.preview?.title, "Submit report")
        XCTAssertEqual(subject.preview?.destinationID, "tasks")
    }

    func testSuccessfulCommitRecordsHistoryAndEditedPreferenceExactlyOnce() {
        let profileID = UUID()
        let profileIdentity: ProfileIdentity = .saved(profileID)
        let categoryID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        let saver = RecordingQuickEntrySaver(steps: [.success(.event(id: "saved-event"))])
        let subject = makeSubject(
            result: .success(eventPreview()),
            saver: saver,
            options: options(
                calendars: [calendarDescriptor("school", "School")],
                defaultCalendarID: "school"
            ),
            categories: [category(id: categoryID)],
            creationProfile: creationProfile(id: profileID),
            historyStore: history
        )
        subject.text = "  Study session tomorrow at 3pm  "
        subject.parse()
        subject.preview?.endDate = date(2026, 8, 24, 10, 30)
        subject.preview?.categoryID = categoryID
        subject.selectDestination("school")

        subject.confirmSave()
        subject.confirmSave()

        let items = history.items(for: profileIdentity)
        XCTAssertEqual(items.count, 1)
        guard let item = items.first else { return }
        XCTAssertEqual(item.text, "Study session tomorrow at 3pm")
        XCTAssertEqual(item.profileIdentity, profileIdentity)
        XCTAssertEqual(item.lastUsedAt, context().now)
        XCTAssertEqual(
            history.preference(profileID: profileID, kind: .event),
            QuickEntryRememberedChoices(
                durationMinutes: 90,
                categoryID: categoryID,
                destinationID: "school"
            )
        )
    }

    func testFailedSaveRecordsNoHistoryOrPreference() {
        let profileID = UUID()
        let profileIdentity: ProfileIdentity = .saved(profileID)
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        let subject = makeSubject(
            result: .success(eventPreview()),
            saver: RecordingQuickEntrySaver(steps: [.failure]),
            options: options(
                calendars: [calendarDescriptor("school", "School")],
                defaultCalendarID: "school"
            ),
            creationProfile: creationProfile(id: profileID),
            historyStore: history
        )
        subject.text = "Study session tomorrow at 3pm"
        subject.parse()

        subject.confirmSave()

        XCTAssertTrue(history.items(for: profileIdentity).isEmpty)
        XCTAssertNil(history.preference(profileID: profileID, kind: .event))
    }

    func testParseReappliesSafeDurationCategoryAndProfileDestination() {
        let profileID = UUID()
        let categoryID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.setPreference(
            QuickEntryRememberedChoices(
                durationMinutes: 90,
                categoryID: categoryID,
                destinationID: "school-projects"
            ),
            profileID: profileID,
            kind: .event
        )
        let subject = makeSubject(
            result: .success(eventPreview()),
            options: options(
                calendars: [
                    calendarDescriptor("school", "School"),
                    calendarDescriptor("school-projects", "School Projects")
                ],
                defaultCalendarID: "school"
            ),
            categories: [category(id: categoryID)],
            creationProfile: creationProfile(
                id: profileID,
                calendarIDs: ["school", "school-projects"]
            ),
            historyStore: history
        )
        subject.text = "Study session tomorrow at 3pm"

        subject.parse()

        XCTAssertEqual(subject.preview?.startDate, date(2026, 8, 24, 9))
        XCTAssertEqual(subject.preview?.endDate, date(2026, 8, 24, 10, 30))
        XCTAssertEqual(subject.preview?.categoryID, categoryID)
        XCTAssertEqual(subject.preview?.destinationID, "school-projects")
    }

    func testParseIgnoresStaleCategoryAndWritableDestinationOutsideCapturedProfile() {
        let profileID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.setPreference(
            QuickEntryRememberedChoices(
                durationMinutes: 45,
                categoryID: UUID(),
                destinationID: "outside-work"
            ),
            profileID: profileID,
            kind: .event
        )
        let subject = makeSubject(
            result: .success(eventPreview()),
            options: options(
                calendars: [
                    calendarDescriptor("school", "School"),
                    calendarDescriptor("outside-work", "Outside Work")
                ],
                defaultCalendarID: "school"
            ),
            categories: [],
            creationProfile: creationProfile(
                id: profileID,
                calendarIDs: ["school"]
            ),
            historyStore: history
        )
        subject.text = "Study session tomorrow at 3pm"

        subject.parse()

        XCTAssertEqual(subject.preview?.endDate, date(2026, 8, 24, 9, 45))
        XCTAssertNil(subject.preview?.categoryID)
        XCTAssertEqual(subject.preview?.destinationID, "school")
    }

    func testParseRestoresRememberedSystemDefaultInsteadOfProfileDefault() {
        let profileID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.setPreference(
            QuickEntryRememberedChoices(
                durationMinutes: nil,
                categoryID: nil,
                destinationID: nil
            ),
            profileID: profileID,
            kind: .event
        )
        let subject = makeSubject(
            result: .success(eventPreview()),
            options: options(
                calendars: [calendarDescriptor("school", "School")],
                defaultCalendarID: "school"
            ),
            creationProfile: creationProfile(id: profileID),
            historyStore: history
        )
        subject.text = "Study session tomorrow at 3pm"

        subject.parse()

        XCTAssertNil(subject.preview?.destinationID)
        XCTAssertTrue(subject.systemDefaultIsAvailable(for: .event))
    }

    func testAllDayEventDoesNotInheritRememberedTimedDuration() {
        let profileID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.setPreference(
            QuickEntryRememberedChoices(
                durationMinutes: 90,
                categoryID: nil,
                destinationID: nil
            ),
            profileID: profileID,
            kind: .event
        )
        let allDay = QuickEntryPreview(
            kind: .event,
            title: "School holiday",
            startDate: date(2026, 8, 25),
            endDate: date(2026, 8, 26),
            isAllDay: true
        )
        let subject = makeSubject(
            result: .success(allDay),
            options: options(
                calendars: [calendarDescriptor("school", "School")],
                defaultCalendarID: "school"
            ),
            creationProfile: creationProfile(id: profileID),
            historyStore: history
        )
        subject.text = "School holiday tomorrow"

        subject.parse()

        XCTAssertEqual(subject.preview?.startDate, date(2026, 8, 25))
        XCTAssertEqual(subject.preview?.endDate, date(2026, 8, 26))
        XCTAssertEqual(subject.preview?.isAllDay, true)
    }

    func testParserSuppliedDestinationWinsOverRememberedPreference() {
        let profileID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.setPreference(
            QuickEntryRememberedChoices(
                durationMinutes: nil,
                categoryID: nil,
                destinationID: "school-remembered"
            ),
            profileID: profileID,
            kind: .event
        )
        var parsed = eventPreview()
        parsed.destinationID = "school-parser"
        let subject = makeSubject(
            result: .success(parsed),
            options: options(
                calendars: [
                    calendarDescriptor("school-parser", "Parser"),
                    calendarDescriptor("school-remembered", "Remembered")
                ],
                defaultCalendarID: "school-remembered"
            ),
            creationProfile: creationProfile(
                id: profileID,
                calendarIDs: ["school-parser", "school-remembered"]
            ),
            historyStore: history
        )
        subject.text = "Study session tomorrow at 3pm"

        subject.parse()

        XCTAssertEqual(subject.preview?.destinationID, "school-parser")
    }

    func testSwitchingKindAppliesThatKindsSafeRememberedChoices() {
        let profileID = UUID()
        let categoryID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.setPreference(
            .init(
                durationMinutes: 90,
                categoryID: categoryID,
                destinationID: "school-projects"
            ),
            profileID: profileID,
            kind: .event
        )
        let subject = makeSubject(
            result: .success(taskPreview(due: date(2026, 8, 25, 9), dueHasTime: true)),
            options: options(
                calendars: [
                    calendarDescriptor("school", "School"),
                    calendarDescriptor("school-projects", "School Projects")
                ],
                defaultCalendarID: "school"
            ),
            categories: [category(id: categoryID)],
            creationProfile: creationProfile(
                id: profileID,
                calendarIDs: ["school", "school-projects"]
            ),
            historyStore: history
        )
        subject.text = "Submit report tomorrow at 9am"
        subject.parse()

        subject.selectKind(.event)

        XCTAssertEqual(subject.preview?.startDate, date(2026, 8, 25, 9))
        XCTAssertEqual(subject.preview?.endDate, date(2026, 8, 25, 10, 30))
        XCTAssertEqual(subject.preview?.categoryID, categoryID)
        XCTAssertEqual(subject.preview?.destinationID, "school-projects")
    }

    func testSavingAllDayEventPreservesRememberedTimedDuration() {
        let profileID = UUID()
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.setPreference(
            .init(durationMinutes: 90, categoryID: nil, destinationID: "school"),
            profileID: profileID,
            kind: .event
        )
        let allDay = QuickEntryPreview(
            kind: .event,
            title: "School holiday",
            startDate: date(2026, 8, 25),
            endDate: date(2026, 8, 26),
            isAllDay: true
        )
        let subject = makeSubject(
            result: .success(allDay),
            saver: RecordingQuickEntrySaver(steps: [.success(.event(id: "holiday"))]),
            options: options(
                calendars: [calendarDescriptor("school", "School")],
                defaultCalendarID: "school"
            ),
            creationProfile: creationProfile(id: profileID),
            historyStore: history
        )
        subject.text = "School holiday tomorrow"
        subject.parse()

        subject.confirmSave()

        XCTAssertEqual(
            history.preference(profileID: profileID, kind: .event)?.durationMinutes,
            90
        )
    }
}

private enum QuickEntrySaverStep {
    case success(QuickEntrySaveOutcome)
    case failure
}

@MainActor
private final class RecordingQuickEntrySaver: QuickEntrySaving {
    private(set) var received: [QuickEntryPreview] = []
    var onSave: (() -> Void)?
    private var steps: [QuickEntrySaverStep]
    private let fixedError: Error?

    init(steps: [QuickEntrySaverStep] = [.success(.task(id: "saved-task"))], error: Error? = nil) {
        self.steps = steps
        self.fixedError = error
    }

    func save(_ preview: QuickEntryPreview) throws -> QuickEntrySaveOutcome {
        received.append(preview)
        onSave?()
        if let fixedError { throw fixedError }
        let step = steps.isEmpty ? .success(.task(id: "saved-task")) : steps.removeFirst()
        switch step {
        case let .success(outcome): return outcome
        case .failure: throw QuickEntryViewModelTestError.saveFailed
        }
    }
}

private struct StubQuickEntryParser: QuickEntryParsing {
    let result: Result<QuickEntryPreview, QuickEntryParseError>
    func parse(_ text: String, context: QuickEntryParseContext) throws -> QuickEntryPreview { try result.get() }
}

private final class LockedSequenceParser: QuickEntryParsing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<QuickEntryPreview, QuickEntryParseError>]
    init(_ results: [Result<QuickEntryPreview, QuickEntryParseError>]) { self.results = results }
    func parse(_ text: String, context: QuickEntryParseContext) throws -> QuickEntryPreview {
        try lock.withLock { try results.removeFirst().get() }
    }
}

private enum QuickEntryViewModelTestError: Error { case saveFailed }

@MainActor
private func makeSubject(
    result: Result<QuickEntryPreview, QuickEntryParseError>,
    saver: RecordingQuickEntrySaver = RecordingQuickEntrySaver(),
    options: QuickEntryDestinationOptions = options(),
    parseContext: QuickEntryParseContext = context(),
    categories: [CategorySnapshot] = [],
    creationProfile: CreationProfileContext? = nil,
    historyStore: QuickEntryHistoryStore? = nil,
    onCommitted: @escaping @MainActor (QuickEntrySaveOutcome) -> Void = { _ in }
) -> QuickEntryViewModel {
    QuickEntryViewModel(
        parser: StubQuickEntryParser(result: result),
        saver: saver,
        context: parseContext,
        destinations: options,
        categories: categories,
        creationProfile: creationProfile,
        historyStore: historyStore,
        historyNow: { parseContext.now },
        onCommitted: onCommitted
    )
}

private func context() -> QuickEntryParseContext {
    QuickEntryParseContext(now: date(2026, 8, 24, 7, 30), calendar: singaporeCalendar(), locale: Locale(identifier: "en_SG"), timeZone: singaporeCalendar().timeZone)
}

private func singaporeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
    calendar.locale = Locale(identifier: "en_SG")
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    singaporeCalendar().date(from: DateComponents(timeZone: singaporeCalendar().timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func eventPreview(start: Date = date(2026, 8, 24, 9), end: Date = date(2026, 8, 24, 10)) -> QuickEntryPreview {
    .init(kind: .event, title: "Dentist", startDate: start, endDate: end)
}

private func taskPreview(due: Date? = date(2026, 8, 25), dueHasTime: Bool = false) -> QuickEntryPreview {
    .init(kind: .task, title: "Submit report", dueDate: due, dueHasTime: dueHasTime)
}

private func routinePreview(days: Set<Int> = Set(1...7), window: RoutineWindow = .evening) -> QuickEntryPreview {
    .init(kind: .routine, title: "Read", routineWindow: window, weekdays: days)
}

private func weekly(_ weekdays: Set<Int>) -> RecurrenceRuleDraft {
    .init(frequency: .weekly, interval: 1, weekdays: weekdays, endDate: nil)
}

private func calendarDescriptor(_ id: String, _ title: String, writable: Bool = true) -> CalendarDescriptor {
    .init(id: id, title: title, colorHex: "#000000", allowsContentModifications: writable)
}

private func listDescriptor(_ id: String, _ title: String, writable: Bool = true) -> ReminderListDescriptor {
    .init(id: id, title: title, colorHex: "#000000", allowsContentModifications: writable)
}

private func category(id: UUID) -> CategorySnapshot {
    .init(id: id, name: "Study", colorHex: "#4868A8", sortOrder: 0)
}

private func creationProfile(
    id: UUID,
    calendarIDs: Set<String> = ["school"],
    reminderListIDs: Set<String> = ["tasks"],
    defaultCalendarID: String? = "school",
    defaultReminderListID: String? = "tasks"
) -> CreationProfileContext {
    CreationProfileContext(
        profileID: id,
        profileName: "School",
        memberCalendarIDs: calendarIDs,
        memberReminderListIDs: reminderListIDs,
        defaultCalendarID: defaultCalendarID,
        defaultReminderListID: defaultReminderListID,
        requiresExplicitCalendarDestination: defaultCalendarID == nil,
        requiresExplicitReminderDestination: defaultReminderListID == nil
    )
}

private func options(
    calendarAccess: AccessState = .granted,
    remindersAccess: AccessState = .granted,
    calendars: [CalendarDescriptor] = [calendarDescriptor("home", "Home"), calendarDescriptor("work", "Work")],
    reminderLists: [ReminderListDescriptor] = [listDescriptor("personal-tasks", "Personal"), listDescriptor("tasks", "Tasks")],
    defaultCalendarID: String? = nil,
    defaultListID: String? = nil,
    visibleCalendarIDs: Set<String> = ["home", "work"],
    visibleReminderListIDs: Set<String> = ["personal-tasks", "tasks"]
) -> QuickEntryDestinationOptions {
    .init(
        calendarAccess: calendarAccess,
        remindersAccess: remindersAccess,
        calendars: calendars,
        reminderLists: reminderLists,
        defaultCalendarID: defaultCalendarID,
        defaultReminderListID: defaultListID,
        visibleCalendarIDs: visibleCalendarIDs,
        visibleReminderListIDs: visibleReminderListIDs
    )
}
