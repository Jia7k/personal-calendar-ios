import XCTest
@testable import PersonalCalendar

@MainActor
final class SystemEventKitMutationBackingTests: XCTestCase {
    func testEventCreateRequiresAccessBeforeDestinationOrAllocation() {
        let driver = RecordingDriver(); driver.eventAccess = false

        assertThrows(.accessUnavailable) {
            _ = try self.backing(driver).createEvent(.init(draft: self.eventDraft(), destination: .defaultWritable))
        }

        XCTAssertEqual(driver.eventDestinationRequests.count, 0)
        XCTAssertEqual(driver.newEventCount, 0)
        assertNoEventWrite(driver)
    }

    func testEventCreateApplyFailureDiscardsWithoutSave() {
        let driver = RecordingDriver(); driver.eventHandle.applyError = TestFailure.expected

        assertThrows(.invalidDraft) {
            _ = try self.backing(driver).createEvent(.init(draft: self.eventDraft(), destination: .defaultWritable))
        }

        XCTAssertEqual(driver.eventHandle.applyCount, 1)
        XCTAssertEqual(driver.eventHandle.discardCount, 1)
        XCTAssertTrue(driver.eventHandle.saveCalls.isEmpty)
        XCTAssertEqual(driver.eventHandle.resetCount, 0)
    }

    func testEventCreateApplyPreservesTypedMutationError() {
        let driver = RecordingDriver(); driver.eventHandle.applyError = EventKitMutationError.invalidRecurrence

        assertThrows(.invalidRecurrence) {
            _ = try self.backing(driver).createEvent(.init(draft: self.eventDraft(), destination: .defaultWritable))
        }

        XCTAssertEqual(driver.eventHandle.discardCount, 1)
        XCTAssertTrue(driver.eventHandle.saveCalls.isEmpty)
    }

    func testEventCreateSaveFailureDiscardsAndMapsSaveError() {
        let driver = RecordingDriver(); driver.eventHandle.saveError = TestFailure.expected

        assertThrows(.saveFailed) {
            _ = try self.backing(driver).createEvent(.init(draft: self.eventDraft(), destination: .defaultWritable))
        }

        XCTAssertEqual(driver.eventHandle.discardCount, 1)
        XCTAssertEqual(driver.eventHandle.saveCalls, [.init(scope: .thisOccurrence, commit: true)])
    }

    func testEventCreateForwardsFullPatchUsesThisCommitAndReturnsSafeID() throws {
        let driver = RecordingDriver(); driver.eventHandle.savedIdentifier = "safe-event-id"
        var draft = eventDraft()
        draft.notes = "Notes"; draft.location = "Home"; draft.url = URL(string: "https://example.com")
        draft.alarms = .replace([-300, 0])
        draft.recurrence = .replace(.init(frequency: .daily, interval: 2, weekdays: [], endDate: nil))

        let id = try XCTUnwrap(try backing(driver).createEvent(.init(draft: draft, destination: .explicit("chosen"))))

        XCTAssertEqual(id, "safe-event-id")
        XCTAssertEqual(driver.eventDestinationRequests, [.create(.explicit("chosen"))])
        XCTAssertEqual(driver.eventHandle.patches, [.init(draft: draft, destinationID: "event-destination")])
        XCTAssertEqual(driver.eventHandle.saveCalls, [.init(scope: .thisOccurrence, commit: true)])
    }

    func testEventCreateTreatsNilAndBlankPostSaveIdentityAsSuccessfulWithoutAddress() throws {
        for identifier: String? in [nil, "", "   "] {
            let driver = RecordingDriver(); driver.eventHandle.savedIdentifier = identifier
            let result = try self.backing(driver).createEvent(.init(draft: self.eventDraft(), destination: .defaultWritable))

            XCTAssertNil(result)
            XCTAssertEqual(driver.eventHandle.saveCalls, [.init(scope: .thisOccurrence, commit: true)])
            XCTAssertEqual(driver.eventHandle.discardCount, 0)
        }
    }

    func testEventUpdateApplyFailureResetsOnceWithoutSave() {
        let driver = RecordingDriver(); driver.eventHandle.applyError = TestFailure.expected

        assertThrows(.invalidDraft) {
            try self.backing(driver).updateEvent(id: "event", request: .init(draft: self.eventDraft(), destination: .preserveCurrent, scope: .thisOccurrence))
        }

        XCTAssertEqual(driver.eventHandle.resetCount, 1)
        XCTAssertTrue(driver.eventHandle.saveCalls.isEmpty)
    }

