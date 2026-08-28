import Foundation
import Observation
import XCTest
@testable import PersonalCalendar

/// RED contract tests for the event editor.  The editor API below is deliberately
/// explicit: route IDs are display-only, while writes can use only a freshly
/// resolved snapshot's opaque mutation ID.
@MainActor
final class EventEditorViewModelTests: XCTestCase {
    func testCreateAssignsSelectedCategoryToReturnedOpaqueIdentifier() async {
        let category = CategorySnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000077")!,
            name: "Personal",
            colorHex: "#3A8D7C",
            sortOrder: 0
        )
        let categories = EditorCategoryRepositoryStub(values: [category])
        let service = RecordingCalendarService(createID: "opaque-created-event")
        let subject = EventEditorViewModel.create(
            service: service,
            savedDefaultCalendarID: nil,
            categories: categories
        )
        subject.title = "Dinner"
        subject.categoryID = category.id

        await subject.requestSave()

        XCTAssertEqual(
            categories.assignments,
            [.init(categoryID: category.id, source: .event, externalID: "opaque-created-event")]
        )
        XCTAssertEqual(subject.phase, .created(id: "opaque-created-event"))
    }

    func testSaveEligibilityRejectsPurelyInvalidEventFormValuesWithoutLookingUpOrWriting() async {
        let service = RecordingCalendarService(event: event())
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()
        let lookupsAfterLoad = service.displayLookups.count

        XCTAssertTrue(subject.canSave)

        subject.title = " \n "
        XCTAssertFalse(subject.canSave)
        subject.title = "Event"
        subject.end = subject.start
        XCTAssertFalse(subject.canSave)
        subject.end = subject.start.addingTimeInterval(-1)
        XCTAssertFalse(subject.canSave)
        subject.end = end
        subject.alarmIntent = .replace([.infinity])
        XCTAssertFalse(subject.canSave)
        subject.alarmIntent = .preserve
        subject.recurrenceIntent = .replace(.init(frequency: .weekly, interval: 0, weekdays: [], endDate: nil))
        XCTAssertFalse(subject.canSave)
        subject.recurrenceIntent = .replace(.init(frequency: .daily, interval: 1, weekdays: [], endDate: start.addingTimeInterval(-1)))
        XCTAssertFalse(subject.canSave)
        subject.recurrenceIntent = .replace(.init(frequency: .weekly, interval: 2, weekdays: [2], endDate: end))
        XCTAssertTrue(subject.canSave)
        XCTAssertEqual(service.displayLookups.count, lookupsAfterLoad)
        XCTAssertTrue(service.creates.isEmpty)
        XCTAssertTrue(service.updates.isEmpty)
    }

    func testEditLoadsDisplayIDAndPreservesExactLocationAndUnsupportedValuesUntilChanged() async {
        let snapshot = event(id: "agenda-event", mutationID: "opaque", location: "  Room 7  ", alarms: .unsupported(summary: "Vendor alarm"), recurrence: .unsupported(summary: "Vendor repeat"))
        let service = RecordingCalendarService(event: snapshot)
        let subject = EventEditorViewModel.edit(displayID: "agenda-event", service: service)

        await subject.load()

        XCTAssertEqual(service.displayLookups, ["agenda-event"])
        XCTAssertEqual(subject.location, "  Room 7  ")
        XCTAssertEqual(subject.alarmDisplay, "Vendor alarm")
        XCTAssertEqual(subject.recurrenceDisplay, "Vendor repeat")
        XCTAssertEqual(subject.alarmIntent, .preserve)
        XCTAssertEqual(subject.recurrenceIntent, .preserve)
        XCTAssertNil(subject.destinationCalendarID)
    }

    func testTitleOnlyEditUsesOpaqueMutationIDByteForByteAndPreservesProviderOwnedFields() async {
        let snapshot = event(id: "agenda-id", mutationID: "  opaque-id  ", location: "  Dock  ", alarms: .unsupported(summary: "alarm"), recurrence: .unsupported(summary: "repeat"))
        let service = RecordingCalendarService(event: snapshot)
        let subject = EventEditorViewModel.edit(displayID: "agenda-id", service: service)
        await subject.load(); subject.title = "Renamed"

        await subject.requestSave(); subject.confirm()

        XCTAssertEqual(service.updates, [.init(id: "  opaque-id  ", draft: EventDraft(title: "Renamed", start: start, end: end, isAllDay: false, calendarID: nil, location: "  Dock  ", alarms: .preserve, recurrence: .preserve), scope: .thisOccurrence)])
    }

    func testCreateNilDestinationPassesSystemDefaultUnchanged() async {
        let service = RecordingCalendarService()
        let subject = EventEditorViewModel.create(service: service, savedDefaultCalendarID: "gone")
        subject.title = "New event"

        await subject.requestSave()

        XCTAssertEqual(service.creates.single?.calendarID, nil)
        XCTAssertEqual(subject.phase, .created(id: "created"))
    }

    func testCreateSeedsOnlyAValidWritableSavedDefault() async {
        let service = RecordingCalendarService(calendars: [writable("home"), readOnly("locked")])
        let subject = EventEditorViewModel.create(service: service, savedDefaultCalendarID: "home")
        subject.title = "New event"

        XCTAssertEqual(subject.destinationCalendarID, "home")
        await subject.requestSave()
        XCTAssertEqual(service.creates.single?.calendarID, "home")
    }

    func testCreateInitialScheduleIsCapturedAsCleanBaseline() {
        let initialStart = Date(timeIntervalSinceReferenceDate: 5_000)
        let initialEnd = Date(timeIntervalSinceReferenceDate: 8_600)

        let subject = EventEditorViewModel.create(service: RecordingCalendarService(), savedDefaultCalendarID: nil, initialStart: initialStart, initialEnd: initialEnd, isAllDay: true)

        XCTAssertEqual(subject.start, initialStart)
        XCTAssertEqual(subject.end, initialEnd)
        XCTAssertTrue(subject.isAllDay)
        XCTAssertFalse(subject.requiresDiscardConfirmation)
    }

    func testEditNilDestinationMeansPreserveCurrentAndExplicitDestinationMoves() async {
        let service = RecordingCalendarService(event: event(), calendars: [writable("other")])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); await subject.requestSave()
        XCTAssertNil(service.updates.single?.draft.calendarID)

        let moving = EventEditorViewModel.edit(displayID: "display", service: service)
        await moving.load(); moving.destinationCalendarID = "other"; await moving.requestSave()
        XCTAssertEqual(service.updates.last?.draft.calendarID, "other")
    }

    func testRecurringPreserveOffersBothScopesAndUsesSelectedScope() async {
        let service = RecordingCalendarService(event: event(recurrence: .editable(rule)))
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        XCTAssertEqual(subject.availableSaveScopes, [.thisOccurrence, .futureOccurrences])
        await subject.requestSave(scope: .futureOccurrences); subject.confirm()
        XCTAssertEqual(service.updates.single?.scope, .futureOccurrences)
    }

    func testRecurringEditLoadsAndMutatesTheExactStableOccurrence() async {
        let displayStart = start.addingTimeInterval(5 * 24 * 60 * 60)
        let occurrenceDate = displayStart.addingTimeInterval(-3_600)
        let occurrenceAddress = EventOccurrenceAddress(
            displayStart: displayStart,
            occurrenceDate: occurrenceDate
        )
        let occurrence = event(
            title: "Exact Friday class",
            recurrence: .editable(rule),
            eventStart: displayStart,
            eventEnd: displayStart.addingTimeInterval(3_600),
            occurrenceDate: occurrenceDate
        )
        let service = RecordingCalendarService(
            event: event(title: "First series occurrence", recurrence: .editable(rule)),
            occurrences: [occurrenceAddress: occurrence]
        )
        let subject = EventEditorViewModel.edit(
            displayID: "display",
            occurrence: occurrenceAddress,
            service: service
        )

        await subject.load()
        XCTAssertEqual(subject.title, "Exact Friday class")
        XCTAssertEqual(subject.start, displayStart)
        subject.start = displayStart.addingTimeInterval(1_800)
        subject.end = displayStart.addingTimeInterval(5_400)

        await subject.requestSave(scope: .thisOccurrence)
        subject.confirm()

        XCTAssertEqual(
            service.occurrenceLookups,
            [occurrenceAddress, occurrenceAddress, occurrenceAddress]
        )
        XCTAssertEqual(service.occurrenceUpdates.compactMap { $0 }.single, occurrenceAddress)
    }

    func testRecurringDeleteMutatesTheExactStableOccurrence() async {
        let displayStart = start.addingTimeInterval(7 * 24 * 60 * 60)
        let occurrenceDate = displayStart.addingTimeInterval(-7_200)
        let occurrenceAddress = EventOccurrenceAddress(
            displayStart: displayStart,
            occurrenceDate: occurrenceDate
        )
        let occurrence = event(
            recurrence: .editable(rule),
            eventStart: displayStart,
            eventEnd: displayStart.addingTimeInterval(3_600),
            occurrenceDate: occurrenceDate
        )
        let service = RecordingCalendarService(
            event: event(recurrence: .editable(rule)),
            occurrences: [occurrenceAddress: occurrence]
        )
        let subject = EventEditorViewModel.edit(
            displayID: "display",
            occurrence: occurrenceAddress,
            service: service
        )

        await subject.load()
        await subject.requestDelete(scope: .thisOccurrence)
        subject.confirm()

        XCTAssertEqual(
            service.occurrenceLookups,
            [occurrenceAddress, occurrenceAddress, occurrenceAddress]
        )
        XCTAssertEqual(service.occurrenceDeletes.compactMap { $0 }.single, occurrenceAddress)
    }

    func testChangingRecurrenceBlocksThisOccurrenceButAllowsFuture() async {
        let service = RecordingCalendarService(event: event(recurrence: .editable(rule)))
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); subject.recurrenceIntent = .clear

        await subject.requestSave(scope: .thisOccurrence)
        XCTAssertTrue(service.updates.isEmpty)
        XCTAssertEqual(subject.scopeExplanation, "Changes to repeat settings apply to this and future events.")

        await subject.requestSave(scope: .futureOccurrences); subject.confirm()
        XCTAssertEqual(service.updates.single?.scope, .futureOccurrences)
    }

    func testNonRecurringEventBecomingRecurringAlwaysWritesThisOccurrence() async {
        let service = RecordingCalendarService(event: event())
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); subject.recurrenceIntent = .replace(rule)

        await subject.requestSave(scope: .futureOccurrences)
        XCTAssertEqual(service.updates.single?.scope, .thisOccurrence)
    }

    func testCancelConfirmationAndCreateDeletePerformZeroWrites() async {
        let service = RecordingCalendarService(event: event(recurrence: .editable(rule)))
        let editor = EventEditorViewModel.edit(displayID: "display", service: service)
        await editor.load(); await editor.requestDelete(scope: .thisOccurrence); editor.cancelConfirmation()
        let create = EventEditorViewModel.create(service: service, savedDefaultCalendarID: nil)
        await create.requestDelete(scope: .thisOccurrence)

        XCTAssertTrue(service.deletes.isEmpty)
        XCTAssertEqual(create.phase, .idle)
    }

    func testPresentationDismissalCancelsOnlyAnOpenConfirmation() async {
        let service = RecordingCalendarService(event: event(recurrence: .editable(rule)))
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        await subject.requestDelete(scope: .thisOccurrence)
        subject.setConfirmationPresented(false, generation: subject.confirmationGeneration)
        XCTAssertEqual(subject.phase, .idle)
        XCTAssertTrue(service.deletes.isEmpty)

        await subject.requestDelete(scope: .thisOccurrence)
        let generation = subject.confirmationGeneration
        subject.confirm()
        subject.setConfirmationPresented(false, generation: generation)
        XCTAssertEqual(subject.phase, .deleted)
        XCTAssertEqual(service.deletes.count, 1)
    }

    func testEveryDeleteAttemptAndRetryRequiresFreshConfirmation() async {
        let service = RecordingCalendarService(event: event(recurrence: .editable(rule)), deleteError: Failure.write)
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); await subject.requestDelete(scope: .thisOccurrence); subject.confirm()
        XCTAssertEqual(subject.phase, .failed(action: .delete(scope: .thisOccurrence), error: .retryableWriteFailure))

        await subject.retry()
        XCTAssertEqual(subject.phase, .confirming(action: .delete(scope: .thisOccurrence)))
        subject.confirm()
        XCTAssertEqual(service.deletes.count, 2)
    }

    func testFailedUpdateRetainsLatestEditedFormForRetry() async {
        let service = RecordingCalendarService(event: event(), updateError: Failure.write)
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); subject.title = "First"; await subject.requestSave(); subject.title = "Edited retry"; service.updateError = nil

        await subject.retry()

        XCTAssertEqual(service.updates.last?.draft.title, "Edited retry")
        XCTAssertEqual(subject.phase, .updated)
    }

    func testTerminalAndCrossActionsAcceptOnlyOneWrite() async {
        let service = RecordingCalendarService(event: event())
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); await subject.requestSave(); await subject.requestSave(); await subject.requestDelete(scope: .thisOccurrence); subject.confirm(); await subject.retry()

        XCTAssertEqual(service.updates.count, 1)
        XCTAssertTrue(service.deletes.isEmpty)
        XCTAssertEqual(subject.phase, .updated)
    }

    func testNilCreateIDIsTerminalSuccessAndCallsCommittedOnce() async {
        let service = RecordingCalendarService(createID: nil)
        var commits: [EventEditorCommit] = []
        let subject = EventEditorViewModel.create(service: service, savedDefaultCalendarID: nil, onCommitted: { commits.append($0) })
        subject.title = "New event"

        await subject.requestSave(); await subject.requestSave(); await subject.retry()

        XCTAssertEqual(subject.phase, .created(id: nil))
        XCTAssertEqual(commits, [.created(id: nil)])
        XCTAssertEqual(service.creates.count, 1)
    }

    func testReadOnlyMissingMutationIDAccessLossAndMissingItemBecomeDetailOnlyWithoutWrites() async {
        let cases: [(CalendarEventSnapshot?, AccessState)] = [(event(mutationID: nil), .granted), (event(), .denied), (nil, .granted)]
        for (snapshot, access) in cases {
            let service = RecordingCalendarService(access: access, event: snapshot)
            let subject = EventEditorViewModel.edit(displayID: "display", service: service)
            await subject.load(); await subject.requestSave(); await subject.requestDelete(scope: .thisOccurrence)
            XCTAssertTrue(service.creates.isEmpty); XCTAssertTrue(service.updates.isEmpty); XCTAssertTrue(service.deletes.isEmpty)
            XCTAssertNotNil(subject.unavailableReason)
        }
    }

    func testExplicitMissingOrReadOnlyDestinationAndRevokedAccessMakeZeroWrites() async {
        let service = RecordingCalendarService(event: event(), calendars: [readOnly("locked")])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); subject.destinationCalendarID = "missing"; await subject.requestSave()
        XCTAssertTrue(service.updates.isEmpty)

        subject.destinationCalendarID = "locked"; await subject.requestSave(); service.accessState = .denied; await subject.requestSave()
        XCTAssertTrue(service.updates.isEmpty)
        XCTAssertEqual(subject.title, "Event")
    }

    func testBlankTitleAndInvalidDateRangeAreValidationFailuresWithZeroWrites() async {
        let service = RecordingCalendarService()
        let subject = EventEditorViewModel.create(service: service, savedDefaultCalendarID: nil)
        subject.title = "   "; await subject.requestSave()
        XCTAssertEqual(subject.phase, .failed(action: .save, error: .validationFailure))
        subject.title = "Okay"; subject.end = subject.start; await subject.requestSave()
        XCTAssertTrue(service.creates.isEmpty)
    }

    func testEditorNeverFetchesHostOwnedAgendaData() async {
        let service = RecordingCalendarService(event: event())
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); await subject.requestSave()
        XCTAssertEqual(service.fetchCount, 0)
    }

    func testItemGoneAfterConfirmationRequestsReconciliationAndCannotBlindRetry() async {
        let service = RecordingCalendarService(event: event())
        var reconciliationCount = 0
        let subject = EventEditorViewModel.edit(displayID: "display", service: service, onReconciliationNeeded: { reconciliationCount += 1 })
        await subject.load(); service.eventValue = nil; await subject.requestSave()

        XCTAssertEqual(subject.phase, .unavailable(reason: .itemGone))
        XCTAssertEqual(reconciliationCount, 1)
        await subject.retry(); XCTAssertTrue(service.updates.isEmpty)
    }

    func testPhaseMutationPublishesObservationNotification() async {
        let service = RecordingCalendarService()
        let subject = EventEditorViewModel.create(service: service, savedDefaultCalendarID: nil)
        subject.title = "Observed"
        let notifications = ObservationCounter()
        withObservationTracking {
            _ = subject.phase
        } onChange: {
            notifications.increment()
        }

        await subject.requestSave()

        XCTAssertEqual(notifications.value, 1)
        XCTAssertEqual(subject.phase, .created(id: "created"))
    }

    func testReadOnlyAndNonaddressableDetailsKeepAllProviderFieldsAndDistinctReasons() async {
        let readOnlySnapshot = event(mutationID: "opaque", allowsModification: false, notes: "Provider notes", location: "  Exact place  ", url: URL(string: "https://example.com/a"), alarms: .unsupported(summary: "Provider alarm"), recurrence: .unsupported(summary: "Provider repeat"))
        let nonaddressableSnapshot = event(mutationID: nil, allowsModification: true, notes: "Provider notes", location: "  Exact place  ", url: URL(string: "https://example.com/a"), alarms: .unsupported(summary: "Provider alarm"), recurrence: .unsupported(summary: "Provider repeat"))

        for (snapshot, reason) in [(readOnlySnapshot, EventEditorUnavailableReason.readOnlySource), (nonaddressableSnapshot, .nonaddressable)] {
            let subject = EventEditorViewModel.edit(displayID: "display", service: RecordingCalendarService(event: snapshot))
            await subject.load()
            XCTAssertEqual(subject.unavailableReason, reason)
            XCTAssertEqual(subject.title, "Event")
            XCTAssertEqual(subject.notes, "Provider notes")
            XCTAssertEqual(subject.location, "  Exact place  ")
            XCTAssertEqual(subject.url, URL(string: "https://example.com/a"))
            XCTAssertEqual(subject.currentCalendarID, "home")
            XCTAssertEqual(subject.currentCalendarTitle, "Home")
            XCTAssertEqual(subject.alarmSnapshot, .unsupported(summary: "Provider alarm"))
            XCTAssertEqual(subject.recurrenceSnapshot, .unsupported(summary: "Provider repeat"))
        }
    }

    func testLoadRetainsExactCurrentCalendarAndEditableProviderSnapshotsSeparateFromIntents() async {
        let alarms = EventAlarmSnapshot.editable([-900, -3_600])
        let recurrence = RecurrenceSnapshot.editable(rule)
        let subject = EventEditorViewModel.edit(displayID: "display", service: RecordingCalendarService(event: event(alarms: alarms, recurrence: recurrence)))

        await subject.load()

        XCTAssertEqual(subject.currentCalendarID, "home")
        XCTAssertEqual(subject.currentCalendarTitle, "Home")
        XCTAssertEqual(subject.alarmSnapshot, alarms)
        XCTAssertEqual(subject.recurrenceSnapshot, recurrence)
        XCTAssertEqual(subject.alarmIntent, .preserve)
        XCTAssertEqual(subject.recurrenceIntent, .preserve)
    }

    func testCreateMapsEveryEventKitMutationErrorToEditorTaxonomy() async {
        for (error, expected) in mutationErrorTaxonomy(action: .save) {
            let service = RecordingCalendarService(createError: error)
            let subject = EventEditorViewModel.create(service: service, savedDefaultCalendarID: nil)
            subject.title = "Create"
            await subject.requestSave()
            XCTAssertEqual(subject.phase, expected, "create \(error)")
            XCTAssertEqual(service.creates.count, 1)
        }
    }

    func testUpdateMapsEveryEventKitMutationErrorAndReconcilesItemGoneOnce() async {
        for (error, expected) in mutationErrorTaxonomy(action: .save) {
            var reconciliations = 0
            let service = RecordingCalendarService(event: event(), updateError: error)
            let subject = EventEditorViewModel.edit(displayID: "display", service: service, onReconciliationNeeded: { reconciliations += 1 })
            await subject.load(); await subject.requestSave()
            if error == .itemNotFound { await subject.retry() }
            await subject.load()
            XCTAssertEqual(subject.phase, expected, "update \(error)")
            XCTAssertEqual(reconciliations, error == .itemNotFound ? 1 : 0)
        }
    }

    func testDeleteMapsEveryEventKitMutationErrorAndReconcilesItemGoneOnce() async {
        let action = EventEditorAction.delete(scope: .thisOccurrence)
        for (error, expected) in mutationErrorTaxonomy(action: action) {
            var reconciliations = 0
            let service = RecordingCalendarService(event: event(), deleteError: error)
            let subject = EventEditorViewModel.edit(displayID: "display", service: service, onReconciliationNeeded: { reconciliations += 1 })
            await subject.load(); await subject.requestDelete(scope: .thisOccurrence); subject.confirm()
            if error == .itemNotFound { await subject.retry() }
            await subject.load()
            XCTAssertEqual(subject.phase, expected, "delete \(error)")
            XCTAssertEqual(reconciliations, error == .itemNotFound ? 1 : 0)
        }
    }

    func testSaveRechecksRecurrenceAtRequestConfirmationAndFinalWrite() async {
        let nonrecurring = event(recurrence: .none)
        let recurring = event(recurrence: .editable(rule))
        let service = RecordingCalendarService(events: [nonrecurring, recurring, recurring, recurring])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        await subject.requestSave(scope: .futureOccurrences)
        XCTAssertEqual(subject.phase, .confirming(action: .save))
        XCTAssertEqual(subject.confirmationSaveScope, .futureOccurrences)
        subject.confirm()

        XCTAssertEqual(service.displayLookups.count, 3)
        XCTAssertEqual(service.updates.single?.scope, .futureOccurrences)
    }

    func testDeleteRecoversFromFutureScopeWhenFreshEventIsNonrecurring() async {
        let recurring = event(recurrence: .editable(rule))
        let nonrecurring = event(recurrence: .none)
        let service = RecordingCalendarService(events: [recurring, recurring, nonrecurring, recurring, nonrecurring, nonrecurring])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); await subject.requestDelete(scope: .futureOccurrences)
        XCTAssertEqual(subject.phase, .confirming(action: .delete(scope: .futureOccurrences)))
        let staleGeneration = subject.confirmationGeneration

        subject.confirm()

        XCTAssertTrue(service.deletes.isEmpty)
        XCTAssertEqual(subject.phase, .confirming(action: .delete(scope: .thisOccurrence)))
        XCTAssertEqual(subject.availableSaveScopes, [.thisOccurrence])
        XCTAssertGreaterThan(subject.confirmationGeneration, staleGeneration)
        subject.setConfirmationPresented(false, generation: staleGeneration)
        XCTAssertEqual(subject.phase, .confirming(action: .delete(scope: .thisOccurrence)))
        subject.setConfirmationPresented(false, generation: subject.confirmationGeneration)
        XCTAssertEqual(subject.phase, .idle)

        await subject.requestDelete(scope: .futureOccurrences)
        let secondStaleGeneration = subject.confirmationGeneration
        subject.confirm()
        XCTAssertEqual(subject.phase, .confirming(action: .delete(scope: .thisOccurrence)))
        subject.setConfirmationPresented(false, generation: secondStaleGeneration)
        XCTAssertEqual(subject.phase, .confirming(action: .delete(scope: .thisOccurrence)))
        subject.confirm()
        XCTAssertEqual(service.deletes.single?.scope, .thisOccurrence)
    }

    func testFutureDeleteRequestNormalizesWhenFreshEventIsAlreadyNonrecurring() async {
        let recurring = event(recurrence: .editable(rule))
        let nonrecurring = event(recurrence: .none)
        let service = RecordingCalendarService(events: [recurring, nonrecurring, nonrecurring])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        await subject.requestDelete(scope: .futureOccurrences)

        XCTAssertEqual(subject.phase, .confirming(action: .delete(scope: .thisOccurrence)))
        XCTAssertTrue(service.deletes.isEmpty)
        subject.confirm()
        XCTAssertEqual(service.deletes.single?.scope, .thisOccurrence)
        XCTAssertEqual(subject.phase, .deleted)
    }

    func testFailedFutureSaveRetryKeepsEditedFormAndScopeThroughFreshConfirmation() async {
        let recurring = event(recurrence: .editable(rule))
        let service = RecordingCalendarService(events: Array(repeating: recurring, count: 12), updateError: EventKitMutationError.saveFailed)
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); await subject.requestSave(scope: .futureOccurrences); subject.confirm()
        subject.title = "Edited after failure"; service.updateError = nil

        await subject.retry()
        XCTAssertEqual(subject.phase, .confirming(action: .save))
        XCTAssertEqual(subject.title, "Edited after failure")
        subject.confirm()

        XCTAssertEqual(service.updates.last?.draft.title, "Edited after failure")
        XCTAssertEqual(service.updates.last?.scope, .futureOccurrences)
    }

    func testCancelledFutureSaveCannotLeakIntoInvalidThisOccurrenceRetry() async {
        let recurring = event(recurrence: .editable(rule))
        let service = RecordingCalendarService(events: Array(repeating: recurring, count: 8))
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        await subject.requestSave(scope: .futureOccurrences)
        subject.cancelConfirmation()
        subject.recurrenceIntent = .clear
        await subject.requestSave(scope: .thisOccurrence)
        XCTAssertEqual(subject.phase, .failed(action: .save, error: .validationFailure))

        subject.recurrenceIntent = .preserve
        await subject.retry()
        XCTAssertEqual(subject.phase, .confirming(action: .save))
        XCTAssertEqual(subject.confirmationSaveScope, .thisOccurrence)
        subject.confirm()

        XCTAssertEqual(service.updates.single?.scope, .thisOccurrence)
    }

    func testSaveScopeReconcilesWhenLiveEventBecomesNonrecurringBeforeConfirmation() async {
        let recurring = event(recurrence: .editable(rule))
        let nonrecurring = event(recurrence: .none)
        let service = RecordingCalendarService(events: [recurring, recurring, nonrecurring])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        await subject.requestSave(scope: .futureOccurrences)
        subject.confirm()

        XCTAssertEqual(subject.phase, .updated)
        XCTAssertEqual(subject.availableSaveScopes, [.thisOccurrence])
        XCTAssertEqual(service.updates.single?.scope, .thisOccurrence)
    }

    func testNonrecurringToRecurringRepeatEditExposesScopesAndRecoversWithFutureConsent() async {
        let nonrecurring = event(recurrence: .none)
        let recurring = event(recurrence: .editable(rule))
        let service = RecordingCalendarService(events: [nonrecurring, nonrecurring, recurring, recurring, recurring])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()
        subject.recurrenceIntent = .clear

        await subject.requestSave(scope: .thisOccurrence)

        XCTAssertEqual(subject.phase, .failed(action: .save, error: .validationFailure))
        XCTAssertEqual(subject.availableSaveScopes, [.thisOccurrence, .futureOccurrences])
        XCTAssertEqual(subject.scopeExplanation, "Changes to repeat settings apply to this and future events.")
        XCTAssertTrue(service.updates.isEmpty)

        await subject.requestSave(scope: .futureOccurrences)
        XCTAssertEqual(subject.phase, .confirming(action: .save))
        XCTAssertEqual(subject.confirmationSaveScope, .futureOccurrences)
        subject.confirm()

        XCTAssertEqual(subject.phase, .updated)
        XCTAssertEqual(service.updates.single?.scope, .futureOccurrences)
    }

    func testFutureDeleteReconcilesToThisOccurrenceWhenLiveEventStopsRepeating() async {
        let recurring = event(recurrence: .editable(rule))
        let nonrecurring = event(recurrence: .none)
        let service = RecordingCalendarService(events: [recurring, recurring, nonrecurring, nonrecurring])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        await subject.requestDelete(scope: .futureOccurrences)
        subject.confirm()

        XCTAssertEqual(subject.phase, .confirming(action: .delete(scope: .thisOccurrence)))
        XCTAssertEqual(subject.availableSaveScopes, [.thisOccurrence])
        XCTAssertNil(subject.scopeExplanation)
        XCTAssertTrue(service.deletes.isEmpty)

        subject.confirm()
        XCTAssertEqual(service.deletes.single?.scope, .thisOccurrence)
    }

    func testAcceptedConfirmationNeverPublishesIdleDuringAuthorityLookup() async {
        let recurring = event(recurrence: .editable(rule))
        let service = RecordingCalendarService(events: Array(repeating: recurring, count: 4))
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        await subject.requestSave(scope: .thisOccurrence)
        var lookupPhases: [EventEditorPhase] = []
        service.onEventLookup = { lookupPhases.append(subject.phase) }
        subject.confirm()

        XCTAssertFalse(lookupPhases.contains(.idle))
        XCTAssertEqual(subject.phase, .updated)
    }

    func testLoadAfterTerminalOrFailureDoesNotOverwriteCommittedOrEditedForm() async {
        let changed = event(notes: "Replacement")
        let committedService = RecordingCalendarService(events: [event(), event(), event(), changed])
        let committed = EventEditorViewModel.edit(displayID: "display", service: committedService)
        await committed.load(); committed.title = "Committed"; await committed.requestSave(); await committed.load()
        XCTAssertEqual(committed.phase, .updated)
        XCTAssertEqual(committed.title, "Committed")

        let failedService = RecordingCalendarService(event: event(), updateError: EventKitMutationError.saveFailed)
        let failed = EventEditorViewModel.edit(displayID: "display", service: failedService)
        await failed.load(); failed.title = "Submitted"; await failed.requestSave(); failed.title = "Edited after failure"; failedService.eventValue = changed; await failed.load()
        XCTAssertEqual(failed.phase, .failed(action: .save, error: .retryableWriteFailure))
        XCTAssertEqual(failed.title, "Edited after failure")
    }

    func testDismissalProtectionTracksDirtyFieldsIntentsDestinationAndFailedFormUntilDiscard() async {
        let service = RecordingCalendarService(event: event(), calendars: [writable("other")])
        let clean = EventEditorViewModel.edit(displayID: "display", service: service)
        await clean.load(); XCTAssertFalse(clean.requiresDiscardConfirmation)

        let title = EventEditorViewModel.edit(displayID: "display", service: service); await title.load(); title.title = "Changed"
        let date = EventEditorViewModel.edit(displayID: "display", service: service); await date.load(); date.start = start.addingTimeInterval(60)
        let destination = EventEditorViewModel.edit(displayID: "display", service: service); await destination.load(); destination.destinationCalendarID = "other"
        let alarm = EventEditorViewModel.edit(displayID: "display", service: service); await alarm.load(); alarm.alarmIntent = .clear
        let recurrence = EventEditorViewModel.edit(displayID: "display", service: service); await recurrence.load(); recurrence.recurrenceIntent = .clear
        for dirty in [title, date, destination, alarm, recurrence] { XCTAssertTrue(dirty.requiresDiscardConfirmation) }

        let failedService = RecordingCalendarService(event: event(), updateError: EventKitMutationError.saveFailed)
        let failed = EventEditorViewModel.edit(displayID: "display", service: failedService)
        await failed.load(); await failed.requestSave(); XCTAssertTrue(failed.requiresDiscardConfirmation)
        failed.confirmDiscard(); XCTAssertFalse(failed.requiresDiscardConfirmation)
    }

    func testSuccessfulScopeChangeClearsStaleScopeExplanation() async {
        let recurring = event(recurrence: .editable(rule))
        let service = RecordingCalendarService(events: Array(repeating: recurring, count: 8))
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load(); subject.recurrenceIntent = .clear
        await subject.requestSave(scope: .thisOccurrence)
        XCTAssertNotNil(subject.scopeExplanation)

        subject.recurrenceIntent = .preserve
        await subject.requestSave(scope: .futureOccurrences)

        XCTAssertNil(subject.scopeExplanation)
        XCTAssertEqual(subject.phase, .confirming(action: .save))
    }

    func testRestoringPreservedRecurrenceClearsScopeExplanationImmediately() async {
        let recurring = event(recurrence: .editable(rule))
        let subject = EventEditorViewModel.edit(
            displayID: "display",
            service: RecordingCalendarService(events: Array(repeating: recurring, count: 4))
        )
        await subject.load()
        subject.recurrenceIntent = .clear
        await subject.requestSave(scope: .thisOccurrence)
        XCTAssertNotNil(subject.scopeExplanation)

        subject.recurrenceIntent = .preserve

        XCTAssertNil(subject.scopeExplanation)
    }

    func testFinalDestinationRecheckRejectsVanishedAndReadOnlyMovesWithoutWriting() async {
        for finalCalendars in [[], [readOnly("move")]] {
            let service = RecordingCalendarService(
                events: Array(repeating: event(), count: 4),
                calendarResponses: [[writable("move")], finalCalendars]
            )
            let subject = EventEditorViewModel.edit(displayID: "display", service: service)
            await subject.load()
            subject.destinationCalendarID = "move"

            await subject.requestSave()

            XCTAssertEqual(subject.phase, .failed(action: .save, error: .invalidDestination))
            XCTAssertTrue(service.updates.isEmpty)
        }
    }

    func testFinalNonrecurringToRecurringTransitionRequiresFreshConfirmationBeforeWrite() async {
        let nonrecurring = event(recurrence: .none)
        let recurring = event(recurrence: .editable(rule))
        let service = RecordingCalendarService(events: [nonrecurring, nonrecurring, recurring, recurring, recurring])
        let subject = EventEditorViewModel.edit(displayID: "display", service: service)
        await subject.load()

        await subject.requestSave(scope: .thisOccurrence)

        XCTAssertEqual(subject.phase, .confirming(action: .save))
        XCTAssertEqual(subject.availableSaveScopes, [.thisOccurrence, .futureOccurrences])
        XCTAssertNil(subject.scopeExplanation)
        XCTAssertTrue(service.updates.isEmpty)
        subject.confirm()
        XCTAssertEqual(service.updates.single?.scope, .thisOccurrence)
    }

    func testDirtyDraftRemainsDiscardProtectedAfterEveryUnavailableTransition() async {
        let transitions: [(RecordingCalendarService, EventEditorUnavailableReason)] = [
            (RecordingCalendarService(event: event()), .accessUnavailable),
            (RecordingCalendarService(events: [event(), nil]), .itemGone),
            (RecordingCalendarService(events: [event(), event(allowsModification: false)]), .readOnlySource),
            (RecordingCalendarService(events: [event(), event(mutationID: nil)]), .nonaddressable)
        ]

        for (service, reason) in transitions {
            let subject = EventEditorViewModel.edit(displayID: "display", service: service)
            await subject.load()
            subject.title = "Unsaved title"
            if reason == .accessUnavailable { service.accessState = .denied }

            await subject.requestSave()

            XCTAssertEqual(subject.phase, .unavailable(reason: reason))
            XCTAssertTrue(subject.requiresDiscardConfirmation)
            subject.confirmDiscard()
            XCTAssertFalse(subject.requiresDiscardConfirmation)
        }
    }

    private static let start = Date(timeIntervalSinceReferenceDate: 100)
    private static let end = Date(timeIntervalSinceReferenceDate: 200)
    private static let rule = RecurrenceRuleDraft(frequency: .daily, interval: 1, weekdays: [], endDate: nil)
    private var start: Date { Self.start }
    private var end: Date { Self.end }
    private var rule: RecurrenceRuleDraft { Self.rule }
    private func writable(_ id: String) -> CalendarDescriptor { .init(id: id, title: id, colorHex: "#000", allowsContentModifications: true) }
    private func readOnly(_ id: String) -> CalendarDescriptor { .init(id: id, title: id, colorHex: "#000", allowsContentModifications: false) }
    private func event(id: String = "display", mutationID: String? = "opaque", title: String = "Event", allowsModification: Bool = true, notes: String? = nil, location: String? = nil, url: URL? = nil, alarms: EventAlarmSnapshot = .none, recurrence: RecurrenceSnapshot = .none, eventStart: Date? = nil, eventEnd: Date? = nil, occurrenceDate: Date? = nil) -> CalendarEventSnapshot { .init(id: id, mutationID: mutationID, title: title, start: eventStart ?? start, end: eventEnd ?? end, isAllDay: false, calendarID: "home", calendarTitle: "Home", allowsModification: allowsModification, hasRecurrence: recurrence != .none, notes: notes, location: location, url: url, alarms: alarms, recurrence: recurrence, occurrenceDate: occurrenceDate) }

    private func mutationErrorTaxonomy(action: EventEditorAction) -> [(EventKitMutationError, EventEditorPhase)] {
        [
            (.accessUnavailable, .unavailable(reason: .accessUnavailable)),
            (.itemNotFound, .unavailable(reason: .itemGone)),
            (.itemReadOnly, .unavailable(reason: .readOnlySource)),
            (.defaultUnavailable, .failed(action: action, error: .invalidDestination)),
            (.destinationMissing, .failed(action: action, error: .invalidDestination)),
            (.destinationReadOnly, .failed(action: action, error: .invalidDestination)),
            (.invalidDraft, .failed(action: action, error: .validationFailure)),
            (.invalidRecurrence, .failed(action: action, error: .validationFailure)),
            (.invalidRecurrenceScope, .failed(action: action, error: .validationFailure)),
            (.saveFailed, .failed(action: action, error: .retryableWriteFailure)),
            (.removeFailed, .failed(action: action, error: .retryableWriteFailure))
        ]
    }
}

