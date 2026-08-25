import Foundation
import XCTest
@testable import PersonalCalendar

/// RED contract for confirmed Quick Entry persistence. These tests deliberately
/// name the missing Task 4 API so production can be added against a fixed,
/// provider-independent boundary.
@MainActor
final class SaveRouterTests: XCTestCase {
    func testRouterImplementsSynchronousQuickEntrySavingContract() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let subject: any QuickEntrySaving = makeSubject(
            calendar: calendar,
            reminders: reminders,
            routines: routines
        )

        let outcome = try subject.save(eventPreview())

        XCTAssertEqual(outcome, .event(id: "event-id"))
        assertCreateAttempts(event: 1, task: 0, routine: 0, calendar, reminders, routines)
    }

    func testEventRouteCreatesExactDraftAndTouchesOnlyCalendar() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let recurrence = RecurrenceRuleDraft(
            frequency: .weekly,
            interval: 2,
            weekdays: [2, 4],
            endDate: end.addingTimeInterval(86_400 * 20)
        )
        let preview = eventPreview(
            title: "  Planning session  ",
            recurrence: recurrence,
            reminderDate: start.addingTimeInterval(-900)
        )

        let outcome = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(preview)

        XCTAssertEqual(outcome, .event(id: "event-id"))
        XCTAssertEqual(
            calendar.receivedDrafts,
            [
                EventDraft(
                    title: "  Planning session  ",
                    start: start,
                    end: end,
                    isAllDay: false,
                    calendarID: "calendar",
                    alarms: .replace([-900]),
                    recurrence: .replace(recurrence)
                )
            ]
        )
        assertCreateAttempts(event: 1, task: 0, routine: 0, calendar, reminders, routines)
    }

    func testEventWithoutReminderOrRecurrenceUsesClearIntents() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()

        _ = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(eventPreview())

        XCTAssertEqual(
            calendar.receivedDrafts.single,
            EventDraft(
                title: "Planning session",
                start: start,
                end: end,
                isAllDay: false,
                calendarID: "calendar",
                alarms: .clear,
                recurrence: .clear
            )
        )
    }

    func testAllDayEventPreservesExactRangeFlagAndDestination() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let dayStart = utcDate(year: 2026, month: 9, day: 8)
        let nextDay = utcDate(year: 2026, month: 9, day: 9)
        let preview = eventPreview(
            title: "Offsite",
            startDate: dayStart,
            endDate: nextDay,
            isAllDay: true,
            destinationID: "calendar"
        )

        _ = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(preview)

        XCTAssertEqual(calendar.receivedDrafts.single?.start, dayStart)
        XCTAssertEqual(calendar.receivedDrafts.single?.end, nextDay)
        XCTAssertEqual(calendar.receivedDrafts.single?.calendarID, "calendar")
        XCTAssertTrue(calendar.receivedDrafts.single?.isAllDay == true)
    }

    func testTaskRouteCreatesExactDraftAndTouchesOnlyReminders() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let due = start.addingTimeInterval(7_200)
        let alert = due.addingTimeInterval(-1_800)
        let recurrence = RecurrenceRuleDraft(
            frequency: .monthly,
            interval: 1,
            weekdays: [],
            endDate: due.addingTimeInterval(86_400 * 90)
        )
        let preview = taskPreview(
            title: "  Submit report  ",
            dueDate: due,
            dueHasTime: true,
            recurrence: recurrence,
            reminderDate: alert
        )

        let outcome = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(preview)

        XCTAssertEqual(outcome, .task(id: "task-id"))
        XCTAssertEqual(
            reminders.receivedDrafts,
            [
                ReminderDraft(
                    title: "  Submit report  ",
                    notes: nil,
                    dueDate: due,
                    dueHasTime: true,
                    priority: 0,
                    listID: "list",
                    alarm: .replace(alert),
                    recurrence: .replace(recurrence)
                )
            ]
        )
        assertCreateAttempts(event: 0, task: 1, routine: 0, calendar, reminders, routines)
    }

    func testTaskWithoutDueReminderOrRecurrenceUsesClearIntents() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()

        _ = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(taskPreview())

        XCTAssertEqual(
            reminders.receivedDrafts.single,
            ReminderDraft(
                title: "Submit report",
                notes: nil,
                dueDate: nil,
                dueHasTime: false,
                priority: 0,
                listID: "list",
                alarm: .clear,
                recurrence: .clear
            )
        )
    }

    func testDateOnlyTaskUsesReplacementScheduleWithoutInventingTime() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let due = utcDate(year: 2026, month: 10, day: 3)

        _ = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(taskPreview(dueDate: due, dueHasTime: false))

        XCTAssertEqual(
            reminders.receivedDrafts.single?.schedule,
            .replace(.init(date: due, hasTime: false))
        )
    }

    func testRoutineRouteTrimsTitleUsesInjectedTimeZoneAndTouchesOnlyRepository() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routineID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let routines = RouterRoutineSpy(createID: routineID)
        let localCalendar = configuredCalendar(timeZoneID: "Asia/Tokyo")
        let absoluteReminder = utcDate(year: 2026, month: 11, day: 5, hour: 1, minute: 45)
        let preview = routinePreview(
            title: " \n Stretch \t ",
            window: .morning,
            weekdays: [2, 4, 6],
            reminderDate: absoluteReminder
        )

        let outcome = try makeSubject(
            calendar: calendar,
            reminders: reminders,
            routines: routines,
            localCalendar: localCalendar
        ).save(preview)

        XCTAssertEqual(outcome, .routine(id: routineID))
        XCTAssertEqual(
            routines.receivedDrafts,
            [
                RoutineDraft(
                    title: "Stretch",
                    weekdays: [2, 4, 6],
                    window: .morning,
                    reminderHour: 10,
                    reminderMinute: 45
                )
            ]
        )
        assertCreateAttempts(event: 0, task: 0, routine: 1, calendar, reminders, routines)
    }

    func testRoutineWithoutReminderWritesBothComponentsAsNil() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()

        _ = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(routinePreview(reminderDate: nil))

        XCTAssertNil(routines.receivedDrafts.single?.reminderHour)
        XCTAssertNil(routines.receivedDrafts.single?.reminderMinute)
    }

    func testNilEventIdentifierIsTypedTerminalSuccess() throws {
        let calendar = RouterCalendarSpy(createID: nil)
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()

        let outcome = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(eventPreview())

        XCTAssertEqual(outcome, .event(id: nil))
        assertCreateAttempts(event: 1, task: 0, routine: 0, calendar, reminders, routines)
    }

    func testNilTaskIdentifierIsTypedTerminalSuccess() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy(createID: nil)
        let routines = RouterRoutineSpy()

        let outcome = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(taskPreview())

        XCTAssertEqual(outcome, .task(id: nil))
        assertCreateAttempts(event: 0, task: 1, routine: 0, calendar, reminders, routines)
    }

    func testBlankEventTitleIsNormalizedWithoutAnyCreateAttempt() {
        assertRejected(
            eventPreview(title: " \n\t "),
            as: .invalidTitle
        )
    }

    func testBlankTaskTitleIsNormalizedWithoutAnyCreateAttempt() {
        assertRejected(
            taskPreview(title: " \n\t "),
            as: .invalidTitle
        )
    }

    func testBlankRoutineTitleIsNormalizedWithoutAnyCreateAttempt() {
        assertRejected(
            routinePreview(title: " \n\t "),
            as: .invalidTitle
        )
    }

    func testEventRequiresBothStartAndEndBeforeAnyCreateAttempt() {
        var missingStart = eventPreview()
        missingStart.startDate = nil
        assertRejected(
            missingStart,
            as: .invalidEventSchedule
        )

        var missingEnd = eventPreview()
        missingEnd.endDate = nil
        assertRejected(
            missingEnd,
            as: .invalidEventSchedule
        )
    }

    func testEventRejectsEqualOrInvertedRangeBeforeAnyCreateAttempt() {
        assertRejected(
            eventPreview(startDate: start, endDate: start),
            as: .invalidEventSchedule
        )
        assertRejected(
            eventPreview(startDate: end, endDate: start),
            as: .invalidEventSchedule
        )
    }

    func testEventRejectsEveryNonfiniteEndpointBeforeAnyCreateAttempt() {
        for invalidDate in nonfiniteDates {
            assertRejected(
                eventPreview(startDate: invalidDate, endDate: end),
                as: .invalidEventSchedule
            )
            assertRejected(
                eventPreview(startDate: start, endDate: invalidDate),
                as: .invalidEventSchedule
            )
        }
    }

    func testEventRejectsNonfiniteAlarmOffsetBeforeAnyCreateAttempt() {
        for invalidDate in nonfiniteDates {
            assertRejected(
                eventPreview(reminderDate: invalidDate),
                as: .invalidEventSchedule
            )
        }
    }

    func testTaskRejectsTimedFlagWithoutDueDateBeforeAnyCreateAttempt() {
        assertRejected(
            taskPreview(dueDate: nil, dueHasTime: true),
            as: .invalidTaskSchedule
        )
    }

    func testTaskRejectsNonfiniteDueAndReminderDatesBeforeAnyCreateAttempt() {
        for invalidDate in nonfiniteDates {
            assertRejected(
                taskPreview(dueDate: invalidDate),
                as: .invalidTaskSchedule
            )
            assertRejected(
                taskPreview(reminderDate: invalidDate),
                as: .invalidTaskSchedule
            )
        }
    }

    func testRecurringTaskRequiresEffectiveDueDateBeforeAnyCreateAttempt() {
        assertRejected(
            taskPreview(recurrence: validRecurrence),
            as: .invalidTaskSchedule
        )
    }

    func testEventRejectsEveryMalformedRecurrenceBeforeAnyCreateAttempt() {
        let malformedRules = [
            RecurrenceRuleDraft(frequency: .weekly, interval: 0, weekdays: [2], endDate: nil),
            RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [0, 8], endDate: nil),
            RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [2], endDate: nil),
            RecurrenceRuleDraft(frequency: .monthly, interval: 1, weekdays: [], endDate: start.addingTimeInterval(-1)),
            RecurrenceRuleDraft(frequency: .yearly, interval: 1, weekdays: [], endDate: Date(timeIntervalSinceReferenceDate: .infinity))
        ]

        for recurrence in malformedRules {
            assertRejected(
                eventPreview(recurrence: recurrence),
                as: .invalidRecurrence
            )
        }
    }

    func testTaskRejectsEveryMalformedRecurrenceBeforeAnyCreateAttempt() {
        let due = start.addingTimeInterval(3_600)
        let malformedRules = [
            RecurrenceRuleDraft(frequency: .weekly, interval: -1, weekdays: [2], endDate: nil),
            RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [9], endDate: nil),
            RecurrenceRuleDraft(frequency: .monthly, interval: 1, weekdays: [2], endDate: nil),
            RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: due.addingTimeInterval(-1))
        ]

        for recurrence in malformedRules {
            assertRejected(
                taskPreview(dueDate: due, recurrence: recurrence),
                as: .invalidRecurrence
            )
        }
    }

    func testRoutineRejectsMalformedRecurrenceEvenThoughRoutineDraftDoesNotPersistIt() {
        assertRejected(
            routinePreview(
                recurrence: .init(frequency: .daily, interval: 0, weekdays: [], endDate: nil)
            ),
            as: .invalidRecurrence
        )
    }

    func testRoutineRequiresWindowBeforeAnyCreateAttempt() {
        assertRejected(
            routinePreview(window: nil),
            as: .invalidRoutineSchedule
        )
    }

    func testRoutineRejectsEmptyAndOutOfRangeWeekdaysBeforeAnyCreateAttempt() {
        for weekdays: Set<Int> in [[], [0], [8], [1, 7, 9]] {
            assertRejected(
                routinePreview(weekdays: weekdays),
                as: .invalidRoutineSchedule
            )
        }
    }

    func testRoutineRejectsNonfiniteReminderBeforeCalendarExtractionOrCreate() {
        for invalidDate in nonfiniteDates {
            assertRejected(
                routinePreview(reminderDate: invalidDate),
                as: .invalidRoutineSchedule
            )
        }
    }

    func testEveryKindRejectsTaskFiveCategoryBeforeAnyCreateAttempt() {
        let categoryID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var previews = [eventPreview(), taskPreview(), routinePreview()]
        for index in previews.indices {
            previews[index].categoryID = categoryID
        }

        for preview in previews {
            assertRejected(preview, as: .unsupportedCategory)
        }
    }

    func testConversionFailurePrecedesUnavailableSourceAndCreatesNothing() {
        let calendar = RouterCalendarSpy(accessState: .denied, descriptors: [])
        let reminders = RouterRemindersSpy(accessState: .denied, descriptors: [])
        let routines = RouterRoutineSpy()
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

        assertSaveError(.invalidTitle, saving: eventPreview(title: " "), with: subject)

        assertNoCreateAttempts(calendar, reminders, routines)
    }

    func testEventRejectsEveryUnavailableAccessStateBeforeCreate() {
        for accessState: AccessState in [.notDetermined, .denied, .restricted] {
            let calendar = RouterCalendarSpy(accessState: accessState, descriptors: [writableCalendar])
            let reminders = RouterRemindersSpy()
            let routines = RouterRoutineSpy()
            let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

            assertSaveError(.accessUnavailable, saving: eventPreview(), with: subject)

            assertNoCreateAttempts(calendar, reminders, routines)
        }
    }

    func testTaskRejectsEveryUnavailableAccessStateBeforeCreate() {
        for accessState: AccessState in [.notDetermined, .denied, .restricted] {
            let calendar = RouterCalendarSpy()
            let reminders = RouterRemindersSpy(accessState: accessState, descriptors: [writableList])
            let routines = RouterRoutineSpy()
            let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

            assertSaveError(.accessUnavailable, saving: taskPreview(), with: subject)

            assertNoCreateAttempts(calendar, reminders, routines)
        }
    }

    func testEventSystemDefaultRequiresGrantedAccessAndForwardsNilWithWritableSource() throws {
        let calendar = RouterCalendarSpy(
            descriptors: [readOnlyCalendar, writableCalendar]
        )
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()

        let outcome = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(eventPreview(destinationID: nil))

        XCTAssertEqual(outcome, .event(id: "event-id"))
        XCTAssertNil(calendar.receivedDrafts.single?.calendarID)
        assertCreateAttempts(event: 1, task: 0, routine: 0, calendar, reminders, routines)
    }

    func testTaskSystemDefaultRequiresGrantedAccessAndForwardsNilWithWritableSource() throws {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy(
            descriptors: [readOnlyList, writableList]
        )
        let routines = RouterRoutineSpy()

        let outcome = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(taskPreview(destinationID: nil))

        XCTAssertEqual(outcome, .task(id: "task-id"))
        XCTAssertNil(reminders.receivedDrafts.single?.listID)
        assertCreateAttempts(event: 0, task: 1, routine: 0, calendar, reminders, routines)
    }

    func testEventSystemDefaultRejectsEmptyOrOnlyReadOnlySources() {
        for descriptors in [[], [readOnlyCalendar]] {
            let calendar = RouterCalendarSpy(descriptors: descriptors)
            let reminders = RouterRemindersSpy()
            let routines = RouterRoutineSpy()
            let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

            assertSaveError(.systemDefaultUnavailable, saving: eventPreview(destinationID: nil), with: subject)

            assertNoCreateAttempts(calendar, reminders, routines)
        }
    }

    func testTaskSystemDefaultRejectsEmptyOrOnlyReadOnlySources() {
        for descriptors in [[], [readOnlyList]] {
            let calendar = RouterCalendarSpy()
            let reminders = RouterRemindersSpy(descriptors: descriptors)
            let routines = RouterRoutineSpy()
            let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

            assertSaveError(.systemDefaultUnavailable, saving: taskPreview(destinationID: nil), with: subject)

            assertNoCreateAttempts(calendar, reminders, routines)
        }
    }

    func testEventExplicitDestinationMustStillExistImmediatelyBeforeCreate() {
        let calendar = RouterCalendarSpy(descriptors: [writableCalendar])
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)
        calendar.descriptors = [otherWritableCalendar]

        assertSaveError(.destinationMissing, saving: eventPreview(), with: subject)

        assertNoCreateAttempts(calendar, reminders, routines)
    }

    func testEventExplicitDestinationMustStillBeWritableImmediatelyBeforeCreate() {
        let calendar = RouterCalendarSpy(descriptors: [writableCalendar])
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)
        calendar.descriptors = [readOnlyCalendar]

        assertSaveError(.destinationReadOnly, saving: eventPreview(), with: subject)

        assertNoCreateAttempts(calendar, reminders, routines)
    }

    func testTaskExplicitDestinationMustStillExistImmediatelyBeforeCreate() {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy(descriptors: [writableList])
        let routines = RouterRoutineSpy()
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)
        reminders.descriptors = [otherWritableList]

        assertSaveError(.destinationMissing, saving: taskPreview(), with: subject)

        assertNoCreateAttempts(calendar, reminders, routines)
    }

    func testTaskExplicitDestinationMustStillBeWritableImmediatelyBeforeCreate() {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy(descriptors: [writableList])
        let routines = RouterRoutineSpy()
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)
        reminders.descriptors = [readOnlyList]

        assertSaveError(.destinationReadOnly, saving: taskPreview(), with: subject)

        assertNoCreateAttempts(calendar, reminders, routines)
    }

    func testAccessLossAfterRouterConstructionTakesPrecedenceOverDestinationState() {
        let eventCalendar = RouterCalendarSpy(descriptors: [writableCalendar])
        let eventReminders = RouterRemindersSpy()
        let eventRoutines = RouterRoutineSpy()
        let eventSubject = makeSubject(
            calendar: eventCalendar,
            reminders: eventReminders,
            routines: eventRoutines
        )
        eventCalendar.accessState = .denied

        assertSaveError(.accessUnavailable, saving: eventPreview(), with: eventSubject)
        assertNoCreateAttempts(eventCalendar, eventReminders, eventRoutines)

        let taskCalendar = RouterCalendarSpy()
        let taskReminders = RouterRemindersSpy(descriptors: [writableList])
        let taskRoutines = RouterRoutineSpy()
        let taskSubject = makeSubject(
            calendar: taskCalendar,
            reminders: taskReminders,
            routines: taskRoutines
        )
        taskReminders.accessState = .restricted

        assertSaveError(.accessUnavailable, saving: taskPreview(), with: taskSubject)
        assertNoCreateAttempts(taskCalendar, taskReminders, taskRoutines)
    }

    func testRoutineCreationDoesNotDependOnExternalAccessOrDestinations() throws {
        let calendar = RouterCalendarSpy(accessState: .denied, descriptors: [])
        let reminders = RouterRemindersSpy(accessState: .restricted, descriptors: [])
        let routines = RouterRoutineSpy()

        let outcome = try makeSubject(calendar: calendar, reminders: reminders, routines: routines)
            .save(routinePreview())

        if case .routine = outcome {
            // Expected typed success. The exact UUID is asserted by the spy's default below.
        } else {
            XCTFail("Expected a routine outcome, got \(outcome)")
        }
        XCTAssertEqual(outcome, .routine(id: routines.createID))
        assertCreateAttempts(event: 0, task: 0, routine: 1, calendar, reminders, routines)
    }

    func testEventProviderFailurePropagatesUnchangedAfterExactlyOneAttempt() {
        let calendar = RouterCalendarSpy(createError: RouterProviderFailure.write)
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

        assertProviderFailure(saving: eventPreview(), with: subject)

        assertCreateAttempts(event: 1, task: 0, routine: 0, calendar, reminders, routines)
    }

    func testTaskProviderFailurePropagatesUnchangedAfterExactlyOneAttempt() {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy(createError: RouterProviderFailure.write)
        let routines = RouterRoutineSpy()
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

        assertProviderFailure(saving: taskPreview(), with: subject)

        assertCreateAttempts(event: 0, task: 1, routine: 0, calendar, reminders, routines)
    }

    func testRoutineProviderFailurePropagatesUnchangedAfterExactlyOneAttempt() {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy(createError: RouterProviderFailure.write)
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

        assertProviderFailure(saving: routinePreview(), with: subject)

        assertCreateAttempts(event: 0, task: 0, routine: 1, calendar, reminders, routines)
    }

    private var start: Date { utcDate(year: 2026, month: 9, day: 2, hour: 9) }
    private var end: Date { utcDate(year: 2026, month: 9, day: 2, hour: 10) }
    private var nonfiniteDates: [Date] {
        [
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity)
        ]
    }
    private var validRecurrence: RecurrenceRuleDraft {
        .init(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil)
    }
    private var writableCalendar: CalendarDescriptor {
        .init(id: "calendar", title: "Calendar", colorHex: "#336699", allowsContentModifications: true)
    }
    private var otherWritableCalendar: CalendarDescriptor {
        .init(id: "other-calendar", title: "Other", colorHex: "#112233", allowsContentModifications: true)
    }
    private var readOnlyCalendar: CalendarDescriptor {
        .init(id: "calendar", title: "Calendar", colorHex: "#336699", allowsContentModifications: false)
    }
    private var writableList: ReminderListDescriptor {
        .init(id: "list", title: "Tasks", colorHex: "#CC8844", allowsContentModifications: true)
    }
    private var otherWritableList: ReminderListDescriptor {
        .init(id: "other-list", title: "Other", colorHex: "#443322", allowsContentModifications: true)
    }
    private var readOnlyList: ReminderListDescriptor {
        .init(id: "list", title: "Tasks", colorHex: "#CC8844", allowsContentModifications: false)
    }

    private func eventPreview(
        title: String = "Planning session",
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        destinationID: String? = "calendar",
        recurrence: RecurrenceRuleDraft? = nil,
        reminderDate: Date? = nil
    ) -> QuickEntryPreview {
        QuickEntryPreview(
            kind: .event,
            title: title,
            startDate: startDate ?? start,
            endDate: endDate ?? end,
            isAllDay: isAllDay,
            recurrence: recurrence,
            reminderDate: reminderDate,
            destinationID: destinationID
        )
    }

    private func taskPreview(
        title: String = "Submit report",
        dueDate: Date? = nil,
        dueHasTime: Bool = false,
        destinationID: String? = "list",
        recurrence: RecurrenceRuleDraft? = nil,
        reminderDate: Date? = nil
    ) -> QuickEntryPreview {
        QuickEntryPreview(
            kind: .task,
            title: title,
            dueDate: dueDate,
            dueHasTime: dueHasTime,
            recurrence: recurrence,
            reminderDate: reminderDate,
            destinationID: destinationID
        )
    }

    private func routinePreview(
        title: String = "Stretch",
        window: RoutineWindow? = .evening,
        weekdays: Set<Int> = [2, 4, 6],
        recurrence: RecurrenceRuleDraft? = nil,
        reminderDate: Date? = nil
    ) -> QuickEntryPreview {
        QuickEntryPreview(
            kind: .routine,
            title: title,
            routineWindow: window,
            weekdays: weekdays,
            recurrence: recurrence,
            reminderDate: reminderDate
        )
    }

    private func makeSubject(
        calendar: RouterCalendarSpy,
        reminders: RouterRemindersSpy,
        routines: RouterRoutineSpy,
        localCalendar: Calendar? = nil
    ) -> SaveRouter {
        SaveRouter(
            calendar: calendar,
            reminders: reminders,
            routines: routines,
            localCalendar: localCalendar ?? configuredCalendar(timeZoneID: "UTC")
        )
    }

    private func assertRejected(
        _ preview: QuickEntryPreview,
        as expected: QuickEntrySaveError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let calendar = RouterCalendarSpy()
        let reminders = RouterRemindersSpy()
        let routines = RouterRoutineSpy()
        let subject = makeSubject(calendar: calendar, reminders: reminders, routines: routines)

        assertSaveError(expected, saving: preview, with: subject, file: file, line: line)
        assertNoCreateAttempts(calendar, reminders, routines, file: file, line: line)
    }

    private func assertSaveError(
        _ expected: QuickEntrySaveError,
        saving preview: QuickEntryPreview,
        with subject: SaveRouter,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try subject.save(preview)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? QuickEntrySaveError, expected, file: file, line: line)
        }
    }

    private func assertProviderFailure(
        saving preview: QuickEntryPreview,
        with subject: SaveRouter,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try subject.save(preview)
            XCTFail("Expected provider failure", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? RouterProviderFailure, .write, file: file, line: line)
        }
    }

    private func assertNoCreateAttempts(
        _ calendar: RouterCalendarSpy,
        _ reminders: RouterRemindersSpy,
        _ routines: RouterRoutineSpy,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertCreateAttempts(
            event: 0,
            task: 0,
            routine: 0,
            calendar,
            reminders,
            routines,
            file: file,
            line: line
        )
    }

    private func assertCreateAttempts(
        event: Int,
        task: Int,
        routine: Int,
        _ calendar: RouterCalendarSpy,
        _ reminders: RouterRemindersSpy,
        _ routines: RouterRoutineSpy,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(calendar.createAttemptCount, event, file: file, line: line)
        XCTAssertEqual(reminders.createAttemptCount, task, file: file, line: line)
        XCTAssertEqual(routines.createAttemptCount, routine, file: file, line: line)
    }

    private func configuredCalendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func utcDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        configuredCalendar(timeZoneID: "UTC").date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}

