import XCTest
@testable import PersonalCalendar

@MainActor
final class QuickEntryDraftViewModelTests: XCTestCase {
    func testResumeRestoresCorrectedReviewWithoutParsingOrSaving() {
        let profileID = UUID()
        let categoryID = UUID()
        let store = QuickEntryDraftStore(defaults: .ephemeral)
        let sourceParser = DraftSequenceParser([.success(draftEventPreview())])
        let source = makeDraftSubject(
            profileID: profileID,
            parser: sourceParser,
            draftStore: store,
            categories: [draftCategory(categoryID)]
        )
        source.text = "Lab review next Friday"
        source.parse()
        source.preview?.title = "Corrected lab review"
        source.preview?.startDate = draftVMDate(2026, 9, 12, 14)
        source.preview?.endDate = draftVMDate(2026, 9, 12, 15, 30)
        source.preview?.categoryID = categoryID
        source.selectDestination("school-calendar")
        XCTAssertTrue(source.checkpointDraft())

        let resumeParser = DraftSequenceParser([.failure(.ambiguousExpression)])
        let saver = DraftRecordingSaver([.success(.event(id: "unexpected"))])
        let resumed = makeDraftSubject(
            profileID: profileID,
            parser: resumeParser,
            saver: saver,
            draftStore: store,
            categories: [draftCategory(categoryID)]
        )
        XCTAssertTrue(resumed.canResumeDraft)

        resumed.resumeDraft()

        XCTAssertEqual(resumeParser.callCount, 0)
        XCTAssertTrue(saver.received.isEmpty)
        XCTAssertEqual(resumed.phase, .confirmation(.ready))
        XCTAssertEqual(resumed.text, "Lab review next Friday")
        XCTAssertEqual(resumed.preview?.title, "Corrected lab review")
        XCTAssertEqual(resumed.preview?.startDate, draftVMDate(2026, 9, 12, 14))
        XCTAssertEqual(resumed.preview?.endDate, draftVMDate(2026, 9, 12, 15, 30))
        XCTAssertEqual(resumed.preview?.destinationID, "school-calendar")
        XCTAssertEqual(resumed.preview?.categoryID, categoryID)
    }

    func testResumeRevalidatesStaleCategoryAndDestinationAndExposesPastWarning() {
        let profileID = UUID()
        let store = QuickEntryDraftStore(defaults: .ephemeral)
        let stale = QuickEntryDraftSnapshot(
            profileID: profileID,
            text: "Old class",
            preview: QuickEntryPreview(
                kind: .event,
                title: "Old class",
                startDate: draftVMDate(2026, 9, 9, 9),
                endDate: draftVMDate(2026, 9, 9, 10),
                destinationID: "removed-calendar",
                categoryID: UUID()
            ),
            parseTextMarker: "Old class",
            eventDestinationID: "removed-calendar",
            taskDestinationID: nil,
            eventDestinationWasExplicitlySelected: true,
            taskDestinationWasExplicitlySelected: false,
            intendedPhase: .confirmation,
            checkpointedAt: draftVMDate(2026, 9, 9, 8)
        )
        XCTAssertTrue(store.save(stale))
        let subject = makeDraftSubject(profileID: profileID, draftStore: store)

        subject.resumeDraft()

        XCTAssertNil(subject.preview?.categoryID)
        XCTAssertEqual(subject.preview?.destinationID, "removed-calendar")
        XCTAssertFalse(subject.canSave)
        XCTAssertEqual(subject.warningMessage, "This event is scheduled in the past.")
    }