    func testEventUpdateSaveFailureResetsOnce() {
        let driver = RecordingDriver(); driver.eventHandle.saveError = TestFailure.expected

        assertThrows(.saveFailed) {
            try self.backing(driver).updateEvent(id: "event", request: .init(draft: self.eventDraft(), destination: .preserveCurrent, scope: .thisOccurrence))
        }

        XCTAssertEqual(driver.eventHandle.resetCount, 1)
        XCTAssertEqual(driver.eventHandle.saveCalls, [.init(scope: .thisOccurrence, commit: true)])
    }

    func testEventUpdateUsesExactThisAndFutureScopesWithCommitTrue() throws {
        for scope in [RecurrenceEditScope.thisOccurrence, .futureOccurrences] {
            let driver = RecordingDriver(); driver.eventHandle.hasRecurrenceValue = true
            try backing(driver).updateEvent(id: "event", request: .init(draft: eventDraft(), destination: .preserveCurrent, scope: scope))
            XCTAssertEqual(driver.eventHandle.saveCalls, [.init(scope: scope, commit: true)])
        }
    }

    func testNonRecurringEventCanBecomeRecurringOnlyFromThisOccurrence() throws {
        let driver = RecordingDriver()
        var draft = eventDraft(); draft.recurrence = .replace(.init(frequency: .daily, interval: 1, weekdays: [], endDate: nil))

        try backing(driver).updateEvent(id: "event", request: .init(draft: draft, destination: .preserveCurrent, scope: .thisOccurrence))
        XCTAssertEqual(driver.eventHandle.saveCalls, [.init(scope: .thisOccurrence, commit: true)])

        let futureDriver = RecordingDriver()
        assertThrows(.invalidRecurrenceScope) {
            try self.backing(futureDriver).updateEvent(id: "event", request: .init(draft: draft, destination: .preserveCurrent, scope: .futureOccurrences))
        }
        assertNoEventWrite(futureDriver)
    }

    func testEventRemoveUsesExactScopesAndCommitTrue() throws {
        for scope in [RecurrenceEditScope.thisOccurrence, .futureOccurrences] {
            let driver = RecordingDriver(); driver.eventHandle.hasRecurrenceValue = true
            try backing(driver).removeEvent(id: "event", span: scope)
            XCTAssertEqual(driver.eventHandle.removeCalls, [.init(scope: scope, commit: true)])
        }
    }

    func testEventRemoveFailureMapsWithoutReset() {
        let driver = RecordingDriver(); driver.eventHandle.removeError = TestFailure.expected

        assertThrows(.removeFailed) { try self.backing(driver).removeEvent(id: "event", span: .thisOccurrence) }

        XCTAssertEqual(driver.eventHandle.removeCalls, [.init(scope: .thisOccurrence, commit: true)])
        XCTAssertEqual(driver.eventHandle.resetCount, 0)
    }

    func testEventMissingAndReadOnlyErrorsAcrossUpdateAndRemove() {
        let missing = RecordingDriver(); missing.eventLookupEnabled = false
        assertThrows(.itemNotFound) { try self.backing(missing).updateEvent(id: "missing", request: .init(draft: self.eventDraft(), destination: .preserveCurrent, scope: .thisOccurrence)) }
        assertThrows(.itemNotFound) { try self.backing(missing).removeEvent(id: "missing", span: .thisOccurrence) }
        assertNoEventWrite(missing)

        let readOnly = RecordingDriver(); readOnly.eventHandle.allowsModification = false
        assertThrows(.itemReadOnly) { try self.backing(readOnly).updateEvent(id: "event", request: .init(draft: self.eventDraft(), destination: .preserveCurrent, scope: .thisOccurrence)) }
        assertThrows(.itemReadOnly) { try self.backing(readOnly).removeEvent(id: "event", span: .thisOccurrence) }
        assertNoEventWrite(readOnly)
    }

    func testEventDestinationErrorsPreflightWithoutAllocationOrApply() {
        let createCases: [(CreateDestination, EventKitMutationError)] = [
            (.defaultWritable, .defaultUnavailable),
            (.explicit("missing"), .destinationMissing),
            (.explicit("read-only"), .destinationReadOnly)
        ]
        for (destination, error) in createCases {
            let createDriver = RecordingDriver(); createDriver.eventCreateDestinationError = error
            assertThrows(error) { _ = try self.backing(createDriver).createEvent(.init(draft: self.eventDraft(), destination: destination)) }
            XCTAssertEqual(createDriver.eventDestinationRequests, [.create(destination)])
            XCTAssertEqual(createDriver.newEventCount, 0)
            assertNoEventWrite(createDriver)
        }
        for error in [EventKitMutationError.destinationMissing, .destinationReadOnly] {
            let updateDriver = RecordingDriver(); updateDriver.eventUpdateDestinationError = error
            assertThrows(error) { try self.backing(updateDriver).updateEvent(id: "event", request: .init(draft: self.eventDraft(), destination: .explicit("bad"), scope: .thisOccurrence)) }
            assertNoEventWrite(updateDriver)
        }
    }