private enum RouterProviderFailure: Error, Equatable {
    case write
}

@MainActor
private final class RouterCalendarSpy: CalendarServicing {
    var accessState: AccessState
    var descriptors: [CalendarDescriptor]
    let createID: String?
    let createError: Error?
    private(set) var createAttemptCount = 0
    private(set) var receivedDrafts: [EventDraft] = []

    init(
        accessState: AccessState = .granted,
        descriptors: [CalendarDescriptor] = [
            .init(id: "calendar", title: "Calendar", colorHex: "#336699", allowsContentModifications: true)
        ],
        createID: String? = "event-id",
        createError: Error? = nil
    ) {
        self.accessState = accessState
        self.descriptors = descriptors
        self.createID = createID
        self.createError = createError
    }

    func requestFullAccess() async -> AccessState { accessState }
    func calendars() -> [CalendarDescriptor] { accessState == .granted ? descriptors : [] }
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        XCTFail("SaveRouter must not fetch events")
        return []
    }
    func createEvent(_ draft: EventDraft) throws -> String? {
        createAttemptCount += 1
        receivedDrafts.append(draft)
        if let createError { throw createError }
        return createID
    }
    func event(id: String) -> CalendarEventSnapshot? {
        XCTFail("SaveRouter must not resolve event details")
        return nil
    }
    func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws {
        XCTFail("SaveRouter must never update an event")
    }
    func deleteEvent(id: String, scope: RecurrenceEditScope) throws {
        XCTFail("SaveRouter must never delete an event")
    }
}

