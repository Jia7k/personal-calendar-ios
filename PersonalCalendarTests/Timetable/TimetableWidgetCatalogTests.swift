import XCTest
@testable import PersonalCalendar

final class TimetableWidgetCatalogTests: XCTestCase {
    private static let schoolID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let personalID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testCatalogRoundTripKeepsIndependentProfileSnapshotsAndDeduplicatedEverythingUnion() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("timetable-catalog-v1.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let generatedAt = date(hour: 8)
        let math = entry(
            id: "occurrence:1788141600000:0",
            title: "INF 2001 Lecture",
            startHour: 9,
            endHour: 11
        )
        let dentist = entry(
            id: "occurrence:1788163200000:0",
            title: "Dentist",
            startHour: 15,
            endHour: 16
        )
        let shared = entry(
            id: "occurrence:1788166800000:0",
            title: "Study Group",
            startHour: 16,
            endHour: 17
        )
        let catalog = TimetableWidgetCatalogV1(
            version: TimetableWidgetCatalogV1.currentVersion,
            generatedAt: generatedAt,
            profiles: [
                profile(
                    id: .saved(Self.schoolID),
                    name: "School",
                    colorHex: "#345995",
                    symbolName: "graduationcap.fill",
                    generatedAt: generatedAt,
                    entries: [math, shared]
                ),
                profile(
                    id: .saved(Self.personalID),
                    name: "Personal",
                    colorHex: "#8C6A5D",
                    symbolName: "person.fill",
                    generatedAt: generatedAt,
                    entries: [dentist, shared]
                ),
                profile(
                    id: .everything,
                    name: "Everything",
                    colorHex: "#4D7C6F",
                    symbolName: "square.stack.3d.up.fill",
                    generatedAt: generatedAt,
                    entries: [math, dentist, shared]
                )
            ]
        )
        let store = TimetableWidgetCatalogStore(fileURL: file)

        try store.write(catalog)

        let restored = try store.read()
        XCTAssertEqual(restored, catalog)
        XCTAssertEqual(
            restored.snapshot(for: .saved(Self.schoolID))?.entries,
            [math, shared]
        )
        XCTAssertEqual(
            restored.snapshot(for: .saved(Self.personalID))?.entries,
            [dentist, shared]
        )
        XCTAssertEqual(
            restored.snapshot(for: .everything)?.entries,
            [math, dentist, shared]
        )
        XCTAssertEqual(
            restored.snapshot(for: .everything)?.entries.filter { $0.title == shared.title }.count,
            1
        )
    }

    private func profile(
        id: ProfileIdentity,
        name: String,
        colorHex: String,
        symbolName: String,
        generatedAt: Date,
        entries: [TimetableEntry]
    ) -> TimetableWidgetProfile {
        TimetableWidgetProfile(
            id: id,
            name: name,
            colorHex: colorHex,
            symbolName: symbolName,
            snapshot: TimetableSnapshotV1(
                version: TimetableSnapshotV1.currentVersion,
                availability: .ready,
                generatedAt: generatedAt,
                weekStart: date(hour: 0),
                timeZoneIdentifier: "Asia/Singapore",
                entries: entries
            )
        )
    }

    private func entry(
        id: String,
        title: String,
        startHour: Int,
        endHour: Int
    ) -> TimetableEntry {
        TimetableEntry(
            id: id,
            title: title,
            shortTitle: String(title.prefix(4)).uppercased(),
            start: date(hour: startHour),
            end: date(hour: endHour),
            location: nil
        )
    }

    private func date(hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 31,
            hour: hour
        ))!
    }
}