    func testInvalidEventInputsNeverResolveAllocateOrWrite() {
        var drafts = [eventDraft()]
        drafts[0].title = "  "
        var inverted = eventDraft(); inverted.end = inverted.start; drafts.append(inverted)
        var alarm = eventDraft(); alarm.alarms = .replace([.infinity]); drafts.append(alarm)
        var recurrence = eventDraft(); recurrence.recurrence = .replace(.init(frequency: .daily, interval: 0, weekdays: [], endDate: nil)); drafts.append(recurrence)

        for draft in drafts {
            let driver = RecordingDriver()
            let expected: EventKitMutationError = draft.recurrence == .preserve ? .invalidDraft : .invalidRecurrence
            assertThrows(expected) { _ = try self.backing(driver).createEvent(.init(draft: draft, destination: .defaultWritable)) }
            XCTAssertTrue(driver.eventDestinationRequests.isEmpty)
            XCTAssertEqual(driver.newEventCount, 0)
            assertNoEventWrite(driver)
        }
    }

    func testReminderCreateApplyFailureDiscardsWithoutSave() {
        let driver = RecordingDriver(); driver.reminderHandle.applyError = TestFailure.expected

        assertThrows(.invalidDraft) { _ = try self.backing(driver).createReminder(.init(draft: self.reminderDraft(), destination: .defaultWritable)) }

        XCTAssertEqual(driver.reminderHandle.applyCount, 1)
        XCTAssertEqual(driver.reminderHandle.discardCount, 1)
        XCTAssertTrue(driver.reminderHandle.saveCommits.isEmpty)
    }

    func testReminderCreateRejectsNonFiniteScheduleAndAlarmBeforeDestinationOrAllocation() {
        var invalidSchedule = reminderDraft()
        invalidSchedule.schedule = .replace(.init(date: Date(timeIntervalSinceReferenceDate: .nan), hasTime: true))
        var invalidAlarm = reminderDraft()
        invalidAlarm.alarm = .replace(Date(timeIntervalSinceReferenceDate: .infinity))

        for draft in [invalidSchedule, invalidAlarm] {
            let driver = RecordingDriver()
            assertThrows(.invalidDraft) {
                _ = try self.backing(driver).createReminder(.init(draft: draft, destination: .defaultWritable))
            }
            XCTAssertTrue(driver.reminderDestinationRequests.isEmpty)
            XCTAssertEqual(driver.newReminderCount, 0)
            assertNoReminderWrite(driver)
        }
    }

    func testReminderCreateSaveFailureDiscardsAndMapsSaveError() {
        let driver = RecordingDriver(); driver.reminderHandle.saveError = TestFailure.expected

        assertThrows(.saveFailed) { _ = try self.backing(driver).createReminder(.init(draft: self.reminderDraft(), destination: .defaultWritable)) }

        XCTAssertEqual(driver.reminderHandle.discardCount, 1)
        XCTAssertEqual(driver.reminderHandle.saveCommits, [true])
    }

    func testReminderCreateForwardsPatchCommitsAndReturnsID() throws {
        let driver = RecordingDriver(); driver.reminderHandle.savedIdentifier = "safe-reminder"
        var draft = reminderDraft(); draft.notes = "Notes"; draft.alarm = .replace(Date(timeIntervalSince1970: 1_000))

        let id = try XCTUnwrap(try backing(driver).createReminder(.init(draft: draft, destination: .explicit("chosen"))))

        XCTAssertEqual(id, "safe-reminder")
        XCTAssertEqual(driver.reminderDestinationRequests, [.create(.explicit("chosen"))])
        XCTAssertEqual(driver.reminderHandle.patches.first?.draft, draft)
        XCTAssertEqual(driver.reminderHandle.patches.first?.destinationID, "reminder-destination")
        XCTAssertEqual(driver.reminderHandle.saveCommits, [true])
    }

    func testReminderCreateTreatsNilAndBlankPostSaveIdentityAsSuccessfulWithoutAddress() throws {
        for identifier: String? in [nil, "", "   "] {
            let driver = RecordingDriver(); driver.reminderHandle.savedIdentifier = identifier
            let result = try self.backing(driver).createReminder(.init(draft: self.reminderDraft(), destination: .defaultWritable))

            XCTAssertNil(result)
            XCTAssertEqual(driver.reminderHandle.saveCommits, [true])
            XCTAssertEqual(driver.reminderHandle.discardCount, 0)
        }
    }

