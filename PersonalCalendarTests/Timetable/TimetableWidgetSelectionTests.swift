import Foundation
import XCTest
@testable import PersonalCalendar

final class TimetableWidgetSelectionTests: XCTestCase {
    private static let schoolID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let personalID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let deletedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private static let accessRequiredID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private static let emptyID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private static let noClassesID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

    func testNilSelectionRequiresExplicitProfileChoice() {
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(nil, in: catalog),
            .chooseProfile
        )
    }

    func testDeletedSavedProfileDoesNotFallBackToEverything() {
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(.saved(Self.deletedID), in: catalog),
            .profileDeleted
        )
    }

    func testValidSavedProfileResolvesOnlyItsSnapshot() {
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(.saved(Self.schoolID), in: catalog),
            .ready(schoolSnapshot)
        )
    }

    func testEverythingSelectionResolvesUnionSnapshot() {
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(.everything, in: catalog),
            .ready(everythingSnapshot)
        )
    }

    func testTwoWidgetConfigurationsResolveDifferentProfilesFromOneCatalog() {
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(.saved(Self.schoolID), in: catalog),
            .ready(schoolSnapshot)
        )
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(.saved(Self.personalID), in: catalog),
            .ready(personalSnapshot)
        )
    }

    func testCalendarAccessRequiredSelectionDoesNotResolveAsReadyContent() {
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(.saved(Self.accessRequiredID), in: catalog),
            .calendarAccessRequired
        )
    }

    func testEmptyProfileSelectionDoesNotResolveAsReadyContent() {
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(.saved(Self.emptyID), in: catalog),
            .emptyProfile
        )
    }

    func testReadyProfileWithoutClassesResolvesNoClassesState() {
        XCTAssertEqual(
            TimetableWidgetSelectionResolver.resolve(.saved(Self.noClassesID), in: catalog),
            .noClasses
        )
    }

    private var catalog: TimetableWidgetCatalogV1 {
        TimetableWidgetCatalogV1(
            version: TimetableWidgetCatalogV1.currentVersion,
            generatedAt: Self.generatedAt,
            profiles: [
                TimetableWidgetProfile(
                    id: .saved(Self.schoolID),
                    name: "School",
                    colorHex: "#4F6F64",
                    symbolName: "graduationcap.fill",
                    snapshot: schoolSnapshot
                ),
                TimetableWidgetProfile(
                    id: .saved(Self.personalID),
                    name: "Personal",
                    colorHex: "#C8795B",
                    symbolName: "person.fill",
                    snapshot: personalSnapshot
                ),
                TimetableWidgetProfile(
                    id: .everything,
                    name: "Everything",
                    colorHex: "#556070",
                    symbolName: "rectangle.3.group.fill",
                    snapshot: everythingSnapshot
                ),
                TimetableWidgetProfile(
                    id: .saved(Self.accessRequiredID),
                    name: "Unavailable",
                    colorHex: "#556070",
                    symbolName: "calendar.badge.exclamationmark",
                    snapshot: snapshot(availability: .calendarAccessRequired)
                ),
                TimetableWidgetProfile(
                    id: .saved(Self.emptyID),
                    name: "Empty",
                    colorHex: "#556070",
                    symbolName: "calendar",
                    snapshot: snapshot(availability: .emptyProfile)
                ),
                TimetableWidgetProfile(
                    id: .saved(Self.noClassesID),
                    name: "No Classes",
                    colorHex: "#556070",
                    symbolName: "calendar",
                    snapshot: snapshot(availability: .noClasses)
                )
            ]
        )
    }

    private var schoolSnapshot: TimetableSnapshotV1 {
        snapshot(entries: [Self.math])
    }

    private var personalSnapshot: TimetableSnapshotV1 {
        snapshot(entries: [Self.dentist])
    }

    private var everythingSnapshot: TimetableSnapshotV1 {
        snapshot(entries: [Self.math, Self.dentist])
    }

    private func snapshot(
        availability: TimetableAvailability = .ready,
        entries: [TimetableEntry] = []
    ) -> TimetableSnapshotV1 {
        TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: availability,
            generatedAt: Self.generatedAt,
            weekStart: Self.weekStart,
            timeZoneIdentifier: "Asia/Singapore",
            entries: entries
        )
    }

    private static let generatedAt = Date(timeIntervalSince1970: 1_788_190_200)
    private static let weekStart = Date(timeIntervalSince1970: 1_788_105_600)

    private static let math = TimetableEntry(
        id: "occurrence:1788138000000:0",
        title: "INF 2001 Lecture",
        shortTitle: "I01",
        start: Date(timeIntervalSince1970: 1_788_138_000),
        end: Date(timeIntervalSince1970: 1_788_145_200),
        location: "Online"
    )

    private static let dentist = TimetableEntry(
        id: "occurrence:1788224400000:0",
        title: "Dentist",
        shortTitle: "Dentist",
        start: Date(timeIntervalSince1970: 1_788_224_400),
        end: Date(timeIntervalSince1970: 1_788_228_000),
        location: "Clinic"
    )
}
