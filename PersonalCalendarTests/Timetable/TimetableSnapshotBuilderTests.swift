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

        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.availability, .ready)
        XCTAssertEqual(snapshot.weekStart, fixture.mondayStart)
        XCTAssertEqual(snapshot.timeZoneIdentifier, "Asia/Singapore")
        XCTAssertEqual(snapshot.entries.count, 9)
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
        location: String
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: id,
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
}