    func testReminderUpdateApplyAndSaveFailuresResetExactlyOnce() {
        let applyDriver = RecordingDriver(); applyDriver.reminderHandle.applyError = TestFailure.expected
        assertThrows(.invalidDraft) { try self.backing(applyDriver).updateReminder(id: "reminder", request: .init(draft: self.reminderDraft(), destination: .preserveCurrent)) }
        XCTAssertEqual(applyDriver.reminderHandle.resetCount, 1)
        XCTAssertTrue(applyDriver.reminderHandle.saveCommits.isEmpty)

        let saveDriver = RecordingDriver(); saveDriver.reminderHandle.saveError = TestFailure.expected
        assertThrows(.saveFailed) { try self.backing(saveDriver).updateReminder(id: "reminder", request: .init(draft: self.reminderDraft(), destination: .preserveCurrent)) }
        XCTAssertEqual(saveDriver.reminderHandle.resetCount, 1)
        XCTAssertEqual(saveDriver.reminderHandle.saveCommits, [true])
    }

    func testReminderUpdateRejectsNonFiniteScheduleAndAlarmBeforeDestinationOrWrite() {
        var invalidSchedule = reminderDraft()
        invalidSchedule.schedule = .replace(.init(date: Date(timeIntervalSinceReferenceDate: -Double.infinity), hasTime: false))
        var invalidAlarm = reminderDraft()
        invalidAlarm.alarm = .replace(Date(timeIntervalSinceReferenceDate: .nan))

        for draft in [invalidSchedule, invalidAlarm] {
            let driver = RecordingDriver()
            assertThrows(.invalidDraft) {
                try self.backing(driver).updateReminder(id: "reminder", request: .init(draft: draft, destination: .explicit("chosen")))
            }
            XCTAssertTrue(driver.reminderDestinationRequests.isEmpty)
            assertNoReminderWrite(driver)
        }
    }

    // Break caught: preserving an unscheduled recurring reminder would retain an
    // invalid EventKit state unless recurrence is explicitly cleared or a due date is supplied.
    func testRecurringUnscheduledReminderCannotPreserveScheduleAndRecurrenceBeforeWrite() {
        let driver = RecordingDriver()
        driver.reminderHandle.hasRecurrence = true
        var draft = reminderDraft()
        draft.schedule = .preserve(current: nil)
        draft.recurrence = .preserve

        assertThrows(.invalidDraft) {
            try backing(driver).updateReminder(id: "reminder", request: .init(draft: draft, destination: .preserveCurrent))
        }

        assertNoReminderDestinationApplyOrSave(driver)
    }

    func testRecurringUnscheduledReminderCanClearRecurrenceWhilePreservingSchedule() throws {
        let driver = RecordingDriver()
        driver.reminderHandle.hasRecurrence = true
        var draft = reminderDraft()
        draft.schedule = .preserve(current: nil)
        draft.recurrence = .clear

        try backing(driver).updateReminder(id: "reminder", request: .init(draft: draft, destination: .preserveCurrent))

        XCTAssertEqual(driver.reminderDestinationRequests, [.update(.preserveCurrent)])
        XCTAssertEqual(driver.reminderHandle.applyCount, 1)
        XCTAssertEqual(driver.reminderHandle.patches.first?.schedule, .preserve)
        XCTAssertEqual(driver.reminderHandle.saveCommits, [true])
    }

    func testRecurringUnscheduledReminderCanReplaceDueWhilePreservingRecurrence() throws {
        let driver = RecordingDriver()
        driver.reminderHandle.hasRecurrence = true
        let due = ReminderScheduleValue(date: Date(timeIntervalSince1970: 7_000), hasTime: true)
        var draft = reminderDraft()
        draft.schedule = .replace(due)
        draft.recurrence = .preserve

        try backing(driver).updateReminder(id: "reminder", request: .init(draft: draft, destination: .preserveCurrent))

        XCTAssertEqual(driver.reminderDestinationRequests, [.update(.preserveCurrent)])
        XCTAssertEqual(driver.reminderHandle.applyCount, 1)
        XCTAssertEqual(driver.reminderHandle.patches.first?.schedule, .replace(due: due, start: due))
        XCTAssertEqual(driver.reminderHandle.saveCommits, [true])
    }

