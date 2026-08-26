import XCTest
@testable import PersonalCalendar

final class CalendarSearchMatcherTests: XCTestCase {
    private let studyID = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!

    func testEmptyQueryReturnsNoPersonalResults() {
        let matcher = makeMatcher()
        let event = makeEvent(id: "cafe-seminar", title: "Café seminar", start: date(2026, 8, 25, 10))
        let corpus = matcher.makeCorpus(events: [event], reminders: [], routines: [], categories: [], now: now)

        XCTAssertEqual(matcher.sections(matching: "", corpus: corpus), .empty)
        XCTAssertEqual(matcher.sections(matching: "   ", corpus: corpus), .empty)
    }

    func testMatchingIsCaseAndDiacriticInsensitiveAndRequiresEveryToken() {
        let matcher = makeMatcher()
        let event = makeEvent(id: "cafe-seminar", title: "Café seminar", start: date(2026, 8, 25, 10))
        let corpus = matcher.makeCorpus(events: [event], reminders: [], routines: [], categories: [], now: now)

        XCTAssertEqual(upcomingIDs(matcher.sections(matching: "CAFE TUESDAY", corpus: corpus)), ["event|cafe-seminar"])
        XCTAssertTrue(upcomingIDs(matcher.sections(matching: "cafe friday", corpus: corpus)).isEmpty)
    }

    func testEventMatchesTitleRoomNotesSourceWeekdayAndLocalizedDate() {
        let matcher = makeMatcher()
        let event = makeEvent(
            id: "cafe-seminar",
            title: "Café seminar",
            start: date(2026, 8, 25, 10),
            location: "E2-07-14",
            notes: "Review the reading before class."
        )
        let corpus = matcher.makeCorpus(events: [event], reminders: [], routines: [], categories: [], now: now)

        for query in ["cafe", "e2-07-14", "reading", "event", "tuesday", "25 aug"] {
            XCTAssertEqual(upcomingIDs(matcher.sections(matching: query, corpus: corpus)), ["event|cafe-seminar"], "Query: \(query)")
        }
    }

    func testTaskMatchesTitleNotesListDueDateAndPriority() {
        let matcher = makeMatcher()
        let task = makeReminder(
            id: "submit-report",
            title: "Submit report",
            notes: "Review the draft.",
            dueDate: date(2026, 8, 26, 17),
            priority: 1,
            listTitle: "Study list"
        )
        let corpus = matcher.makeCorpus(events: [], reminders: [task], routines: [], categories: [], now: now)

        for query in ["submit", "draft", "study list", "26 aug", "high priority"] {
            XCTAssertEqual(upcomingIDs(matcher.sections(matching: query, corpus: corpus)), ["task|submit-report"], "Query: \(query)")
        }
    }

    func testRoutineMatchesTitleWindowWeekdaysAndCategory() {
        let matcher = makeMatcher()
        let category = CategorySnapshot(id: studyID, name: "Study", colorHex: "#3366FF", sortOrder: 0)
        let routine = RoutineSnapshot(
            id: UUID(uuidString: "B1000000-0000-4000-8000-000000000001")!,
            title: "Morning review",
            weekdays: [3, 5],
            window: .morning,
            reminderHour: nil,
            reminderMinute: nil,
            isPaused: false,
            isArchived: false,
            categoryID: studyID
        )
        let archived = RoutineSnapshot(
            id: UUID(uuidString: "B1000000-0000-4000-8000-000000000002")!,
            title: "Archived review",
            weekdays: [2],
            window: .morning,
            reminderHour: nil,
            reminderMinute: nil,
            isPaused: false,
            isArchived: true,
            categoryID: studyID
        )
        let corpus = matcher.makeCorpus(events: [], reminders: [], routines: [routine, archived], categories: [category], now: now)

        for query in ["morning review", "morning", "tuesday", "study"] {
            XCTAssertEqual(routineIDs(matcher.sections(matching: query, corpus: corpus)), ["routine|B1000000-0000-4000-8000-000000000001"], "Query: \(query)")
        }
        XCTAssertTrue(routineIDs(matcher.sections(matching: "archived", corpus: corpus)).isEmpty)
    }

