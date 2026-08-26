import XCTest
@testable import PersonalCalendar

final class TimetableSnapshotBuilderTests: XCTestCase {
    func testBuildsMondayToFridaySnapshotFromTimedVisibleEvents() throws {
        let fixture = TimetableTestFixture()
        let subject = TimetableSnapshotBuilder(calendar: fixture.calendar)

        let snapshot = subject.makeSnapshot(
            access: .granted,
            events: fixture.weekEvents + [fixture.allDayEvent, fixture.saturdayEvent],
            now: fixture.tuesday0941
        )

        XCTAssertEqual(snapshot.version, TimetableSnapshotV1.currentVersion)
        XCTAssertEqual(TimetableSnapshotV1.currentVersion, 2)
        XCTAssertEqual(snapshot.availability, .ready)
        XCTAssertEqual(snapshot.weekStart, fixture.mondayStart)
        XCTAssertEqual(snapshot.timeZoneIdentifier, "Asia/Singapore")
        XCTAssertEqual(snapshot.entries.count, 9)
        XCTAssertEqual(snapshot.omittedEntryCount, 0)
        XCTAssertEqual(
            snapshot.entries.map(\.shortTitle),
            ["I01", "I06", "B05", "I03", "B05", "I03", "I06", "I01", "U22"]
        )
        XCTAssertFalse(snapshot.entries.contains {
            fixture.calendar.component(.weekday, from: $0.start) == 7
        })
    }

    func testMomentDistinguishesBeforeCurrentGapAndAfterSchool() throws {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.monday0840)