    func testReminderUpdateRejectsNonFinitePreservedDueBeforeDestinationApplyOrSave() {
        let driver = RecordingDriver()
        driver.reminderHandle.currentSchedule = .init(date: Date(timeIntervalSinceReferenceDate: .infinity), hasTime: true)
        var draft = reminderDraft()
        draft.schedule = .preserve(current: nil)

        assertThrows(.invalidDraft) {
            try backing(driver).updateReminder(id: "reminder", request: .init(draft: draft, destination: .preserveCurrent))
        }

        assertNoReminderDestinationApplyOrSave(driver)
    }

    func testReminderUpdateRejectsNonFinitePreservedStartBeforeDestinationApplyOrSave() {
        let driver = RecordingDriver()
        driver.reminderHandle.currentStartSchedule = .init(date: Date(timeIntervalSinceReferenceDate: .nan), hasTime: true)
        var draft = reminderDraft()
        draft.schedule = .preserve(current: nil)

        assertThrows(.invalidDraft) {
            try backing(driver).updateReminder(id: "reminder", request: .init(draft: draft, destination: .preserveCurrent))
        }

        assertNoReminderDestinationApplyOrSave(driver)
    }

    func testReminderUpdatePreservesAndChangesSchedulePrecisely() throws {
        let due = ReminderScheduleValue(date: Date(timeIntervalSince1970: 4_000), hasTime: true)
        let start = ReminderScheduleValue(date: Date(timeIntervalSince1970: 3_000), hasTime: true)

        let preserveDriver = RecordingDriver(); preserveDriver.reminderHandle.currentSchedule = due; preserveDriver.reminderHandle.currentStartSchedule = start
        var preserveDraft = reminderDraft(); preserveDraft.schedule = .preserve(current: nil)
        try backing(preserveDriver).updateReminder(id: "reminder", request: .init(draft: preserveDraft, destination: .preserveCurrent))
        XCTAssertEqual(preserveDriver.reminderHandle.patches.first?.schedule, .preserve)

        let sameDriver = RecordingDriver(); sameDriver.reminderHandle.currentSchedule = due; sameDriver.reminderHandle.currentStartSchedule = start
        var sameDraft = reminderDraft(); sameDraft.schedule = .replace(due)
        try backing(sameDriver).updateReminder(id: "reminder", request: .init(draft: sameDraft, destination: .preserveCurrent))
        XCTAssertEqual(sameDriver.reminderHandle.patches.first?.schedule, .replace(due: due, start: start))

        let changed = ReminderScheduleValue(date: Date(timeIntervalSince1970: 8_000), hasTime: true)
        let changedDriver = RecordingDriver(); changedDriver.reminderHandle.currentSchedule = due; changedDriver.reminderHandle.currentStartSchedule = start
        var changedDraft = reminderDraft(); changedDraft.schedule = .replace(changed)
        try backing(changedDriver).updateReminder(id: "reminder", request: .init(draft: changedDraft, destination: .preserveCurrent))
        XCTAssertEqual(changedDriver.reminderHandle.patches.first?.schedule, .replace(due: changed, start: changed))
        XCTAssertEqual(changedDriver.reminderHandle.saveCommits, [true])
    }

    func testReminderSameDueWithMissingStartFillsStart() throws {
        let due = ReminderScheduleValue(date: Date(timeIntervalSince1970: 4_000), hasTime: true)
        let driver = RecordingDriver(); driver.reminderHandle.currentSchedule = due
        var draft = reminderDraft(); draft.schedule = .replace(due)

        try backing(driver).updateReminder(id: "reminder", request: .init(draft: draft, destination: .preserveCurrent))

        XCTAssertEqual(driver.reminderHandle.patches.first?.schedule, .replace(due: due, start: due))
    }

    func testReminderDateOnlyAndTimedMidnightTransitionsBothAlignStartToDue() throws {
        let midnight = Date(timeIntervalSince1970: 1_775_952_000)
        let transitions: [(ReminderScheduleValue, ReminderScheduleValue)] = [
            (.init(date: midnight, hasTime: false), .init(date: midnight, hasTime: true)),
            (.init(date: midnight, hasTime: true), .init(date: midnight, hasTime: false))
        ]

        for (current, replacement) in transitions {
            let driver = RecordingDriver()
            driver.reminderHandle.currentSchedule = current
            driver.reminderHandle.currentStartSchedule = .init(date: midnight.addingTimeInterval(-86_400), hasTime: current.hasTime)
            var draft = reminderDraft(); draft.schedule = .replace(replacement)

            try backing(driver).updateReminder(id: "reminder", request: .init(draft: draft, destination: .preserveCurrent))

            XCTAssertEqual(driver.reminderHandle.patches.first?.schedule, .replace(due: replacement, start: replacement))
        }
    }