    func testExplicitDiscardAndSuccessfulSaveClearDraftButFailedSaveRetainsIt() {
        let discardProfileID = UUID()
        let discardStore = QuickEntryDraftStore(defaults: .ephemeral)
        XCTAssertTrue(discardStore.save(draftVMSnapshot(profileID: discardProfileID)))
        let discardSubject = makeDraftSubject(profileID: discardProfileID, draftStore: discardStore)
        discardSubject.resumeDraft()
        discardSubject.discardDraft()
        XCTAssertNil(discardStore.draft(for: discardProfileID))

        let successProfileID = UUID()
        let successStore = QuickEntryDraftStore(defaults: .ephemeral)
        let success = makeDraftSubject(
            profileID: successProfileID,
            saver: DraftRecordingSaver([.success(.event(id: "event-1"))]),
            draftStore: successStore
        )
        success.text = "Class tomorrow at 9am"
        success.parse()
        XCTAssertTrue(success.checkpointDraft())
        success.confirmSave()
        XCTAssertNil(successStore.draft(for: successProfileID))

        let failureProfileID = UUID()
        let failureStore = QuickEntryDraftStore(defaults: .ephemeral)
        let failure = makeDraftSubject(
            profileID: failureProfileID,
            saver: DraftRecordingSaver([.failure]),
            draftStore: failureStore
        )
        failure.text = "Class tomorrow at 9am"
        failure.parse()
        XCTAssertTrue(failure.checkpointDraft())
        failure.confirmSave()
        XCTAssertNotNil(failureStore.draft(for: failureProfileID))
    }

    func testAddAnotherSavesTwoDistinctItemsExactlyOnceAndBecomesInAppCapture() {
        let first = draftEventPreview(title: "First class")
        let second = QuickEntryPreview(
            kind: .task,
            title: "Second task",
            dueDate: draftVMDate(2026, 9, 11),
            destinationID: "school-tasks"
        )
        let parser = DraftSequenceParser([.success(first), .success(second)])
        let saver = DraftRecordingSaver([
            .success(.event(id: "event-1")),
            .success(.task(id: "task-1"))
        ])
        let subject = makeDraftSubject(
            profileID: UUID(),
            parser: parser,
            saver: saver,
            captureSource: .shortcut
        )
        subject.text = "First class"
        subject.parse()
        subject.confirmSave()

        subject.startAnotherEntry()

        XCTAssertEqual(subject.captureSource, .inApp)
        XCTAssertEqual(subject.phase, .entry(parseError: nil))
        XCTAssertEqual(subject.text, "")
        XCTAssertNil(subject.preview)
        subject.text = "Second task"
        subject.parse()
        subject.confirmSave()
        subject.confirmSave()

        XCTAssertEqual(saver.received.map(\.title), ["First class", "Second task"])
        XCTAssertEqual(subject.phase, .committed(.task(id: "task-1")))
    }

    func testResumeNeverOverwritesTypedInputOrShortcutCapture() {
        let profileID = UUID()
        let store = QuickEntryDraftStore(defaults: .ephemeral)
        XCTAssertTrue(store.save(draftVMSnapshot(profileID: profileID, text: "Recovered text")))

        let typed = makeDraftSubject(profileID: profileID, draftStore: store)
        typed.text = "What I am typing now"
        typed.resumeDraft()
        XCTAssertEqual(typed.text, "What I am typing now")
        XCTAssertNil(typed.preview)
        XCTAssertFalse(typed.checkpointDraft())
        XCTAssertEqual(store.draft(for: profileID)?.text, "Recovered text")

        let shortcut = makeDraftSubject(
            profileID: profileID,
            draftStore: store,
            captureSource: .shortcut
        )
        shortcut.text = "Queued shortcut"
        shortcut.resumeDraft()
        XCTAssertNil(shortcut.availableDraft)
        XCTAssertEqual(shortcut.text, "Queued shortcut")
        XCTAssertNil(shortcut.preview)
        XCTAssertFalse(shortcut.checkpointDraft())
        XCTAssertEqual(store.draft(for: profileID)?.text, "Recovered text")
    }

    func testEmptyUntouchedCaptureDoesNotCreateDraft() {
        let profileID = UUID()
        let store = QuickEntryDraftStore(defaults: .ephemeral)
        let subject = makeDraftSubject(profileID: profileID, draftStore: store)

        XCTAssertFalse(subject.checkpointDraft())
        XCTAssertNil(store.draft(for: profileID))
    }