        XCTAssertEqual(snapshot.moment(at: fixture.monday0840, calendar: fixture.calendar), .next(snapshot.entries[0]))
        XCTAssertEqual(snapshot.moment(at: fixture.tuesday0941, calendar: fixture.calendar).entry?.shortTitle, "I03")
        XCTAssertEqual(snapshot.moment(at: fixture.monday1330, calendar: fixture.calendar).entry?.shortTitle, "B05")
        XCTAssertEqual(snapshot.moment(at: fixture.monday1830, calendar: fixture.calendar), .none)
    }

    func testPermissionLossContainsNoEventData() {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .denied, events: fixture.weekEvents, now: fixture.tuesday0941)

        XCTAssertEqual(snapshot.availability, .calendarAccessRequired)
        XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertEqual(snapshot.omittedEntryCount, 0)
    }

    func testDefaultBudgetKeepsTwentyFiveNormalWeeklyClasses() {
        let fixture = TimetableTestFixture()
        let events = fixture.twentyFiveClassWeek

        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: events, now: fixture.tuesday0941)

        XCTAssertEqual(snapshot.entries.count, 25)
        XCTAssertEqual(snapshot.omittedEntryCount, 0)
    }

    func testEncodedByteBudgetOmitsFurthestEntriesDeterministicallyAndReportsExactCount() throws {
        let fixture = TimetableTestFixture()
        let events = fixture.twentyFiveLongClassWeek
        let subject = TimetableSnapshotBuilder(
            calendar: fixture.calendar,
            maximumEncodedBytes: 2_000
        )

        let first = subject.makeSnapshot(
            access: .granted,
            events: events,
            now: fixture.tuesday0941
        )
        let reordered = subject.makeSnapshot(
            access: .granted,
            events: Array(events.reversed()),
            now: fixture.tuesday0941
        )

        XCTAssertFalse(first.entries.isEmpty)
        XCTAssertLessThan(first.entries.count, 25)
        XCTAssertEqual(first.omittedEntryCount, 25 - first.entries.count)
        XCTAssertEqual(first.entries, reordered.entries)
        XCTAssertEqual(first.omittedEntryCount, reordered.omittedEntryCount)
        XCTAssertEqual(try encoded(first), try encoded(reordered))
        XCTAssertLessThanOrEqual(try encoded(first).count, 2_000)
        XCTAssertEqual(
            first.entries.map(\.start),
            Array(events.map(\.start).sorted().prefix(first.entries.count))
        )
    }

    func testRouteIDsRemainStableWhenInputAndSortPositionChange() {
        let fixture = TimetableTestFixture()
        let later = fixture.event(
            "provider-later",
            "Later",
            day: 2,
            start: 12,
            end: 13,
            location: "Room 2"
        )
        let earlier = fixture.event(
            "provider-earlier",
            "Earlier",
            day: 1,
            start: 12,
            end: 13,
            location: "Room 1"
        )
        let inserted = fixture.event(
            "provider-inserted",
            "Inserted",
            day: 31,
            start: 8,
            end: 9,
            location: "Room 0"
        )
        let subject = TimetableSnapshotBuilder(calendar: fixture.calendar)

        let original = subject.makeSnapshot(
            access: .granted,
            events: [later, earlier],
            now: fixture.tuesday0941
        )
        let shifted = subject.makeSnapshot(
            access: .granted,
            events: [later, inserted, earlier],
            now: fixture.tuesday0941
        )

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: original.entries.map { ($0.title, $0.routeID) }),
            Dictionary(uniqueKeysWithValues: shifted.entries
                .filter { $0.title != "Inserted" }
                .map { ($0.title, $0.routeID) })
        )
        XCTAssertEqual(Set(shifted.entries.map(\.routeID)).count, 3)
    }

    func testEqualTimeEntriesUseLocaleIndependentLocationOrdering() {
        let fixture = TimetableTestFixture()
        let uppercase = fixture.event(
            "provider-z",
            "Seminar",
            day: 1,
            start: 12,
            end: 13,
            location: "A"
        )
        let lowercase = fixture.event(
            "provider-a",
            "Seminar",
            day: 1,
            start: 12,
            end: 13,
            location: "a"
        )

        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(
                access: .granted,
                events: [lowercase, uppercase],
                now: fixture.tuesday0941
            )

        XCTAssertEqual(snapshot.entries.compactMap(\.location), ["A", "a"])
    }

    func testEncodedSnapshotNeverContainsRawProviderOrMutationIdentifiers() throws {
        let fixture = TimetableTestFixture()
        let providerID = "raw-provider-display-id-should-not-leak"
        let mutationID = "raw-provider-mutation-id-should-not-leak"
        let event = fixture.event(
            providerID,
            "Private Seminar",
            day: 1,
            start: 14,
            end: 15,
            location: "Room 4",
            mutationID: mutationID
        )

        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: [event], now: fixture.tuesday0941)
        let json = String(decoding: try encoded(snapshot), as: UTF8.self)

        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertFalse(snapshot.entries[0].routeID.contains(providerID))
        XCTAssertFalse(snapshot.entries[0].routeID.contains(mutationID))
        XCTAssertFalse(json.contains(providerID))
        XCTAssertFalse(json.contains(mutationID))
    }

    func testVersionOneSnapshotFailsClosedInsteadOfInventingRouteIdentity() {
        let legacyJSON = """
        {
          "version": 1,
          "availability": "ready",
          "generatedAt": "2026-09-01T01:41:00Z",
          "weekStart": "2026-08-30T16:00:00Z",
          "timeZoneIdentifier": "Asia/Singapore",
          "entries": [{
            "id": "occurrence:1788224400000:0",
            "title": "Legacy class",
            "shortTitle": "LEGA",
            "start": "2026-09-01T02:00:00Z",
            "end": "2026-09-01T03:00:00Z",
            "location": "Room 1"
          }]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertThrowsError(
            try decoder.decode(TimetableSnapshotV1.self, from: Data(legacyJSON.utf8)),
            "Schema-v1 ordinal IDs must never be reused as route identities."
        )
    }

    private func encoded(_ snapshot: TimetableSnapshotV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }
}

struct TimetableTestFixture {
    let timeZone = TimeZone(identifier: "Asia/Singapore")!

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        value.locale = Locale(identifier: "en_SG")
        return value
    }

    func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: day == 31 ? 8 : 9,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    func event(
        _ id: String,
        _ title: String,
        day: Int,
        start: Int,
        end: Int,
        location: String,
        mutationID: String? = nil
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: mutationID ?? id,
            title: title,
            start: date(day: day, hour: start),
            end: date(day: day, hour: end),
            isAllDay: false,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: false,
            location: location
        )
    }

    var mondayStart: Date { date(day: 31, hour: 0) }
    var monday0840: Date { date(day: 31, hour: 8, minute: 40) }
    var monday0900: Date { date(day: 31, hour: 9) }
    var monday1100: Date { date(day: 31, hour: 11) }
    var monday1330: Date { date(day: 31, hour: 13, minute: 30) }
    var monday1830: Date { date(day: 31, hour: 18, minute: 30) }
    var tuesdayStart: Date { date(day: 1, hour: 0) }
    var tuesday0941: Date { date(day: 1, hour: 9, minute: 41) }

    var allDayEvent: CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: "holiday",
            title: "Holiday",
            start: mondayStart,
            end: tuesdayStart,
            isAllDay: true,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: false,
            hasRecurrence: false
        )
    }

    var saturdayEvent: CalendarEventSnapshot {
        event("sat", "INF 2099 Tutorial", day: 5, start: 9, end: 10, location: "Online")
    }

    var weekEvents: [CalendarEventSnapshot] {
        [
            event("i01-mon", "INF 2001 Lecture", day: 31, start: 9, end: 11, location: "Online"),
            event("i06-mon", "INF 2006 Lecture", day: 31, start: 11, end: 13, location: "Online"),
            event("b05-mon", "BAC 2005 Seminar", day: 31, start: 16, end: 18, location: "E2-02-07-SR204"),
            event("i03-tue", "INF 2003 Lecture", day: 1, start: 9, end: 11, location: "Online"),
            event("b05-wed", "BAC 2005 Laboratory", day: 2, start: 9, end: 11, location: "E2-08-01"),
            event("i03-wed", "INF 2003 Laboratory", day: 2, start: 11, end: 13, location: "E2-07-14"),
            event("i06-thu", "INF 2006 Laboratory", day: 3, start: 9, end: 11, location: "E2-03-05-SR223"),
            event("i01-thu", "INF 2001 Laboratory", day: 3, start: 11, end: 13, location: "E6-03-05-SR335"),
            event("u22-fri", "UDE 2222 Seminar", day: 4, start: 9, end: 12, location: "E6-03-05-SR335")
        ]
    }

    var twentyFiveClassWeek: [CalendarEventSnapshot] {
        [31, 1, 2, 3, 4].flatMap { day in
            [8, 10, 12, 14, 16].map { hour in
                event(
                    "provider-\(day)-\(hour)",
                    "CLS \(day)-\(hour)",
                    day: day,
                    start: hour,
                    end: hour + 1,
                    location: "Room \(day)-\(hour)"
                )
            }
        }
    }

    var twentyFiveLongClassWeek: [CalendarEventSnapshot] {
        twentyFiveClassWeek.map { value in
            CalendarEventSnapshot(
                id: value.id,
                mutationID: "mutation-\(value.id)",
                title: value.title + String(repeating: " very-long-title", count: 8),
                start: value.start,
                end: value.end,
                isAllDay: value.isAllDay,
                calendarID: value.calendarID,
                calendarTitle: value.calendarTitle,
                allowsModification: value.allowsModification,
                hasRecurrence: value.hasRecurrence,
                location: (value.location ?? "") + String(repeating: " long-location", count: 8)
            )
        }
    }
}
