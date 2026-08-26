import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class QuickEntryHistoryTests: XCTestCase {
    func testRecordTrimsFoldedDuplicatesMovesThemToMRUAndPersists() {
        let defaults = UserDefaults.ephemeral
        let profile: ProfileIdentity = .saved(UUID())
        let firstUse = Date(timeIntervalSinceReferenceDate: 100)
        let secondUse = Date(timeIntervalSinceReferenceDate: 200)
        let latestUse = Date(timeIntervalSinceReferenceDate: 300)
        let subject = AppSettingsStore(defaults: defaults).quickEntryHistory

        subject.record(
            text: "  Café planning  ",
            profileIdentity: profile,
            at: firstUse
        )
        subject.record(
            text: "Submit report",
            profileIdentity: profile,
            at: secondUse
        )
        subject.record(
            text: "CAFE PLANNING",
            profileIdentity: profile,
            at: latestUse
        )

        let reloaded = AppSettingsStore(defaults: defaults).quickEntryHistory
        let items = reloaded.items(for: profile)
        XCTAssertEqual(items.map(\.text), ["CAFE PLANNING", "Submit report"])
        XCTAssertEqual(items.map(\.lastUsedAt), [latestUse, secondUse])
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
    }

    func testRecordKeepsOnlyTenNewestItems() {
        let profile: ProfileIdentity = .saved(UUID())
        let subject = AppSettingsStore(defaults: .ephemeral).quickEntryHistory

        for index in 0..<11 {
            subject.record(
                text: "Entry \(index)",
                profileIdentity: profile,
                at: Date(timeIntervalSinceReferenceDate: TimeInterval(index))
            )
        }

        XCTAssertEqual(
            subject.items(for: profile).map(\.text),
            [
                "Entry 10", "Entry 9", "Entry 8", "Entry 7", "Entry 6",
                "Entry 5", "Entry 4", "Entry 3", "Entry 2", "Entry 1"
            ]
        )
    }

    func testHistoryAndPreferencesAreIsolatedBySavedProfileAndKind() {
        let schoolID = UUID()
        let workID = UUID()
        let school: ProfileIdentity = .saved(schoolID)
        let work: ProfileIdentity = .saved(workID)
        let schoolCategory = UUID()
        let workCategory = UUID()
        let subject = AppSettingsStore(defaults: .ephemeral).quickEntryHistory
        let schoolEvent = QuickEntryRememberedChoices(
            durationMinutes: 90,
            categoryID: schoolCategory,
            destinationID: "school-calendar"
        )
        let workTask = QuickEntryRememberedChoices(
            durationMinutes: nil,
            categoryID: workCategory,
            destinationID: "work-reminders"
        )

        subject.record(
            text: "Study session",
            profileIdentity: school,
            at: Date(timeIntervalSinceReferenceDate: 100)
        )
        subject.record(
            text: "Study session",
            profileIdentity: work,
            at: Date(timeIntervalSinceReferenceDate: 200)
        )
        subject.setPreference(schoolEvent, profileID: schoolID, kind: .event)
        subject.setPreference(workTask, profileID: workID, kind: .task)

        XCTAssertEqual(subject.items(for: school).map(\.text), ["Study session"])
        XCTAssertEqual(subject.items(for: work).map(\.text), ["Study session"])
        XCTAssertEqual(subject.preference(profileID: schoolID, kind: .event), schoolEvent)
        XCTAssertNil(subject.preference(profileID: schoolID, kind: .task))
        XCTAssertEqual(subject.preference(profileID: workID, kind: .task), workTask)
        XCTAssertNil(subject.preference(profileID: workID, kind: .event))
    }

    func testClearHistoryRemovesOnlyTheChosenSavedProfile() {
        let school: ProfileIdentity = .saved(UUID())
        let work: ProfileIdentity = .saved(UUID())
        let subject = AppSettingsStore(defaults: .ephemeral).quickEntryHistory

        subject.record(
            text: "Study session",
            profileIdentity: school,
            at: Date(timeIntervalSinceReferenceDate: 100)
        )
        subject.record(
            text: "Prepare report",
            profileIdentity: work,
            at: Date(timeIntervalSinceReferenceDate: 200)
        )

        subject.clearHistory(for: school)

        XCTAssertTrue(subject.items(for: school).isEmpty)
        XCTAssertEqual(subject.items(for: work).map(\.text), ["Prepare report"])
        subject.clearHistory(for: .everything)
        XCTAssertEqual(subject.items(for: work).map(\.text), ["Prepare report"])
    }

    func testUnsupportedOrMalformedStoredMemoryFailsClosed() throws {
        let unsupportedDefaults = UserDefaults.ephemeral
        let unsupported = QuickEntryMemoryV1(version: 99)
        unsupportedDefaults.set(
            try JSONEncoder().encode(unsupported),
            forKey: "quickEntryMemory"
        )

        XCTAssertTrue(
            AppSettingsStore(defaults: unsupportedDefaults)
                .quickEntryHistory.backupValue.history.isEmpty
        )

        let malformedDefaults = UserDefaults.ephemeral
        malformedDefaults.set(Data("not-json".utf8), forKey: "quickEntryMemory")

        XCTAssertEqual(
            AppSettingsStore(defaults: malformedDefaults)
                .quickEntryHistory.backupValue,
            QuickEntryMemoryV1()
        )
    }
}
