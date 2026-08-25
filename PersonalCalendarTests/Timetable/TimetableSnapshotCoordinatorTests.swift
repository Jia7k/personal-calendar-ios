import XCTest
@testable import PersonalCalendar

@MainActor
final class TimetableSnapshotCoordinatorTests: XCTestCase {
    func testRefreshFetchesSelectedWeekWritesSnapshotAndReloadsWidgetsOnce() throws {
        let fixture = TimetableTestFixture()
        let calendarService = RecordingTimetableCalendarService(events: fixture.weekEvents)
        let writer = RecordingTimetableWriter()
        let reloader = RecordingTimetableReloader()
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.replaceSelectedCalendarIDs(["school"], availableIDs: ["school", "personal"])
        let subject = TimetableSnapshotCoordinator(
            calendar: calendarService,
            settings: settings,
            builder: .init(calendar: fixture.calendar),
            writer: writer,
            reloader: reloader
        )

        let snapshot = try subject.refresh(now: fixture.tuesday0941)

        XCTAssertEqual(calendarService.requestedCalendarIDs, ["school"])
        XCTAssertEqual(calendarService.requestedIntervals, [
            DateInterval(start: fixture.mondayStart, end: fixture.date(day: 7, hour: 0))
        ])
        XCTAssertEqual(writer.values, [snapshot])
        XCTAssertEqual(reloader.reloadCount, 1)
        XCTAssertEqual(snapshot.entries.count, 9)
        XCTAssertEqual(subject.latestSnapshot, snapshot)
        XCTAssertNil(subject.errorMessage)
    }

    func testStoreRoundTripsVersionedJSONAtomically() throws {
        let fixture = TimetableTestFixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TimetableSnapshotStore(fileURL: directory.appendingPathComponent("timetable-v1.json"))
        let expected = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)

        try store.write(expected)

        XCTAssertEqual(try store.read(), expected)
    }

    func testDeniedAccessWritesPrivateEmptySnapshotWithoutFetchingEvents() throws {
        let fixture = TimetableTestFixture()
        let calendarService = RecordingTimetableCalendarService(access: .denied, events: fixture.weekEvents)
        let writer = RecordingTimetableWriter()
        let reloader = RecordingTimetableReloader()
        let subject = TimetableSnapshotCoordinator(
            calendar: calendarService,
            settings: AppSettingsStore(defaults: .ephemeral),
            builder: .init(calendar: fixture.calendar),
            writer: writer,
            reloader: reloader
        )

        let snapshot = try subject.refresh(now: fixture.tuesday0941)

        XCTAssertEqual(snapshot.availability, .calendarAccessRequired)
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertEqual(calendarService.fetchCount, 0)
        XCTAssertEqual(writer.values, [snapshot])
        XCTAssertEqual(reloader.reloadCount, 1)
    }
}

@MainActor
private final class RecordingTimetableCalendarService: CalendarServicing {
    var accessState: AccessState
    let events: [CalendarEventSnapshot]
    private(set) var requestedIntervals: [DateInterval] = []
    private(set) var requestedCalendarIDs: Set<String> = []
    private(set) var fetchCount = 0

    init(access: AccessState = .granted, events: [CalendarEventSnapshot]) {
        accessState = access
        self.events = events
    }

    func requestFullAccess() async -> AccessState { accessState }

    func calendars() -> [CalendarDescriptor] {
        guard accessState == .granted else { return [] }
        return [
            .init(id: "personal", title: "Personal", colorHex: "#000000", allowsContentModifications: true),
            .init(id: "school", title: "School", colorHex: "#000000", allowsContentModifications: true)
        ]
    }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        fetchCount += 1
        requestedIntervals.append(interval)
        requestedCalendarIDs = calendarIDs
        return events.filter { calendarIDs.contains($0.calendarID) }
    }

    func createEvent(_ draft: EventDraft) throws -> String? { nil }
    func event(id: String) -> CalendarEventSnapshot? { nil }
    func updateEvent(id: String, draft: EventDraft, scope: RecurrenceEditScope) throws {}
    func deleteEvent(id: String, scope: RecurrenceEditScope) throws {}
}

private final class RecordingTimetableWriter: TimetableSnapshotWriting {
    private(set) var values: [TimetableSnapshotV1] = []
    func write(_ value: TimetableSnapshotV1) throws { values.append(value) }
}

@MainActor
private final class RecordingTimetableReloader: TimetableWidgetReloading {
    private(set) var reloadCount = 0
    func reloadTimetableWidgets() { reloadCount += 1 }
}