@MainActor
private final class RouterRemindersSpy: RemindersServicing {
    var accessState: AccessState
    var descriptors: [ReminderListDescriptor]
    let createID: String?
    let createError: Error?
    private(set) var createAttemptCount = 0
    private(set) var receivedDrafts: [ReminderDraft] = []

    init(
        accessState: AccessState = .granted,
        descriptors: [ReminderListDescriptor] = [
            .init(id: "list", title: "Tasks", colorHex: "#CC8844", allowsContentModifications: true)
        ],
        createID: String? = "task-id",
        createError: Error? = nil
    ) {
        self.accessState = accessState
        self.descriptors = descriptors
        self.createID = createID
        self.createError = createError
    }

    func requestFullAccess() async -> AccessState { accessState }
    func lists() -> [ReminderListDescriptor] { accessState == .granted ? descriptors : [] }
    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] {
        XCTFail("SaveRouter must not fetch reminders")
        return []
    }
    func createReminder(_ draft: ReminderDraft) throws -> String? {
        createAttemptCount += 1
        receivedDrafts.append(draft)
        if let createError { throw createError }
        return createID
    }
    func setCompleted(id: String, completed: Bool) throws {
        XCTFail("SaveRouter must never complete a reminder")
    }
    func reminder(id: String) -> ReminderSnapshot? {
        XCTFail("SaveRouter must not resolve reminder details")
        return nil
    }
    func updateReminder(id: String, draft: ReminderDraft) throws {
        XCTFail("SaveRouter must never update a reminder")
    }
    func deleteReminder(id: String) throws {
        XCTFail("SaveRouter must never delete a reminder")
    }
}