    func testPendingRecoveryRejectsRecentSelectionAndCheckpointCannotReplaceIt() {
        let profileID = UUID()
        let store = QuickEntryDraftStore(defaults: .ephemeral)
        let correctedDraft = draftVMSnapshot(
            profileID: profileID,
            text: "Corrected stored draft"
        )
        XCTAssertTrue(store.save(correctedDraft))
        let history = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        history.record(
            text: "Recent item",
            profileIdentity: .saved(profileID),
            at: draftVMDate(2026, 9, 10, 7)
        )
        let subject = makeDraftSubject(
            profileID: profileID,
            draftStore: store,
            historyStore: history
        )
        guard let recentID = subject.recentEntries.first?.id else {
            return XCTFail("Expected a recent entry")
        }

        subject.selectRecent(id: recentID)
        let checkpointed = subject.checkpointDraft()

        XCTAssertEqual(subject.text, "")
        XCTAssertNil(subject.preview)
        XCTAssertFalse(checkpointed)
        XCTAssertEqual(store.draft(for: profileID), correctedDraft)
        XCTAssertTrue(subject.canResumeDraft)
    }

    func testShortcutAddAnotherSurfacesPreexistingDraftBeforeNewCheckpoint() {
        let profileID = UUID()
        let store = QuickEntryDraftStore(defaults: .ephemeral)
        let preexisting = draftVMSnapshot(
            profileID: profileID,
            text: "Resume this corrected draft"
        )
        XCTAssertTrue(store.save(preexisting))
        let subject = makeDraftSubject(
            profileID: profileID,
            saver: DraftRecordingSaver([.success(.event(id: "shortcut-event"))]),
            draftStore: store,
            captureSource: .shortcut
        )
        subject.text = "Queued shortcut capture"
        subject.parse()
        subject.confirmSave()

        subject.startAnotherEntry()

        XCTAssertEqual(subject.captureSource, .inApp)
        XCTAssertEqual(subject.availableDraft, preexisting)
        XCTAssertTrue(subject.canResumeDraft)
        XCTAssertFalse(subject.checkpointDraft())
        XCTAssertEqual(store.draft(for: profileID), preexisting)
    }

    func testDeletingAllTypedTextClearsOnlyTheCurrentCapturesCheckpoint() {
        let profileID = UUID()
        let store = QuickEntryDraftStore(defaults: .ephemeral)
        let subject = makeDraftSubject(profileID: profileID, draftStore: store)
        subject.text = "Temporary capture"
        XCTAssertTrue(subject.checkpointDraft())
        XCTAssertEqual(store.draft(for: profileID)?.text, "Temporary capture")

        subject.text = ""
        XCTAssertFalse(subject.checkpointDraft())

        XCTAssertNil(store.draft(for: profileID))

        let unresolved = draftVMSnapshot(
            profileID: profileID,
            text: "Unresolved original"
        )
        XCTAssertTrue(store.save(unresolved))
        let recovery = makeDraftSubject(profileID: profileID, draftStore: store)
        XCTAssertFalse(recovery.checkpointDraft())
        XCTAssertEqual(store.draft(for: profileID), unresolved)
    }
}

private enum DraftSaverStep { case success(QuickEntrySaveOutcome), failure }

@MainActor
private final class DraftRecordingSaver: QuickEntrySaving {
    private(set) var received: [QuickEntryPreview] = []
    private var steps: [DraftSaverStep]

    init(_ steps: [DraftSaverStep] = [.success(.event(id: "event"))]) {
        self.steps = steps
    }

    func save(_ preview: QuickEntryPreview) throws -> QuickEntrySaveOutcome {
        received.append(preview)
        let step = steps.removeFirst()
        switch step {
        case let .success(outcome): return outcome
        case .failure: throw DraftTestError.failed
        }
    }
}