    func testReminderRecurrenceAndScheduleResultingStateRules() throws {
        let clearInvalid = RecordingDriver(); clearInvalid.reminderHandle.hasRecurrence = true
        var clearDraft = reminderDraft(); clearDraft.schedule = .clear; clearDraft.recurrence = .preserve
        assertThrows(.invalidDraft) { try self.backing(clearInvalid).updateReminder(id: "reminder", request: .init(draft: clearDraft, destination: .preserveCurrent)) }
        assertNoReminderWrite(clearInvalid)

        let clearValid = RecordingDriver(); clearValid.reminderHandle.hasRecurrence = true
        clearDraft.recurrence = .clear
        try backing(clearValid).updateReminder(id: "reminder", request: .init(draft: clearDraft, destination: .preserveCurrent))
        XCTAssertEqual(clearValid.reminderHandle.patches.first?.schedule, .clear)

        let replaceInvalid = RecordingDriver()
        var replaceDraft = reminderDraft(); replaceDraft.schedule = .clear
        replaceDraft.recurrence = .replace(.init(frequency: .daily, interval: 1, weekdays: [], endDate: nil))
        assertThrows(.invalidDraft) {
            try self.backing(replaceInvalid).updateReminder(id: "reminder", request: .init(draft: replaceDraft, destination: .preserveCurrent))
        }
        assertNoReminderWrite(replaceInvalid)

        let preserveDue = RecordingDriver(); preserveDue.reminderHandle.currentSchedule = .init(date: Date(timeIntervalSince1970: 9_000), hasTime: true)
        var recurringDraft = reminderDraft(); recurringDraft.schedule = .preserve(current: nil)
        recurringDraft.recurrence = .replace(.init(frequency: .weekly, interval: 1, weekdays: [2], endDate: nil))
        try backing(preserveDue).updateReminder(id: "reminder", request: .init(draft: recurringDraft, destination: .preserveCurrent))
        XCTAssertEqual(preserveDue.reminderHandle.saveCommits, [true])
    }

    func testReminderRemoveSuccessAndFailureUseCommitWithoutReset() throws {
        let success = RecordingDriver()
        try backing(success).removeReminder(id: "reminder")
        XCTAssertEqual(success.reminderHandle.removeCommits, [true])

        let failure = RecordingDriver(); failure.reminderHandle.removeError = TestFailure.expected
        assertThrows(.removeFailed) { try self.backing(failure).removeReminder(id: "reminder") }
        XCTAssertEqual(failure.reminderHandle.removeCommits, [true])
        XCTAssertEqual(failure.reminderHandle.resetCount, 0)
    }

    func testCompletionApplyAndSaveFailuresResetExactlyOnce() {
        let applyDriver = RecordingDriver(); applyDriver.reminderHandle.completionError = TestFailure.expected
        assertThrows(.invalidDraft) { try self.backing(applyDriver).setReminderCompleted(id: "reminder", completed: true) }
        XCTAssertEqual(applyDriver.reminderHandle.resetCount, 1)
        XCTAssertTrue(applyDriver.reminderHandle.saveCommits.isEmpty)

        let saveDriver = RecordingDriver(); saveDriver.reminderHandle.saveError = TestFailure.expected
        assertThrows(.saveFailed) { try self.backing(saveDriver).setReminderCompleted(id: "reminder", completed: false) }
        XCTAssertEqual(saveDriver.reminderHandle.completedValues, [false])
        XCTAssertEqual(saveDriver.reminderHandle.saveCommits, [true])
        XCTAssertEqual(saveDriver.reminderHandle.resetCount, 1)
    }

    func testCompletionSuccessUsesCommittedSave() throws {
        let driver = RecordingDriver()
        try backing(driver).setReminderCompleted(id: "reminder", completed: true)
        XCTAssertEqual(driver.reminderHandle.completedValues, [true])
        XCTAssertEqual(driver.reminderHandle.saveCommits, [true])
        XCTAssertEqual(driver.reminderHandle.resetCount, 0)
    }

    func testReminderMissingAndReadOnlyErrorsAcrossRemoveAndCompletion() {
        let missing = RecordingDriver(); missing.reminderLookupEnabled = false
        assertThrows(.itemNotFound) { try self.backing(missing).removeReminder(id: "missing") }
        assertThrows(.itemNotFound) { try self.backing(missing).setReminderCompleted(id: "missing", completed: true) }
        assertNoReminderWrite(missing)

        let readOnly = RecordingDriver(); readOnly.reminderHandle.allowsModification = false
        assertThrows(.itemReadOnly) { try self.backing(readOnly).removeReminder(id: "reminder") }
        assertThrows(.itemReadOnly) { try self.backing(readOnly).setReminderCompleted(id: "reminder", completed: true) }
        assertNoReminderWrite(readOnly)
    }

