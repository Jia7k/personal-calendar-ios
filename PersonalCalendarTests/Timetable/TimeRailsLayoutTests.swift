import XCTest
@testable import PersonalCalendar

final class TimeRailsLayoutTests: XCTestCase {
    func testDefaultBoundsAreEightToSixAndPreserveGeometry() throws {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: fixture.weekEvents, now: fixture.tuesday0941)
        let subject = TimeRailsLayout(calendar: fixture.calendar, snapshot: snapshot)
        let placements = subject.placements(snapshot: snapshot)

        let friday = try XCTUnwrap(placements.first { $0.entry.shortTitle == "U22" })
        let tuesday = try XCTUnwrap(placements.first {
            $0.entry.shortTitle == "I03" && $0.weekdayIndex == 1
        })
        let mondayLate = try XCTUnwrap(placements.first {
            $0.entry.shortTitle == "B05" && $0.weekdayIndex == 0
        })

        XCTAssertEqual(subject.startMinute, 8 * 60)
        XCTAssertEqual(subject.endMinute, 18 * 60)
        XCTAssertEqual(friday.heightFraction, 3.0 / 10.0, accuracy: 0.001)
        XCTAssertEqual(tuesday.heightFraction, 2.0 / 10.0, accuracy: 0.001)
        XCTAssertEqual(mondayLate.startFraction, 8.0 / 10.0, accuracy: 0.001)
    }

    func testAdaptiveBoundsRoundOutwardAndRetainEarlyAndLateEntries() throws {
        let fixture = TimetableTestFixture()
        let events = [
            event(
                fixture: fixture,
                id: "early",
                title: "EAR 1001 Lecture",
                day: 1,
                startHour: 7,
                startMinute: 30,
                endHour: 8,
                endMinute: 30
            ),
            event(
                fixture: fixture,
                id: "late",
                title: "LATE 2001 Seminar",
                day: 1,
                startHour: 21,
                endHour: 22
            )
        ]
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: events, now: fixture.tuesday0941)
        let subject = TimeRailsLayout(calendar: fixture.calendar, snapshot: snapshot)
        let placements = subject.placements(snapshot: snapshot)

        XCTAssertEqual(subject.startMinute, 7 * 60)
        XCTAssertEqual(subject.endMinute, 22 * 60)
        XCTAssertEqual(
            Set(placements.map(\.entry.title)),
            ["EAR 1001 Lecture", "LATE 2001 Seminar"]
        )

        let early = try XCTUnwrap(placements.first { $0.entry.title == "EAR 1001 Lecture" })
        let late = try XCTUnwrap(placements.first { $0.entry.title == "LATE 2001 Seminar" })
        XCTAssertEqual(early.startFraction, 0.5 / 15.0, accuracy: 0.001)
        XCTAssertEqual(early.heightFraction, 1.0 / 15.0, accuracy: 0.001)
        XCTAssertEqual(late.startFraction, 14.0 / 15.0, accuracy: 0.001)
        XCTAssertEqual(late.heightFraction, 1.0 / 15.0, accuracy: 0.001)
    }

    func testDayEdgeEntriesUseClampedFullDayBoundsAndRemainPlaced() throws {
        let fixture = TimetableTestFixture()
        let events = [
            event(
                fixture: fixture,
                id: "after-midnight",
                title: "EAR 0001 Lecture",
                day: 1,
                startHour: 0,
                startMinute: 15,
                endHour: 1
            ),
            event(
                fixture: fixture,
                id: "crossing-midnight",
                title: "LATE 2359 Seminar",
                day: 1,
                startHour: 23,
                startMinute: 30,
                endDay: 2,
                endHour: 0,
                endMinute: 30
            )
        ]
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(access: .granted, events: events, now: fixture.tuesday0941)
        let subject = TimeRailsLayout(calendar: fixture.calendar, snapshot: snapshot)
        let placements = subject.placements(snapshot: snapshot)

        XCTAssertEqual(subject.startMinute, 0)
        XCTAssertEqual(subject.endMinute, 24 * 60)
        XCTAssertEqual(
            Set(placements.map(\.entry.title)),
            ["EAR 0001 Lecture", "LATE 2359 Seminar"]
        )

        let early = try XCTUnwrap(placements.first { $0.entry.title == "EAR 0001 Lecture" })
        let crossing = try XCTUnwrap(placements.first { $0.entry.title == "LATE 2359 Seminar" })
        XCTAssertEqual(early.startFraction, 15.0 / 1_440.0, accuracy: 0.001)
        XCTAssertEqual(early.heightFraction, 45.0 / 1_440.0, accuracy: 0.001)
        XCTAssertEqual(crossing.startFraction, 1_410.0 / 1_440.0, accuracy: 0.001)
        XCTAssertEqual(crossing.heightFraction, 30.0 / 1_440.0, accuracy: 0.001)
    }

    func testDateFractionUsesAdaptiveBoundsAndRejectsOutsideRange() throws {
        let fixture = TimetableTestFixture()
        let snapshot = TimetableSnapshotBuilder(calendar: fixture.calendar)
            .makeSnapshot(
                access: .granted,
                events: [
                    event(
                        fixture: fixture,
                        id: "early",
                        title: "EAR 1001 Lecture",
                        day: 1,
                        startHour: 7,
                        startMinute: 30,
                        endHour: 8,
                        endMinute: 30
                    ),
                    event(
                        fixture: fixture,
                        id: "late",
                        title: "LATE 2001 Seminar",
                        day: 1,
                        startHour: 21,
                        endHour: 22
                    )
                ],
                now: fixture.tuesday0941
            )
        let subject = TimeRailsLayout(calendar: fixture.calendar, snapshot: snapshot)

        XCTAssertEqual(
            try XCTUnwrap(subject.fraction(for: fixture.date(day: 1, hour: 14, minute: 30))),
            0.5,
            accuracy: 0.001
        )
        XCTAssertNil(subject.fraction(for: fixture.date(day: 1, hour: 6, minute: 59)))
        XCTAssertNil(subject.fraction(for: fixture.date(day: 1, hour: 22, minute: 1)))
    }

    private func event(
        fixture: TimetableTestFixture,
        id: String,
        title: String,
        day: Int,
        startHour: Int,
        startMinute: Int = 0,
        endDay: Int? = nil,
        endHour: Int,
        endMinute: Int = 0
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: id,
            title: title,
            start: fixture.date(day: day, hour: startHour, minute: startMinute),
            end: fixture.date(day: endDay ?? day, hour: endHour, minute: endMinute),
            isAllDay: false,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: false
        )
    }
}
