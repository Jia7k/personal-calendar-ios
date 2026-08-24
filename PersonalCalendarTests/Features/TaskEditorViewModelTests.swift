import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class TaskEditorViewModelTests: XCTestCase {
    private let due = Date(timeIntervalSince1970: 1_700_000_000)
    private let alarm = Date(timeIntervalSince1970: 1_700_003_600)
    private let weekly = RecurrenceRuleDraft(frequency: .weekly, interval: 1, weekdays: [2, 4], endDate: nil)

    func testSaveEligibilityRejectsInvalidKnownTaskFormValuesWithoutProviderLookupsOrWrites() {
        let snapshot = reminder(recurrence: .editable(weekly))
        let service = RecordingRemindersService(reminders: [snapshot])
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: service)
        let lookupsAfterCreation = service.reminderLookupCount

        XCTAssertTrue(subject.canSave)

        subject.form.title = " \n "
        XCTAssertFalse(subject.canSave)
        subject.form.title = "Buy milk"
        subject.form.priority = 10
        XCTAssertFalse(subject.canSave)
        subject.form.priority = 1
        subject.form.schedule = .replace(.init(date: Date(timeIntervalSinceReferenceDate: .infinity), hasTime: true))
        XCTAssertFalse(subject.canSave)
        subject.form.schedule = .preserve(current: .init(date: due, hasTime: true))
        subject.form.alarm = .replace(Date(timeIntervalSinceReferenceDate: .infinity))
        XCTAssertFalse(subject.canSave)
        subject.form.alarm = .preserve
        subject.form.recurrence = .replace(.init(frequency: .weekly, interval: 0, weekdays: [], endDate: nil))
        XCTAssertFalse(subject.canSave)
        subject.form.recurrence = .replace(.init(frequency: .daily, interval: 1, weekdays: [], endDate: due.addingTimeInterval(-1)))
        XCTAssertFalse(subject.canSave)
        subject.form.recurrence = .replace(.init(frequency: .weekly, interval: 2, weekdays: [2], endDate: due))
        XCTAssertTrue(subject.canSave)
        XCTAssertEqual(service.reminderLookupCount, lookupsAfterCreation)
        XCTAssertTrue(service.createCalls.isEmpty)
        XCTAssertTrue(service.updateCalls.isEmpty)
    }

    func testSaveEligibilityRejectsRecurringProviderTaskWithPreservedNilSchedule() {
        let snapshot = reminderWithoutDue(recurrence: .editable(weekly))
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: RecordingRemindersService(reminders: [snapshot]))

        XCTAssertEqual(subject.form.schedule, .preserve(current: nil))
        XCTAssertEqual(subject.form.recurrence, .preserve)
        XCTAssertFalse(subject.canSave)
    }

    // Break caught: loading an existing task must not convert provider values into a replacement intent.
    func testSnapshotSeedsLosslessPreserveFormIncludingScheduleAlarmAndUnsupportedRecurrence() {
        let snapshot = reminder(recurrence: .unsupported(summary: "Every second weekday"), alarm: .unsupported(summary: "Provider alarm"))
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: RecordingRemindersService(reminders: [snapshot]))

        XCTAssertEqual(subject.form.schedule, .preserve(current: .init(date: due, hasTime: true)))
        XCTAssertEqual(subject.form.alarm, .preserve)
        XCTAssertEqual(subject.form.recurrence, .preserve)
        XCTAssertEqual(subject.providerAlarmSummary, "Provider alarm")
        XCTAssertEqual(subject.providerRecurrenceSummary, "Every second weekday")
    }

    // Break caught: the UI cannot describe supported provider values while preserve intent remains selected.
    func testEditExposesExactProviderSnapshotsAndCurrentDestinationWhileMutationIntentsPreserve() {
        let snapshot = reminder(listID: "provider-list", listTitle: "Provider List", recurrence: .editable(weekly), alarm: .editable(alarm))
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: RecordingRemindersService(reminders: [snapshot]))

        XCTAssertEqual(subject.providerAlarmSnapshot, .editable(alarm))
        XCTAssertEqual(subject.providerRecurrenceSnapshot, .editable(weekly))
        XCTAssertEqual(subject.destination, .preserveCurrent(id: "provider-list", title: "Provider List"))
        XCTAssertEqual(subject.form.alarm, .preserve)
        XCTAssertEqual(subject.form.recurrence, .preserve)
    }

    // Break caught: a title-only edit must erase due-date metadata, alarm, or recurrence.
    func testTitleOnlyEditMaterializesEveryUntouchedProviderValueAsPreserve() async {
        let snapshot = reminder(recurrence: .editable(weekly), alarm: .editable(alarm))
        let service = RecordingRemindersService(reminders: [snapshot])
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: service)
        subject.form.title = "Buy oat milk"

        await subject.requestSave()

        XCTAssertEqual(service.updateCalls.single?.draft.title, "Buy oat milk")
        XCTAssertEqual(service.updateCalls.single?.draft.schedule, .preserve(current: .init(date: due, hasTime: true)))
        XCTAssertEqual(service.updateCalls.single?.draft.alarm, .preserve)
        XCTAssertEqual(service.updateCalls.single?.draft.recurrence, .preserve)
    }

    // Break caught: a create form can accidentally send preserve without a provider value.
    func testCreateStartsWithSystemDefaultAndAnExplicitClearSchedule() {
        let subject = TaskEditorViewModel.creating(service: RecordingRemindersService())

        XCTAssertEqual(subject.form.listID, nil)
        XCTAssertEqual(subject.form.schedule, .clear)
        XCTAssertEqual(subject.destination, .systemDefault)
    }

    // Break caught: a stale saved default can silently replace the system default or descriptor order.
    func testCreateSeedsOnlyACurrentlyWritableSavedDefault() {
        let writable = list("saved", writable: true)
        let subject = TaskEditorViewModel.creating(
            service: RecordingRemindersService(lists: [list("first", writable: true), writable]),
            savedDefaultListID: "saved"
        )

        XCTAssertEqual(subject.form.listID, "saved")
        XCTAssertEqual(subject.destination, .explicit(id: "saved", title: "saved"))
    }

    // Break caught: an existing task may be unintentionally moved when its old list is no longer enumerated.
    func testEditStartsWithPreserveCurrentDestinationAndCanExplicitlyMove() async {
        let snapshot = reminder(listID: "old", listTitle: "Old")
        let service = RecordingRemindersService(reminders: [snapshot], lists: [list("new", writable: true)])
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: service)
        XCTAssertEqual(subject.form.listID, nil)
        XCTAssertEqual(subject.destination, .preserveCurrent(id: "old", title: "Old"))

        subject.selectDestination(.explicit(id: "new"))
        await subject.requestSave()

        XCTAssertEqual(service.updateCalls.single?.draft.listID, "new")
    }

    // Break caught: nil destination is changed outside the model, leaving semantic destination state stale.
    func testAuthoritativeDestinationSelectionRestoresSystemDefaultForCreateAndPreserveCurrentForEdit() async {
        let lists = [list("inbox", writable: true), list("work", writable: true)]
        let createService = RecordingRemindersService(lists: lists)
        let create = TaskEditorViewModel.creating(service: createService)
        create.form.title = "Create destination"
        create.selectDestination(.explicit(id: "work"))
        create.selectDestination(.nilDestination)
        await create.requestSave()

        XCTAssertEqual(create.destination, .systemDefault)
        XCTAssertNil(createService.createCalls.single?.listID)

        let snapshot = reminder(listID: "inbox", listTitle: "Inbox")
        let editService = RecordingRemindersService(reminders: [snapshot], lists: lists)
        let edit = TaskEditorViewModel.editing(reminderID: snapshot.id, service: editService)
        edit.selectDestination(.explicit(id: "work"))
        edit.selectDestination(.nilDestination)
        await edit.requestSave()

        XCTAssertEqual(edit.destination, .preserveCurrent(id: "inbox", title: "Inbox"))
        XCTAssertNil(editService.updateCalls.single?.draft.listID)
    }

    // Break caught: a recurring task can be saved with no effective due date.
    func testRecurringReminderWithoutEffectiveDueDateIsValidationFailureWithZeroWrites() async {
        let snapshot = reminder(recurrence: .editable(weekly))
        let service = RecordingRemindersService(reminders: [snapshot])
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: service)
        subject.form.schedule = .clear

        await subject.requestSave()

        XCTAssertEqual(subject.phase, .failed(.save, .validation))
        XCTAssertTrue(service.updateCalls.isEmpty)
    }

    // Break caught: preserving a recurring provider item with no current due date bypasses the due invariant.
    func testRecurringReminderWithPreservedNilScheduleAndRecurrencePerformsZeroWrites() async {
        let snapshot = reminderWithoutDue(recurrence: .editable(weekly))
        let service = RecordingRemindersService(reminders: [snapshot])
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: service)

        XCTAssertEqual(subject.form.schedule, .preserve(current: nil))
        XCTAssertEqual(subject.form.recurrence, .preserve)
        await subject.requestSave()

        XCTAssertEqual(subject.phase, .failed(.save, .validation))
        XCTAssertTrue(service.updateCalls.isEmpty)
    }

    // Break caught: validation trusts cached nonrecurrence after the provider item becomes recurring.
    func testLiveTransitionToRecurringWithPreservedNilScheduleRevalidatesAndPerformsZeroWrites() async {
        let original = reminderWithoutDue()
        let service = RecordingRemindersService(reminders: [original])
        let subject = TaskEditorViewModel.editing(reminderID: original.id, service: service)
        service.reminders = [reminderWithoutDue(recurrence: .editable(weekly))]

        await subject.requestSave()

        XCTAssertEqual(subject.phase, .failed(.save, .validation))
        XCTAssertTrue(service.updateCalls.isEmpty)
    }

    // Break caught: reminder editing may incorrectly expose event occurrence/future scope.
    func testRecurringReminderHasNoOccurrenceScopeAndExplainsProviderSemantics() {
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: RecordingRemindersService(reminders: [reminder(recurrence: .editable(weekly))]))

        XCTAssertNil(subject.recurrenceScopeOptions)
        XCTAssertEqual(subject.recurringDetailExplanation, "Only the current incomplete reminder occurrence is shown. Completing it may reveal the next occurrence supplied by Apple Reminders.")
        XCTAssertEqual(subject.recurringDeleteExplanation, "Deleting this task removes the repeating reminder.")
    }

    // Break caught: destructive task deletion can occur without an explicit confirmation.
    func testEveryDeleteAttemptAndRetryRequiresFreshDestructiveConfirmation() async {
        let service = RecordingRemindersService(reminders: [reminder()], deleteErrors: [TestFailure.save, nil])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)

        subject.requestDelete()
        XCTAssertEqual(subject.phase, .confirming(.delete))
        subject.confirm()
        XCTAssertEqual(service.deleteCalls, ["task"])
        XCTAssertEqual(subject.phase, .failed(.delete, .retryableWrite))

        await subject.retry()
        XCTAssertEqual(subject.phase, .confirming(.delete))
        XCTAssertEqual(service.deleteCalls, ["task"])
        subject.confirm()
        XCTAssertEqual(service.deleteCalls, ["task", "task"])
    }

    // Break caught: retry asks for destructive consent for an item that vanished after the failed delete.
    func testFailedDeleteRetryRechecksVanishedItemBeforeConfirmationAndReconcilesOnce() async {
        var reconciliationCount = 0
        let service = RecordingRemindersService(reminders: [reminder()], deleteErrors: [TestFailure.save])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service, onReconciliationNeeded: { reconciliationCount += 1 })
        subject.requestDelete(); subject.confirm()
        service.reminders = []

        await subject.retry(); await subject.retry()

        XCTAssertEqual(subject.phase, .unavailable(.itemGone))
        XCTAssertEqual(service.deleteCalls, ["task"])
        XCTAssertEqual(reconciliationCount, 1)
    }

    // Break caught: retry asks for destructive consent after the provider item becomes read-only.
    func testFailedDeleteRetryRechecksReadOnlyAuthorityBeforeConfirmation() async {
        let service = RecordingRemindersService(reminders: [reminder()], deleteErrors: [TestFailure.save])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)
        subject.requestDelete(); subject.confirm()
        service.reminders = [readOnlyReminder()]

        await subject.retry()

        XCTAssertEqual(subject.phase, .unavailable(.readOnlySource))
        XCTAssertEqual(service.deleteCalls, ["task"])
    }

    // Break caught: retry asks for destructive consent after Reminders access is revoked.
    func testFailedDeleteRetryRechecksAccessAuthorityBeforeConfirmation() async {
        let service = RecordingRemindersService(reminders: [reminder()], deleteErrors: [TestFailure.save])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)
        subject.requestDelete(); subject.confirm()
        service.accessState = .denied

        await subject.retry()

        XCTAssertEqual(subject.phase, .unavailable(.accessUnavailable))
        XCTAssertEqual(service.deleteCalls, ["task"])
    }

    // Break caught: cancelling a destructive prompt or asking a create editor to delete still mutates the provider.
    func testCancelledDeleteConfirmationAndCreateModeDeletePerformZeroWrites() async {
        let service = RecordingRemindersService(reminders: [reminder()])
        let edit = TaskEditorViewModel.editing(reminderID: "task", service: service)
        edit.requestDelete(); edit.cancelConfirmation()
        let create = TaskEditorViewModel.creating(service: service)
        create.requestDelete()

        XCTAssertTrue(service.deleteCalls.isEmpty)
        XCTAssertEqual(edit.phase, .idle)
        XCTAssertEqual(create.phase, .idle)
    }

    func testPresentationDismissalCancelsOnlyAnOpenConfirmation() {
        let service = RecordingRemindersService(reminders: [reminder()])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)

        subject.requestDelete()
        subject.setDeleteConfirmationPresented(false, generation: subject.deleteConfirmationGeneration)
        XCTAssertEqual(subject.phase, .idle)
        XCTAssertTrue(service.deleteCalls.isEmpty)

        subject.requestDelete()
        let generation = subject.deleteConfirmationGeneration
        subject.confirm()
        subject.setDeleteConfirmationPresented(false, generation: generation)
        XCTAssertEqual(subject.phase, .deleted)
        XCTAssertEqual(service.deleteCalls, ["task"])
    }

    // Break caught: consent for a nonrepeating reminder can be reused after it starts repeating.
    func testDeleteRequiresFreshConsentWhenReminderBecomesRecurringBeforeConfirmation() {
        let nonrecurring = reminder()
        let recurring = reminder(recurrence: .editable(weekly))
        let service = RecordingRemindersService(reminderResponses: [nonrecurring, nonrecurring, recurring, recurring, recurring])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)

        subject.requestDelete()
        let staleGeneration = subject.deleteConfirmationGeneration
        subject.confirm()

        XCTAssertEqual(subject.phase, .confirming(.delete))
        XCTAssertGreaterThan(subject.deleteConfirmationGeneration, staleGeneration)
        XCTAssertTrue(service.deleteCalls.isEmpty)
        XCTAssertEqual(subject.recurringDeleteExplanation, "Deleting this task removes the repeating reminder.")
        subject.setDeleteConfirmationPresented(false, generation: staleGeneration)
        XCTAssertEqual(subject.phase, .confirming(.delete))
        subject.confirm()
        XCTAssertEqual(service.deleteCalls, ["task"])
    }

    // Break caught: consent for a repeating reminder can be reused after it stops repeating.
    func testDeleteRequiresFreshConsentWhenReminderStopsRecurringBeforeConfirmation() {
        let recurring = reminder(recurrence: .editable(weekly))
        let nonrecurring = reminder()
        let service = RecordingRemindersService(reminderResponses: [recurring, recurring, nonrecurring])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)

        subject.requestDelete()
        let staleGeneration = subject.deleteConfirmationGeneration
        subject.confirm()

        XCTAssertEqual(subject.phase, .confirming(.delete))
        XCTAssertGreaterThan(subject.deleteConfirmationGeneration, staleGeneration)
        XCTAssertTrue(service.deleteCalls.isEmpty)
        XCTAssertNil(subject.recurringDeleteExplanation)
        subject.setDeleteConfirmationPresented(false, generation: staleGeneration)
        XCTAssertEqual(subject.phase, .confirming(.delete))
        subject.setDeleteConfirmationPresented(false, generation: subject.deleteConfirmationGeneration)
        XCTAssertEqual(subject.phase, .idle)
    }

    func testDeleteReconfirmsWhenFinalAuthorityChangesRecurrenceInEitherDirectionBeforeWriting() {
        let nonrecurring = reminder()
        let recurring = reminder(recurrence: .editable(weekly))

        for (initial, final, expectedCopy) in [
            (nonrecurring, recurring, "Deleting this task removes the repeating reminder."),
            (recurring, nonrecurring, nil)
        ] {
            let service = RecordingRemindersService(reminderResponses: [initial, initial, initial, final])
            let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)
            var phaseAtFinalAuthorityLookup: TaskEditorPhase?
            service.onReminderLookup = {
                if service.reminderLookupCount == 4 {
                    phaseAtFinalAuthorityLookup = subject.phase
                }
            }

            subject.requestDelete()
            let staleGeneration = subject.deleteConfirmationGeneration
            subject.confirm()

            XCTAssertEqual(phaseAtFinalAuthorityLookup, .confirming(.delete))
            XCTAssertTrue(service.deleteCalls.isEmpty)
            XCTAssertEqual(subject.phase, .confirming(.delete))
            XCTAssertGreaterThan(subject.deleteConfirmationGeneration, staleGeneration)
            XCTAssertEqual(subject.recurringDeleteExplanation, expectedCopy)
            subject.setDeleteConfirmationPresented(false, generation: staleGeneration)
            XCTAssertEqual(subject.phase, .confirming(.delete))
        }
    }

    // Break caught: clean and dirty forms receive the same dismissal treatment.
    func testDismissalContractAllowsCleanFormAndRequiresExplicitDiscardForDirtyForm() {
        let subject = TaskEditorViewModel.creating(service: RecordingRemindersService())
        XCTAssertEqual(subject.requestDismissal(), .dismiss)

        subject.form.title = "Unsaved edit"
        XCTAssertEqual(subject.requestDismissal(), .confirmDiscard)
        XCTAssertEqual(subject.confirmDiscard(), .dismiss)
    }

    // Break caught: a failed write can be dismissed without explicit discard when form values equal the initial snapshot.
    func testFailedOperationRequiresExplicitDiscardEvenWhenFormIsOtherwiseClean() async {
        let snapshot = reminder()
        let service = RecordingRemindersService(reminders: [snapshot], updateErrors: [TestFailure.save])
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: service)
        await subject.requestSave()

        XCTAssertEqual(subject.phase, .failed(.save, .retryableWrite))
        XCTAssertEqual(subject.requestDismissal(), .confirmDiscard)
        XCTAssertEqual(subject.confirmDiscard(), .dismiss)
        XCTAssertEqual(service.updateCalls.count, 1)
    }

    // Break caught: failed creation loses user edits or retries a stale draft.
    func testFailedCreateRetainsLatestEditedFormAndRetryWritesItOnce() async {
        let service = RecordingRemindersService(lists: [list("inbox", writable: true)], createErrors: [TestFailure.save, nil])
        let subject = TaskEditorViewModel.creating(service: service)
        subject.form.title = "First wording"; subject.selectDestination(.explicit(id: "inbox"))

        await subject.requestSave()
        subject.form.title = "Latest wording"
        await subject.retry()

        XCTAssertEqual(service.createCalls.map(\.title), ["First wording", "Latest wording"])
        XCTAssertEqual(subject.phase, .created(id: "created-2"))
    }

    // Break caught: failed updates and deletes can write the pre-failure snapshot after the user edits it.
    func testFailedUpdateAndDeleteRetainContextAndUseLatestEditedFormOnRetry() async {
        let service = RecordingRemindersService(reminders: [reminder()], updateErrors: [TestFailure.save, nil])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)
        subject.form.title = "Before failure"
        await subject.requestSave()
        subject.form.title = "After failure"
        await subject.retry()

        XCTAssertEqual(service.updateCalls.map(\.draft.title), ["Before failure", "After failure"])
        XCTAssertEqual(subject.phase, .updated)
    }

    // Break caught: confirmation races, repeated taps, or cross-actions write more than once.
    func testTerminalDoubleAndCrossActionGuardsAcceptOnlyOneWrite() async {
        let service = RecordingRemindersService(lists: [list("inbox", writable: true)])
        let subject = TaskEditorViewModel.creating(service: service)
        subject.selectDestination(.explicit(id: "inbox")); subject.form.title = "Create once"

        await subject.requestSave(); await subject.requestSave(); subject.requestDelete(); await subject.retry(); subject.confirm()

        XCTAssertEqual(service.createCalls.count, 1)
        XCTAssertTrue(service.deleteCalls.isEmpty)
        XCTAssertEqual(subject.phase, .created(id: "created-1"))
    }

    // Break caught: a successful save with no provider identifier is treated as a failure and duplicated.
    func testNilCreateIDIsTerminalSuccessAndCallsCommittedExactlyOnce() async {
        var commits: [TaskEditorCommit] = []
        let service = RecordingRemindersService(lists: [list("inbox", writable: true)], createIDs: [nil])
        let subject = TaskEditorViewModel.creating(service: service, onCommitted: { commits.append($0) })
        subject.selectDestination(.explicit(id: "inbox")); subject.form.title = "No identifier"

        await subject.requestSave(); await subject.retry(); await subject.requestSave()

        XCTAssertEqual(subject.phase, .created(id: nil))
        XCTAssertEqual(service.createCalls.count, 1)
        XCTAssertEqual(commits, [.created(id: nil)])
    }

    // Break caught: update success is reported as an untyped nil identifier or more than once.
    func testUpdateCallsTypedCommitExactlyOnceAcrossPostTerminalActions() async {
        var commits: [TaskEditorCommit] = []
        let service = RecordingRemindersService(reminders: [reminder()])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service, onCommitted: { commits.append($0) })

        await subject.requestSave(); await subject.requestSave(); subject.requestDelete(); await subject.retry(); subject.confirm()

        XCTAssertEqual(commits, [.updated])
        XCTAssertEqual(service.updateCalls.count, 1)
        XCTAssertTrue(service.deleteCalls.isEmpty)
    }

    // Break caught: delete success is reported as an untyped nil identifier or more than once.
    func testDeleteCallsTypedCommitExactlyOnceAcrossPostTerminalActions() async {
        var commits: [TaskEditorCommit] = []
        let service = RecordingRemindersService(reminders: [reminder()])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service, onCommitted: { commits.append($0) })

        subject.requestDelete(); subject.confirm(); subject.confirm(); await subject.requestSave(); subject.requestDelete()

        XCTAssertEqual(commits, [.deleted])
        XCTAssertEqual(service.deleteCalls, ["task"])
        XCTAssertTrue(service.updateCalls.isEmpty)
    }

    // Break caught: a vanished edit does not request host reconciliation, or requests it repeatedly.
    func testItemGoneRequestsReconciliationExactlyOnceAndNeverCommits() async {
        var commits: [TaskEditorCommit] = []
        var reconciliationCount = 0
        let service = RecordingRemindersService(reminders: [reminder()])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service, onCommitted: { commits.append($0) }, onReconciliationNeeded: { reconciliationCount += 1 })
        service.reminders = []

        await subject.requestSave(); await subject.requestSave(); subject.requestDelete(); await subject.retry()

        XCTAssertEqual(subject.phase, .unavailable(.itemGone))
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(reconciliationCount, 1)
        XCTAssertTrue(service.updateCalls.isEmpty)
        XCTAssertTrue(service.deleteCalls.isEmpty)
    }

    // Break caught: revoked access, a vanished item, or read-only source reaches a mutation service call.
    func testAccessItemAndReadOnlyTransitionsBecomeUnavailableWithZeroWrites() async {
        let service = RecordingRemindersService(reminders: [reminder()])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)
        service.accessState = .denied
        await subject.requestSave()
        XCTAssertEqual(subject.phase, .unavailable(.accessUnavailable))

        service.accessState = .granted; service.reminders = []
        let missing = TaskEditorViewModel.editing(reminderID: "task", service: service)
        await missing.requestSave()
        XCTAssertEqual(missing.phase, .unavailable(.itemGone))
        XCTAssertTrue(service.updateCalls.isEmpty)
    }

    // Break caught: a readable but immutable reminder reaches the update/delete service as if it were writable.
    func testReadOnlyReminderIsDetailOnlyWithVisibleReasonAndZeroWrites() async {
        let readOnly = ReminderSnapshot(id: "task", title: "Shared", notes: nil, dueDate: due, dueHasTime: false, priority: 1, listID: "shared", listTitle: "Shared", isCompleted: false, allowsModification: false, hasRecurrence: false)
        let service = RecordingRemindersService(reminders: [readOnly])
        let subject = TaskEditorViewModel.editing(reminderID: "task", service: service)

        await subject.requestSave(); subject.requestDelete()

        XCTAssertEqual(subject.phase, .unavailable(.readOnlySource))
        XCTAssertEqual(subject.mutationExplanation, "This task belongs to a read-only reminders list.")
        XCTAssertTrue(service.updateCalls.isEmpty)
        XCTAssertTrue(service.deleteCalls.isEmpty)
    }

    // Break caught: an explicit invalid or read-only move silently falls back to another list.
    func testExplicitVanishedOrReadOnlyDestinationFailsWithoutWriteAndRetainsForm() async {
        let snapshot = reminder()
        let service = RecordingRemindersService(reminders: [snapshot], lists: [list("locked", writable: false)])
        let subject = TaskEditorViewModel.editing(reminderID: snapshot.id, service: service)
        subject.form.title = "Keep me"; subject.selectDestination(.explicit(id: "locked"))

        await subject.requestSave()

        XCTAssertEqual(subject.phase, .failed(.save, .invalidDestination))
        XCTAssertEqual(subject.form.title, "Keep me")
        XCTAssertTrue(service.updateCalls.isEmpty)
    }

    // Break caught: client-side invalid drafts call the provider before reporting validation.
    func testBlankTitleInvalidPriorityAndDueTimeWithoutDueDatePerformZeroWrites() async {
        let service = RecordingRemindersService(lists: [list("inbox", writable: true)])
        let subject = TaskEditorViewModel.creating(service: service)
        subject.selectDestination(.explicit(id: "inbox"))
        subject.form.title = "   "
        await subject.requestSave()
        subject.form.title = "Valid"; subject.form.priority = 99
        await subject.requestSave()
        subject.form.priority = 1; subject.form = .init(title: "Valid", notes: nil, dueDate: nil, dueHasTime: true, priority: 1, listID: "inbox")
        await subject.requestSave()

        XCTAssertTrue(service.createCalls.isEmpty)
        XCTAssertEqual(subject.phase, .failed(.save, .validation))
    }

    // Break caught: model ownership grows to include fetch/host refresh, allowing a refresh failure to repeat a write.
    func testEditorDoesNotFetchAndACommittedWriteCannotDowngradeToRetry() async {
        let service = RecordingRemindersService(lists: [list("inbox", writable: true)])
        let subject = TaskEditorViewModel.creating(service: service)
        subject.selectDestination(.explicit(id: "inbox")); subject.form.title = "No refresh"

        await subject.requestSave()

        XCTAssertEqual(service.fetchCount, 0)
        XCTAssertEqual(subject.phase, .created(id: "created-1"))
        XCTAssertFalse(subject.canRetry)
    }

    func testFinalDestinationRecheckRejectsVanishedAndReadOnlyMovesWithoutWriting() async {
        for finalLists in [[], [list("move", writable: false)]] {
            let original = reminder()
            let service = RecordingRemindersService(
                reminderResponses: [original, original, original],
                listResponses: [[list("move", writable: true)], [list("move", writable: true)], finalLists]
            )
            let subject = TaskEditorViewModel.editing(reminderID: original.id, service: service)
            subject.selectDestination(.explicit(id: "move"))

            await subject.requestSave()

            XCTAssertEqual(subject.phase, .failed(.save, .invalidDestination))
            XCTAssertTrue(service.updateCalls.isEmpty)
        }
    }

    func testFinalSnapshotBecomingRecurringRevalidatesPreservedNilScheduleBeforeWrite() async {
        let nonrecurring = reminderWithoutDue()
        let recurring = reminderWithoutDue(recurrence: .editable(weekly))
        let service = RecordingRemindersService(reminderResponses: [nonrecurring, nonrecurring, recurring])
        let subject = TaskEditorViewModel.editing(reminderID: nonrecurring.id, service: service)

        await subject.requestSave()

        XCTAssertEqual(subject.phase, .failed(.save, .validation))
        XCTAssertTrue(service.updateCalls.isEmpty)
    }

    func testInvalidRecurrenceScopeServiceErrorMapsToValidationFailure() async {
        let original = reminder()
        let service = RecordingRemindersService(reminders: [original], updateErrors: [DraftValidationError.invalidRecurrenceScope])
        let subject = TaskEditorViewModel.editing(reminderID: original.id, service: service)

        await subject.requestSave()

        XCTAssertEqual(subject.phase, .failed(.save, .validation))
        XCTAssertEqual(service.updateCalls.count, 1)
    }

    private func reminder(
        listID: String = "inbox",
        listTitle: String = "Inbox",
        recurrence: RecurrenceSnapshot = .none,
        alarm: ReminderAlarmSnapshot = .none
    ) -> ReminderSnapshot {
        .init(id: "task", title: "Buy milk", notes: "two litres", dueDate: due, dueHasTime: true, priority: 1, listID: listID, listTitle: listTitle, isCompleted: false, allowsModification: true, hasRecurrence: recurrence != .none, alarm: alarm, recurrence: recurrence)
    }

    private func reminderWithoutDue(recurrence: RecurrenceSnapshot = .none) -> ReminderSnapshot {
        .init(id: "task", title: "Buy milk", notes: nil, dueDate: nil, priority: 1, listID: "inbox", listTitle: "Inbox", isCompleted: false, allowsModification: true, hasRecurrence: recurrence != .none, recurrence: recurrence)
    }

    private func readOnlyReminder() -> ReminderSnapshot {
        .init(id: "task", title: "Buy milk", notes: nil, dueDate: due, dueHasTime: true, priority: 1, listID: "inbox", listTitle: "Inbox", isCompleted: false, allowsModification: false, hasRecurrence: false)
    }

    private func list(_ id: String, writable: Bool) -> ReminderListDescriptor {
        .init(id: id, title: id, colorHex: "#000000", allowsContentModifications: writable)
    }
}