    func testReminderDestinationErrorsPreflightWithoutAllocationOrApply() {
        let createCases: [(CreateDestination, EventKitMutationError)] = [
            (.defaultWritable, .defaultUnavailable),
            (.explicit("missing"), .destinationMissing),
            (.explicit("read-only"), .destinationReadOnly)
        ]
        for (destination, error) in createCases {
            let createDriver = RecordingDriver(); createDriver.reminderCreateDestinationError = error
            assertThrows(error) { _ = try self.backing(createDriver).createReminder(.init(draft: self.reminderDraft(), destination: destination)) }
            XCTAssertEqual(createDriver.reminderDestinationRequests, [.create(destination)])
            XCTAssertEqual(createDriver.newReminderCount, 0)
            assertNoReminderWrite(createDriver)
        }
        for error in [EventKitMutationError.destinationMissing, .destinationReadOnly] {
            let updateDriver = RecordingDriver(); updateDriver.reminderUpdateDestinationError = error
            assertThrows(error) { try self.backing(updateDriver).updateReminder(id: "reminder", request: .init(draft: self.reminderDraft(), destination: .explicit("bad"))) }
            assertNoReminderWrite(updateDriver)
        }
    }

    func testGregorianBuilderHandlesDateOnlyAndDSTWithoutGlobalTimeZoneMutation() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var source = Calendar(identifier: .iso8601); source.timeZone = zone
        let date = try XCTUnwrap(source.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30)))

        let timed = ReminderDueComponentBuilder.components(for: date, dueHasTime: true, preferredCalendar: source)
        let dateOnly = ReminderDueComponentBuilder.components(for: date, dueHasTime: false, preferredCalendar: source)

        XCTAssertEqual(timed.calendar?.identifier, .gregorian)
        XCTAssertEqual(timed.timeZone, zone)
        XCTAssertEqual(timed.year, 2026); XCTAssertEqual(timed.month, 3); XCTAssertEqual(timed.day, 8)
        XCTAssertEqual(timed.hour, 3); XCTAssertEqual(timed.minute, 30)
        XCTAssertEqual(dateOnly.year, 2026); XCTAssertEqual(dateOnly.month, 3); XCTAssertEqual(dateOnly.day, 8)
        XCTAssertNil(dateOnly.hour); XCTAssertNil(dateOnly.minute)
    }

    private func backing(_ driver: RecordingDriver) -> SystemEventKitMutationBacking { .init(driver: driver) }
    private func eventDraft() -> EventDraft {
        .init(title: "Event", start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200), isAllDay: false, calendarID: nil)
    }
    private func reminderDraft() -> ReminderDraft {
        .init(title: "Task", notes: nil, dueDate: Date(timeIntervalSince1970: 4_000), dueHasTime: true, priority: 0)
    }
    private func assertThrows(
        _ expected: EventKitMutationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? EventKitMutationError, expected, file: file, line: line)
        }
    }
    private func assertNoEventWrite(_ driver: RecordingDriver, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(driver.eventHandle.applyCount, 0, file: file, line: line)
        XCTAssertTrue(driver.eventHandle.saveCalls.isEmpty, file: file, line: line)
        XCTAssertTrue(driver.eventHandle.removeCalls.isEmpty, file: file, line: line)
    }
    private func assertNoReminderWrite(_ driver: RecordingDriver, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(driver.reminderHandle.applyCount, 0, file: file, line: line)
        XCTAssertTrue(driver.reminderHandle.saveCommits.isEmpty, file: file, line: line)
        XCTAssertTrue(driver.reminderHandle.removeCommits.isEmpty, file: file, line: line)
        XCTAssertTrue(driver.reminderHandle.completedValues.isEmpty, file: file, line: line)
    }
    private func assertNoReminderDestinationApplyOrSave(_ driver: RecordingDriver, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(driver.reminderDestinationRequests.count, 0, file: file, line: line)
        XCTAssertEqual(driver.reminderHandle.applyCount, 0, file: file, line: line)
        XCTAssertEqual(driver.reminderHandle.saveCommits.count, 0, file: file, line: line)
    }
    private enum TestFailure: Error { case expected }
}

private enum DestinationRequest: Equatable {
    case create(CreateDestination)
    case update(UpdateDestination)
}
private struct EventStoreCall: Equatable {
    let scope: RecurrenceEditScope
    let commit: Bool
}