@MainActor
private final class EditorCategoryRepositoryStub: CategoryRepository {
    struct Assignment: Equatable {
        let categoryID: UUID?
        let source: ExternalItemSource
        let externalID: String
    }

    let values: [CategorySnapshot]
    private(set) var assignments: [Assignment] = []

    init(values: [CategorySnapshot]) {
        self.values = values
    }

    func list() throws -> [CategorySnapshot] { values }
    func create(name: String, colorHex: String) throws -> UUID { fatalError("Unused") }
    func update(id: UUID, name: String, colorHex: String) throws { fatalError("Unused") }
    func reorder(ids: [UUID]) throws { fatalError("Unused") }
    func delete(id: UUID, reassignedTo replacementID: UUID?) throws { fatalError("Unused") }
    func assign(categoryID: UUID?, to source: ExternalItemSource, externalID: String) throws {
        assignments.append(.init(categoryID: categoryID, source: source, externalID: externalID))
    }
    func category(for source: ExternalItemSource, externalID: String) throws -> CategorySnapshot? { nil }
    func removeUnresolvedLinks(for source: ExternalItemSource, validExternalIDs: Set<String>) throws { fatalError("Unused") }
    func seedDefaultsIfNeeded(settings: AppSettingsStore) throws { fatalError("Unused") }
}