@MainActor
private final class RouterRoutineSpy: RoutineRepository {
    let createID: UUID
    let createError: Error?
    private(set) var createAttemptCount = 0
    private(set) var receivedDrafts: [RoutineDraft] = []

    init(
        createID: UUID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
        createError: Error? = nil
    ) {
        self.createID = createID
        self.createError = createError
    }

    func list(includeArchived: Bool) throws -> [RoutineSnapshot] {
        XCTFail("SaveRouter must not list routines")
        return []
    }
    func create(_ draft: RoutineDraft) throws -> UUID {
        createAttemptCount += 1
        receivedDrafts.append(draft)
        if let createError { throw createError }
        return createID
    }
    func update(id: UUID, draft: RoutineDraft) throws {
        XCTFail("SaveRouter must never update a routine")
    }
    func setPaused(id: UUID, paused: Bool) throws {
        XCTFail("SaveRouter must never pause a routine")
    }
    func setArchived(id: UUID, archived: Bool) throws {
        XCTFail("SaveRouter must never archive a routine")
    }
    func delete(id: UUID) throws {
        XCTFail("SaveRouter must never delete a routine")
    }
    func setCompleted(routineID: UUID, day: LocalDay, completed: Bool) throws {
        XCTFail("SaveRouter must never complete a routine")
    }
    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool {
        XCTFail("SaveRouter must not read routine completion")
        return false
    }
    func completedDays(routineID: UUID) throws -> Set<LocalDay> {
        XCTFail("SaveRouter must not read routine completion history")
        return []
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