@MainActor
private final class RecordingDriver: EventKitStoreDriving {
    var eventAccess = true
    var reminderAccess = true
    var eventLookupEnabled = true
    var reminderLookupEnabled = true
    var eventCreateDestinationError: Error?
    var eventUpdateDestinationError: Error?
    var reminderCreateDestinationError: Error?
    var reminderUpdateDestinationError: Error?
    let eventHandle = RecordingEventHandle()
    let reminderHandle = RecordingReminderHandle()
    var newEventCount = 0
    var newReminderCount = 0
    var eventDestinationRequests: [DestinationRequest] = []
    var reminderDestinationRequests: [DestinationRequest] = []

    func eventAccessGranted() -> Bool { eventAccess }
    func reminderAccessGranted() -> Bool { reminderAccess }
    func event(id: String) -> (any EventMutationHandling)? { eventLookupEnabled ? eventHandle : nil }
    func reminder(id: String) -> (any ReminderMutationHandling)? { reminderLookupEnabled ? reminderHandle : nil }
    func newEvent() -> any EventMutationHandling { newEventCount += 1; return eventHandle }
    func newReminder() -> any ReminderMutationHandling { newReminderCount += 1; return reminderHandle }
    func resolveEventDestination(_ destination: CreateDestination) throws -> String {
        eventDestinationRequests.append(.create(destination)); if let eventCreateDestinationError { throw eventCreateDestinationError }; return "event-destination"
    }
    func resolveEventDestination(_ destination: UpdateDestination) throws -> String? {
        eventDestinationRequests.append(.update(destination)); if let eventUpdateDestinationError { throw eventUpdateDestinationError }; return destination == .preserveCurrent ? nil : "event-destination"
    }
    func resolveReminderDestination(_ destination: CreateDestination) throws -> String {
        reminderDestinationRequests.append(.create(destination)); if let reminderCreateDestinationError { throw reminderCreateDestinationError }; return "reminder-destination"
    }
    func resolveReminderDestination(_ destination: UpdateDestination) throws -> String? {
        reminderDestinationRequests.append(.update(destination)); if let reminderUpdateDestinationError { throw reminderUpdateDestinationError }; return destination == .preserveCurrent ? nil : "reminder-destination"
    }
}

@MainActor
private final class RecordingEventHandle: EventMutationHandling {
    var allowsModification = true
    var hasRecurrenceValue = false
    var hasRecurrence: Bool { hasRecurrenceValue }
    var savedIdentifier: String? = "created-event"
    var applyError: Error?
    var saveError: Error?
    var removeError: Error?
    var applyCount = 0
    var patches: [PreparedEventPatch] = []
    var saveCalls: [EventStoreCall] = []
    var removeCalls: [EventStoreCall] = []
    var resetCount = 0
    var discardCount = 0

    func apply(_ patch: PreparedEventPatch) throws { applyCount += 1; if let applyError { throw applyError }; patches.append(patch) }
    func save(scope: RecurrenceEditScope, commit: Bool) throws { saveCalls.append(.init(scope: scope, commit: commit)); if let saveError { throw saveError } }
    func remove(scope: RecurrenceEditScope, commit: Bool) throws { removeCalls.append(.init(scope: scope, commit: commit)); if let removeError { throw removeError } }
    func reset() { resetCount += 1 }
    func discardNewItem() { discardCount += 1 }
}

@MainActor
private final class RecordingReminderHandle: ReminderMutationHandling {
    var allowsModification = true
    var hasRecurrence = false
    var currentSchedule: ReminderScheduleValue?
    var currentStartSchedule: ReminderScheduleValue?
    var savedIdentifier: String? = "created-reminder"
    var applyError: Error?
    var completionError: Error?
    var saveError: Error?
    var removeError: Error?
    var applyCount = 0
    var patches: [PreparedReminderPatch] = []
    var completedValues: [Bool] = []
    var saveCommits: [Bool] = []
    var removeCommits: [Bool] = []
    var resetCount = 0
    var discardCount = 0

    func apply(_ patch: PreparedReminderPatch) throws { applyCount += 1; if let applyError { throw applyError }; patches.append(patch) }
    func setCompleted(_ completed: Bool) throws { if let completionError { throw completionError }; completedValues.append(completed) }
    func save(commit: Bool) throws { saveCommits.append(commit); if let saveError { throw saveError } }
    func remove(commit: Bool) throws { removeCommits.append(commit); if let removeError { throw removeError } }
    func reset() { resetCount += 1 }
    func discardNewItem() { discardCount += 1 }
}