private enum TestFailure: Error { case save }

@MainActor
private final class RecordingRemindersService: RemindersServicing {
    var accessState: AccessState = .granted
    var reminders: [ReminderSnapshot]
    var descriptorValues: [ReminderListDescriptor]
    var createErrors: [Error?]
    var updateErrors: [Error?]
    var deleteErrors: [Error?]
    var createIDs: [String?]
    var reminderResponses: [ReminderSnapshot?]
    var listResponses: [[ReminderListDescriptor]]
    private(set) var createCalls: [ReminderDraft] = []
    private(set) var updateCalls: [ReminderUpdateCall] = []
    private(set) var deleteCalls: [String] = []
    private(set) var fetchCount = 0
    private(set) var reminderLookupCount = 0
    var onReminderLookup: (() -> Void)?

    init(reminders: [ReminderSnapshot] = [], reminderResponses: [ReminderSnapshot?] = [], lists: [ReminderListDescriptor] = [], listResponses: [[ReminderListDescriptor]] = [], createErrors: [Error?] = [], updateErrors: [Error?] = [], deleteErrors: [Error?] = [], createIDs: [String?] = []) {
        self.reminders = reminders; self.reminderResponses = reminderResponses; descriptorValues = lists; self.listResponses = listResponses; self.createErrors = createErrors; self.updateErrors = updateErrors; self.deleteErrors = deleteErrors; self.createIDs = createIDs
    }

    func requestFullAccess() async -> AccessState { accessState }
    func lists() -> [ReminderListDescriptor] { listResponses.isEmpty ? descriptorValues : listResponses.removeFirst() }
    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] { fetchCount += 1; return reminders }
    func createReminder(_ draft: ReminderDraft) throws -> String? { createCalls.append(draft); if let error = createErrors.popFirst() ?? nil { throw error }; return createIDs.popFirst() ?? "created-\(createCalls.count)" }
    func setCompleted(id: String, completed: Bool) throws {}
    func reminder(id: String) -> ReminderSnapshot? {
        reminderLookupCount += 1
        onReminderLookup?()
        return reminderResponses.isEmpty ? reminders.first { $0.id == id } : reminderResponses.removeFirst()
    }
    func updateReminder(id: String, draft: ReminderDraft) throws { updateCalls.append(.init(id: id, draft: draft)); if let error = updateErrors.popFirst() ?? nil { throw error } }
    func deleteReminder(id: String) throws { deleteCalls.append(id); if let error = deleteErrors.popFirst() ?? nil { throw error } }
}

private extension Array {
    mutating func popFirst() -> Element? { isEmpty ? nil : removeFirst() }
    var single: Element? { count == 1 ? first : nil }
}