@MainActor
private final class RecordingCalendarService: CalendarServicing {
    var accessState: AccessState
    var eventValue: CalendarEventSnapshot?
    var calendarValues: [CalendarDescriptor]
    var createID: String?
    var createError: Error?
    var updateError: Error?
    var deleteError: Error?
    var eventValues: [CalendarEventSnapshot?]
    var calendarResponses: [[CalendarDescriptor]]
    var onEventLookup: (() -> Void)?
    var occurrences: [EventOccurrenceAddress: CalendarEventSnapshot]
    private(set) var displayLookups: [String] = []
    private(set) var occurrenceLookups: [EventOccurrenceAddress] = []
    private(set) var occurrenceUpdates: [EventOccurrenceAddress?] = []
    private(set) var occurrenceDeletes: [EventOccurrenceAddress?] = []
    private(set) var creates: [EventDraft] = []
    private(set) var updates: [EventUpdateCall] = []
    private(set) var deletes: [EventDeleteCall] = []
    private(set) var fetchCount = 0

    init(access: AccessState = .granted, event: CalendarEventSnapshot? = nil, events: [CalendarEventSnapshot?] = [], occurrences: [EventOccurrenceAddress: CalendarEventSnapshot] = [:], calendars: [CalendarDescriptor] = [], calendarResponses: [[CalendarDescriptor]] = [], createID: String? = "created", createError: Error? = nil, updateError: Error? = nil, deleteError: Error? = nil) { self.accessState = access; eventValue = event; eventValues = events; self.occurrences = occurrences; calendarValues = calendars; self.calendarResponses = calendarResponses; self.createID = createID; self.createError = createError; self.updateError = updateError; self.deleteError = deleteError }
    func requestFullAccess() async -> AccessState { accessState }
    func calendars() -> [CalendarDescriptor] { calendarResponses.isEmpty ? calendarValues : calendarResponses.removeFirst() }
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] { fetchCount += 1; return [] }
    func createEvent(_ draft: EventDraft) throws -> String? { creates.append(draft); if let createError { throw createError }; return createID }
    func event(id: String) -> CalendarEventSnapshot? { displayLookups.append(id); onEventLookup?(); guard accessState == .granted else { return nil }; return eventValues.isEmpty ? eventValue : eventValues.removeFirst() }
    func event(id: String, occurrence: EventOccurrenceAddress?) -> CalendarEventSnapshot? {
        guard let occurrence else { return event(id: id) }
        occurrenceLookups.append(occurrence)
        return occurrences[occurrence]
    }
    func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws { updates.append(.init(id: id, draft: draft, scope: scope)); if let updateError { throw updateError } }
    func updateEvent(id: String, occurrence: EventOccurrenceAddress?, draft: EventDraft, scope: RecurrenceEditScope) throws {
        occurrenceUpdates.append(occurrence)
        try updateEvent(id: id, draft: draft, scope: scope)
    }
    func deleteEvent(id: String, scope: RecurrenceEditScope) throws { deletes.append(.init(id: id, scope: scope)); if let deleteError { throw deleteError } }
    func deleteEvent(id: String, occurrence: EventOccurrenceAddress?, scope: RecurrenceEditScope) throws {
        occurrenceDeletes.append(occurrence)
        try deleteEvent(id: id, scope: scope)
    }
}

private extension Array { var single: Element? { count == 1 ? first : nil } }
private enum Failure: Error { case write }

private final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