    func testSectionsOrderUpcomingAscendingPastDescendingAndRoutinesAlphabetically() {
        let matcher = makeMatcher()
        let events = [
            makeEvent(id: "upcoming-late", title: "Item upcoming late", start: date(2026, 8, 27, 10)),
            makeEvent(id: "past-old", title: "Item past old", start: date(2026, 8, 20, 10)),
            makeEvent(id: "upcoming-early", title: "Item upcoming early", start: date(2026, 8, 25, 10)),
            makeEvent(id: "past-recent", title: "Item past recent", start: date(2026, 8, 23, 10))
        ]
        let completed = makeReminder(id: "completed", title: "Item completed", dueDate: date(2026, 8, 26, 9), priority: 0, listTitle: "Inbox", isCompleted: true)
        let routines = [
            makeRoutine(id: "C1000000-0000-4000-8000-000000000002", title: "Item Zebra"),
            makeRoutine(id: "C1000000-0000-4000-8000-000000000001", title: "Item Alpha")
        ]
        let corpus = matcher.makeCorpus(events: events, reminders: [completed], routines: routines, categories: [], now: now)

        let sections = matcher.sections(matching: "item", corpus: corpus)

        XCTAssertEqual(upcomingIDs(sections), ["event|upcoming-early", "event|upcoming-late"])
        XCTAssertEqual(pastIDs(sections), ["task|completed", "event|past-recent", "event|past-old"])
        XCTAssertEqual(routineIDs(sections), [
            "routine|C1000000-0000-4000-8000-000000000001",
            "routine|C1000000-0000-4000-8000-000000000002"
        ])
    }

    func testEachVisibleGroupIsCappedAtFiftyAfterMatching() {
        let matcher = makeMatcher()
        let upcoming = (0...50).map { offset in
            makeEvent(id: "upcoming-\(offset)", title: "Match upcoming \(offset)", start: calendar.date(byAdding: .hour, value: offset + 1, to: now)!)
        }
        let past = (0...50).map { offset in
            makeEvent(id: "past-\(offset)", title: "Match past \(offset)", start: calendar.date(byAdding: .hour, value: -(offset + 2), to: now)!)
        }
        let routines = (0...50).map { offset in
            makeRoutine(id: String(format: "D1000000-0000-4000-8000-%012d", offset + 1), title: "Match routine \(offset)")
        }
        let corpus = matcher.makeCorpus(events: upcoming + past, reminders: [], routines: routines, categories: [], now: now)

        let sections = matcher.sections(matching: "match", corpus: corpus)

        XCTAssertEqual(sections.upcoming.count, 50)
        XCTAssertEqual(sections.pastAndCompleted.count, 50)
        XCTAssertEqual(sections.routines.count, 50)
        XCTAssertEqual(sections.upcoming.first?.id, "event|upcoming-0")
        XCTAssertEqual(sections.pastAndCompleted.first?.id, "event|past-0")
        XCTAssertEqual(sections.routines.first?.id, "routine|D1000000-0000-4000-8000-000000000001")
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_SG")
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }

    private var now: Date { date(2026, 8, 24, 12) }

    private func makeMatcher() -> CalendarSearchMatcher {
        CalendarSearchMatcher(calendar: calendar, locale: Locale(identifier: "en_SG"))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeEvent(id: String, title: String, start: Date, location: String? = nil, notes: String? = nil) -> CalendarEventSnapshot {
        .init(id: id, title: title, start: start, end: calendar.date(byAdding: .hour, value: 1, to: start)!, isAllDay: false, calendarID: "school", calendarTitle: "School", allowsModification: true, hasRecurrence: false, notes: notes, location: location)
    }

    private func makeReminder(id: String, title: String, notes: String? = nil, dueDate: Date?, priority: Int, listTitle: String, isCompleted: Bool = false) -> ReminderSnapshot {
        .init(id: id, title: title, notes: notes, dueDate: dueDate, dueHasTime: true, priority: priority, listID: "study", listTitle: listTitle, isCompleted: isCompleted, allowsModification: true, hasRecurrence: false)
    }

    private func makeRoutine(id: String, title: String) -> RoutineSnapshot {
        .init(id: UUID(uuidString: id)!, title: title, weekdays: [2], window: .morning, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
    }

    private func upcomingIDs(_ sections: CalendarSearchSections) -> [String] { sections.upcoming.map(\.id) }
    private func pastIDs(_ sections: CalendarSearchSections) -> [String] { sections.pastAndCompleted.map(\.id) }
    private func routineIDs(_ sections: CalendarSearchSections) -> [String] { sections.routines.map(\.id) }
}