private final class DraftSequenceParser: QuickEntryParsing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<QuickEntryPreview, QuickEntryParseError>]
    private var calls = 0

    init(_ results: [Result<QuickEntryPreview, QuickEntryParseError>]) {
        self.results = results
    }

    var callCount: Int { lock.withLock { calls } }

    func parse(_ text: String, context: QuickEntryParseContext) throws -> QuickEntryPreview {
        try lock.withLock {
            calls += 1
            return try results.removeFirst().get()
        }
    }
}

private enum DraftTestError: Error { case failed }

@MainActor
private func makeDraftSubject(
    profileID: UUID,
    parser: DraftSequenceParser = DraftSequenceParser([.success(draftEventPreview())]),
    saver: DraftRecordingSaver = DraftRecordingSaver(),
    draftStore: QuickEntryDraftStore? = nil,
    historyStore: QuickEntryHistoryStore? = nil,
    categories: [CategorySnapshot] = [],
    captureSource: QuickEntryCaptureSource = .inApp
) -> QuickEntryViewModel {
    QuickEntryViewModel(
        parser: parser,
        saver: saver,
        context: QuickEntryParseContext(
            now: draftVMDate(2026, 9, 10, 8),
            calendar: draftVMCalendar(),
            locale: Locale(identifier: "en_SG"),
            timeZone: draftVMCalendar().timeZone
        ),
        destinations: QuickEntryDestinationOptions(
            calendarAccess: .granted,
            remindersAccess: .granted,
            calendars: [draftCalendar("school-calendar")],
            reminderLists: [draftList("school-tasks")],
            defaultCalendarID: "school-calendar",
            defaultReminderListID: "school-tasks",
            visibleCalendarIDs: ["school-calendar"],
            visibleReminderListIDs: ["school-tasks"]
        ),
        categories: categories,
        creationProfile: CreationProfileContext(
            profileID: profileID,
            profileName: "School",
            memberCalendarIDs: ["school-calendar"],
            memberReminderListIDs: ["school-tasks"],
            defaultCalendarID: "school-calendar",
            defaultReminderListID: "school-tasks",
            requiresExplicitCalendarDestination: false,
            requiresExplicitReminderDestination: false
        ),
        historyStore: historyStore,
        draftStore: draftStore,
        captureSource: captureSource
    )
}

private func draftVMSnapshot(
    profileID: UUID,
    text: String = "Class tomorrow at 9am"
) -> QuickEntryDraftSnapshot {
    .init(
        profileID: profileID,
        text: text,
        preview: draftEventPreview(),
        parseTextMarker: text,
        eventDestinationID: "school-calendar",
        taskDestinationID: "school-tasks",
        eventDestinationWasExplicitlySelected: false,
        taskDestinationWasExplicitlySelected: false,
        intendedPhase: .confirmation,
        checkpointedAt: draftVMDate(2026, 9, 10, 8)
    )
}

private func draftEventPreview(title: String = "Class") -> QuickEntryPreview {
    .init(
        kind: .event,
        title: title,
        startDate: draftVMDate(2026, 9, 11, 9),
        endDate: draftVMDate(2026, 9, 11, 10),
        destinationID: "school-calendar"
    )
}

private func draftCategory(_ id: UUID) -> CategorySnapshot {
    .init(id: id, name: "Study", colorHex: "#4868A8", sortOrder: 0)
}

private func draftCalendar(_ id: String) -> CalendarDescriptor {
    .init(id: id, title: "School", colorHex: "#4868A8", allowsContentModifications: true)
}

private func draftList(_ id: String) -> ReminderListDescriptor {
    .init(id: id, title: "School Tasks", colorHex: "#4868A8", allowsContentModifications: true)
}

private func draftVMCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
    calendar.locale = Locale(identifier: "en_SG")
    return calendar
}

private func draftVMDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 0,
    _ minute: Int = 0
) -> Date {
    draftVMCalendar().date(from: DateComponents(
        timeZone: draftVMCalendar().timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    ))!
}
