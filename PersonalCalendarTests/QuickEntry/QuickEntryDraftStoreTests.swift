import XCTest
@testable import PersonalCalendar

@MainActor
final class QuickEntryDraftStoreTests: XCTestCase {
    func testRoundTripKeepsOnlyTheRequestedProfilesCorrectedDraft() {
        let defaults = UserDefaults.ephemeral
        let store = QuickEntryDraftStore(defaults: defaults)
        let schoolID = UUID()
        let personalID = UUID()
        let categoryID = UUID()
        let corrected = QuickEntryPreview(
            kind: .event,
            title: "Corrected lab review",
            startDate: draftDate(2026, 9, 12, 14),
            endDate: draftDate(2026, 9, 12, 15, 30),
            reminderDate: draftDate(2026, 9, 12, 13, 45),
            destinationID: "school-calendar",
            categoryID: categoryID
        )
        let snapshot = QuickEntryDraftSnapshot(
            profileID: schoolID,
            text: "lab review next friday",
            preview: corrected,
            parseTextMarker: "lab review next friday",
            eventDestinationID: "school-calendar",
            taskDestinationID: "school-tasks",
            eventDestinationWasExplicitlySelected: true,
            taskDestinationWasExplicitlySelected: false,
            intendedPhase: .confirmation,
            checkpointedAt: draftDate(2026, 9, 10, 8)
        )

        XCTAssertTrue(store.save(snapshot))

        let reloaded = QuickEntryDraftStore(defaults: defaults)
        XCTAssertEqual(reloaded.draft(for: schoolID), snapshot)
        XCTAssertNil(reloaded.draft(for: personalID))
    }

    func testCorruptAndOversizedStorageAreIgnoredWithoutPartialRecovery() {
        let corruptDefaults = UserDefaults.ephemeral
        corruptDefaults.set(Data("not-json".utf8), forKey: "drafts")
        XCTAssertNil(
            QuickEntryDraftStore(defaults: corruptDefaults, key: "drafts")
                .draft(for: UUID())
        )

        let oversizedDefaults = UserDefaults.ephemeral
        oversizedDefaults.set(
            Data(repeating: 0x61, count: QuickEntryDraftStore.maximumEncodedBytes + 1),
            forKey: "drafts"
        )
        XCTAssertNil(
            QuickEntryDraftStore(defaults: oversizedDefaults, key: "drafts")
                .draft(for: UUID())
        )
    }

    func testSaveRejectsOversizedTextWithoutReplacingExistingDraft() {
        let defaults = UserDefaults.ephemeral
        let store = QuickEntryDraftStore(defaults: defaults)
        let profileID = UUID()
        let original = draftSnapshot(profileID: profileID, text: "Keep me")
        XCTAssertTrue(store.save(original))

        let oversized = draftSnapshot(
            profileID: profileID,
            text: String(repeating: "x", count: QuickEntryDraftStore.maximumTextCharacters + 1)
        )
        XCTAssertFalse(store.save(oversized))
        XCTAssertEqual(store.draft(for: profileID), original)
    }

    func testReconcileDeletesDraftForRemovedProfileSoReusedNameCannotRecoverIt() {
        let store = QuickEntryDraftStore(defaults: .ephemeral)
        let deletedID = UUID()
        let keptID = UUID()
        XCTAssertTrue(store.save(draftSnapshot(profileID: deletedID, text: "Deleted profile secret")))
        XCTAssertTrue(store.save(draftSnapshot(profileID: keptID, text: "Keep")))

        store.reconcile(validProfileIDs: [keptID])

        XCTAssertNil(store.draft(for: deletedID))
        XCTAssertEqual(store.draft(for: keptID)?.text, "Keep")
    }

    func testSettingsProfileReconciliationAlsoRemovesDeletedProfileDraft() {
        let settings = AppSettingsStore(defaults: .ephemeral)
        let deletedID = UUID()
        let keptID = UUID()
        XCTAssertTrue(settings.quickEntryDrafts.save(
            draftSnapshot(profileID: deletedID, text: "Deleted profile secret")
        ))
        XCTAssertTrue(settings.quickEntryDrafts.save(
            draftSnapshot(profileID: keptID, text: "Keep")
        ))

        settings.reconcileQuickEntryHistory(validProfileIDs: [keptID])

        XCTAssertNil(settings.quickEntryDrafts.draft(for: deletedID))
        XCTAssertEqual(settings.quickEntryDrafts.draft(for: keptID)?.text, "Keep")
    }
}

private func draftSnapshot(profileID: UUID, text: String) -> QuickEntryDraftSnapshot {
    .init(
        profileID: profileID,
        text: text,
        preview: nil,
        parseTextMarker: nil,
        eventDestinationID: nil,
        taskDestinationID: nil,
        eventDestinationWasExplicitlySelected: false,
        taskDestinationWasExplicitlySelected: false,
        intendedPhase: .entry,
        checkpointedAt: draftDate(2026, 9, 10, 8)
    )
}

private func draftDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 0,
    _ minute: Int = 0
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
    return calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    ))!
}
