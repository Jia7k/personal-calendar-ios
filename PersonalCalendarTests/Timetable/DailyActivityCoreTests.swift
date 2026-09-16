import Foundation
import XCTest
@testable import PersonalCalendar

/// Written for the user-approved physical iPhone 16 Pro test run; no provider data is used.
final class DailyActivityCoreTests: XCTestCase {
    func testMixedOrderingChoosesEarliestActiveAndNeverRepeatsHero() {
        let snapshot = snapshot(items: [
            item("later-active", start: 9.5, end: 12),
            item("earlier-active", start: 9, end: 11),
            item("overdue", kind: .task, start: 8),
            item("next-task", kind: .task, start: 10.75),
            item("next-event", start: 11, end: 12),
            item("date-only", kind: .task, start: 0, allDay: true),
            item("all-day", start: 0, end: 24, allDay: true)
        ])
        let result = DailyActivityPresentation.make(snapshot: snapshot, now: date(10), rowLimit: 3)
        XCTAssertEqual(result.hero?.id, "earlier-active")
        XCTAssertEqual(result.rows.map(\.id), ["later-active", "overdue", "next-task"])
        XCTAssertEqual(result.hiddenCount, 3)
        XCTAssertEqual(result.remainingCount, 7)
        XCTAssertEqual(result.countdownBoundary, date(11))
        XCTAssertFalse(result.rows.contains { $0.id == result.hero?.id })
    }

    func testActiveTiesUseEndThenTitleThenStableIdentity() {
        let snapshot = snapshot(items: [
            item("z", start: 9, end: 11, title: "A"),
            item("a", start: 9, end: 11, title: "A"),
            item("b", start: 9, end: 12, title: "0"),
            item("c", start: 9, end: 11, title: "B")
        ])
        let result = DailyActivityPresentation.make(snapshot: snapshot, now: date(10), rowLimit: 10)
        XCTAssertEqual(result.hero?.id, "a")
        XCTAssertEqual(result.rows.map(\.id), ["z", "c", "b"])
    }

    func testTaskOnlyHeroUsesDueNotAlarmAndOverdueRemainsWithoutCountdown() {
        let reminder = task("task", due: date(10.75), alarm: .editable(date(8)))
        let snapshot = build(reminders: [reminder])
        let before = DailyActivityPresentation.make(snapshot: snapshot, now: date(10), rowLimit: 3)
        XCTAssertEqual(before.hero?.kind, .task)
        XCTAssertEqual(before.hero?.start, date(10.75))
        XCTAssertEqual(before.countdownBoundary, date(10.75))
        XCTAssertEqual(before.hero?.hasAlert, true)
        let after = DailyActivityPresentation.make(snapshot: snapshot, now: date(11), rowLimit: 3)
        XCTAssertNil(after.hero)
        XCTAssertNil(after.countdownBoundary)
        XCTAssertEqual(after.rows.count, 1)
        XCTAssertEqual(after.remainingCount, 1)
    }

    func testBuilderFiltersScopeCompletionUndatedPriorDayAndDeduplicates() {
        let duplicate = task("same", due: date(12))
        let result = build(events: [event("outside", calendarID: "other")], reminders: [
            duplicate, duplicate,
            task("prior", due: date(-1)), task("undated", due: nil),
            task("completed", due: date(12), completed: true),
            task("outside", due: date(12), listID: "other"),
            task("unsupported", due: date(13), alarm: .unsupported(summary: "Location alarm"))
        ])
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items.map(\.title).sorted(), ["same", "unsupported"])
        XCTAssertEqual(result.items.first { $0.title == "unsupported" }?.hasAlert, true)
        XCTAssertEqual(result.items.first { $0.title == "unsupported" }?.start, date(13))
        XCTAssertEqual(build(events: [event("outside")], reminders: [duplicate], scope: scope(empty: true)).items, [])
    }

    func testOvernightWeekendAndAllDayEventsAreIncluded() {
        // Fixture is Saturday 19 September, Singapore time.
        let result = build(events: [
            event("overnight", start: -1, end: 11),
            event("weekend", start: 12, end: 13),
            event("all-day", start: 0, end: 24, allDay: true),
            event("ended", start: 8, end: 10),
            event("tomorrow", start: 24, end: 25)
        ])
        XCTAssertEqual(Set(result.items.map(\.title)), ["overnight", "weekend", "all-day"])
        XCTAssertEqual(DailyActivityPresentation.make(snapshot: result, now: date(10), rowLimit: 3).hero?.title, "overnight")
    }

    func testSourceQualifiedIdentityAndRecurringOccurrenceAreStable() {
        let recurring = event("same", start: 12, end: 13, occurrence: date(9))
        let moved = event("same", start: 14, end: 15, occurrence: date(9))
        XCTAssertEqual(build(events: [recurring]).items.first?.id, build(events: [moved]).items.first?.id)
        let scoped = ProfileScope(identity: .everything, calendarIDs: ["calendar", "other"],
            reminderListIDs: ["tasks"], routineIDs: [], defaultCalendarID: nil, defaultReminderListID: nil)
        let first = build(events: [recurring, event("same", calendarID: "other"),
            event("same", start: 16, end: 17)], reminders: [task("same", due: date(12))], scope: scoped)
        XCTAssertEqual(Set(first.items.map(\.id)).count, 4)
        XCTAssertFalse(first.items.contains { $0.id.contains("calendar") || $0.id.contains("same") })
    }

    func testUntimedEmptyAndUnavailableDaysNeverInventCountdown() {
        let untimed = build(events: [event("all-day", start: 0, end: 24, allDay: true)],
            reminders: [task("date-only", due: date(0), hasTime: false)])
        let result = DailyActivityPresentation.make(snapshot: untimed, now: date(10), rowLimit: 3)
        XCTAssertNil(result.hero)
        XCTAssertNil(result.countdownBoundary)
        XCTAssertEqual(result.remainingCount, 2)
        let empty = DailyActivityPresentation.make(snapshot: snapshot(items: []), now: date(10), rowLimit: 3)
        XCTAssertEqual(empty.hiddenCount, 0)
        XCTAssertFalse(empty.requiresRefresh)
        let unavailable = DailyActivitySnapshot(profile: profile, dayStart: date(0), dayEnd: date(24),
            timeZoneIdentifier: "Asia/Singapore", generatedAt: date(10), items: [], tasksUnavailable: true)
        XCTAssertTrue(DailyActivityPresentation.make(snapshot: unavailable, now: date(10), rowLimit: 3).requiresRefresh)
    }

    func testDayRolloverAndMalformedDayFailClosed() {
        let valid = snapshot(items: [item("task", kind: .task, start: 12)])
        let after = DailyActivityPresentation.make(snapshot: valid, now: date(24), rowLimit: 3)
        XCTAssertTrue(after.requiresRefresh)
        XCTAssertNil(after.hero)
        XCTAssertNil(after.hiddenCount)
        XCTAssertTrue(after.rows.isEmpty)
        for value in [
            DailyActivitySnapshot(profile: profile, dayStart: date(0), dayEnd: date(24),
                timeZoneIdentifier: "Invalid/Zone", generatedAt: date(10), items: valid.items),
            DailyActivitySnapshot(profile: profile, dayStart: date(0), dayEnd: date(23),
                timeZoneIdentifier: "Asia/Singapore", generatedAt: date(10), items: valid.items)
        ] {
            XCTAssertTrue(DailyActivityPresentation.make(snapshot: value, now: date(10), rowLimit: 3).requiresRefresh)
            XCTAssertNil(DailyActivityPayload.make(snapshot: value, attributes: .init(snapshot: value), now: date(10)))
        }
        let invalidItem = item("bad", start: 12, end: 11)
        XCTAssertEqual(DailyActivityPresentation.make(snapshot: snapshot(items: [invalidItem]), now: date(10), rowLimit: 3).remainingCount, 0)
    }

    func testDSTUsesLocalCalendarDayRatherThanTwentyFourHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        for (month, day, expectedHours) in [(3, 8, 23), (11, 1, 25)] {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
            let snapshot = DailyActivitySnapshotBuilder(calendar: calendar).makeSnapshot(
                profile: profile, scope: scope(), events: [], reminders: [], now: now)
            XCTAssertEqual(snapshot.dayEnd.timeIntervalSince(snapshot.dayStart), Double(expectedHours * 3600))
            XCTAssertTrue(snapshot.hasValidDay)
        }
    }

    func testPayloadBoundsUnicodeStateAndCombinedAttributesThenRoundTripsKinds() throws {
        let long = String(repeating: "👩🏽‍💻\"\\\n", count: 400)
        let longProfile = DailyActivityProfile(id: .everything, name: long, symbolName: long)
        let snapshot = DailyActivitySnapshot(profile: longProfile, dayStart: date(0), dayEnd: date(24),
            timeZoneIdentifier: "Asia/Singapore", generatedAt: date(10), items:
                (0..<40).map { index in item("event-\(index)", start: 11, end: 12, title: long) }
                + [item("task", kind: .task, start: 10.5, title: long)])
        let attributes = TimetableActivityAttributes(snapshot: snapshot)
        let payload = try XCTUnwrap(DailyActivityPayload.make(snapshot: snapshot, attributes: attributes, now: date(10)))
        let state = TimetableActivityAttributes.ContentState(daily: payload)
        let encoded = try JSONEncoder().encode(state)
        let encodedAttributes = try JSONEncoder().encode(attributes)
        XCTAssertLessThanOrEqual(encoded.count, 3_500)
        XCTAssertLessThanOrEqual(encoded.count + encodedAttributes.count, 4_096)
        XCTAssertEqual(try JSONDecoder().decode(TimetableActivityAttributes.ContentState.self, from: encoded), state)
        XCTAssertTrue(payload.snapshot.items.contains { $0.kind == .task })
        XCTAssertTrue(payload.snapshot.items.contains { $0.kind == .event })
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(attributes.profileName).count, 96)
        for item in payload.snapshot.items {
            XCTAssertLessThanOrEqual(try JSONEncoder().encode(item.title).count, 160)
        }
    }

    func testOmittedTimedEventsExpireAndCannotProduceFalseNextOrAllDone() throws {
        let snapshot = snapshot(items: (0..<60).map { index in
            item("event-\(index)", start: 11, end: 12, title: String(repeating: "Long title ", count: 40))
        } + [item("persistent-task", kind: .task, start: 8)])
        let payload = try XCTUnwrap(DailyActivityPayload.make(snapshot: snapshot,
            attributes: .init(snapshot: snapshot), now: date(10)))
        XCTAssertFalse(payload.omissions.isEmpty)
        XCTAssertFalse(payload.omissionCountUnknown)
        let initial = payload.presentation(at: date(10), rowLimit: 3)
        XCTAssertEqual(initial.remainingCount, 61)
        XCTAssertEqual(initial.hiddenCount, 61 - initial.rows.count - (initial.hero == nil ? 0 : 1))
        let transition = payload.presentation(at: date(11), rowLimit: 3)
        XCTAssertTrue(transition.requiresRefresh)
        XCTAssertNil(transition.hero)
        XCTAssertNil(transition.countdownBoundary)
        let expired = payload.presentation(at: date(12), rowLimit: 3)
        XCTAssertEqual(expired.remainingCount, 1)
        XCTAssertEqual(expired.rows.first?.id, "persistent-task")
        XCTAssertEqual(expired.hiddenCount, 0)
        XCTAssertFalse(expired.requiresRefresh)
    }

    func testCappedOmissionMetadataUsesUnknownCountAndRefresh() throws {
        let snapshot = snapshot(items: (0..<120).map { index in
            item("event-\(index)", start: 11, end: 12 + Double(index) / 100,
                 title: String(repeating: "Title ", count: 80))
        })
        let payload = try XCTUnwrap(DailyActivityPayload.make(snapshot: snapshot,
            attributes: .init(snapshot: snapshot), now: date(10)))
        XCTAssertTrue(payload.omissionCountUnknown)
        XCTAssertLessThanOrEqual(payload.omissions.count, DailyActivityPayload.maximumOmissionBoundaries)
        let result = payload.presentation(at: date(10), rowLimit: 3)
        XCTAssertNil(result.hiddenCount)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertNil(result.hero)
        let expired = payload.presentation(at: date(23), rowLimit: 3)
        XCTAssertTrue(expired.requiresRefresh)
        XCTAssertNil(expired.hiddenCount)
    }

    func testVersionTwoAttributesAndOldContentStateDecodeWithoutDailyData() throws {
        let old: [String: Any] = ["schemaVersion": 2, "profileIdentity": "everything",
            "profileName": "Legacy", "weekStart": date(0).timeIntervalSinceReferenceDate,
            "timeZoneIdentifier": "Asia/Singapore"]
        let attributes = try JSONDecoder().decode(TimetableActivityAttributes.self,
            from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(attributes.isLegacy)
        XCTAssertNil(attributes.dayStart)
        let oldState = Data(#"{"g":0,"e":[],"o":2,"u":1}"#.utf8)
        let state = try JSONDecoder().decode(TimetableActivityAttributes.ContentState.self, from: oldState)
        XCTAssertNil(state.daily)
        XCTAssertEqual(state.omittedEntryCount, 2)
        XCTAssertEqual(state.sourceOmittedEntryCount, 1)
        XCTAssertFalse(TimetableActivityAttributes(snapshot: snapshot(items: [])).isLegacy)
        XCTAssertFalse(TimetableActivityAttributes(profileIdentity: .everything, profileName: "Compatibility",
            weekStart: date(0), timeZoneIdentifier: "Asia/Singapore").isLegacy)
    }

    func testNonfiniteClockAndInvalidMetadataFailClosed() throws {
        let badClock = Date(timeIntervalSinceReferenceDate: .nan)
        let built = DailyActivitySnapshotBuilder(calendar: calendar).makeSnapshot(
            profile: profile, scope: scope(), events: [event("event")], reminders: [], now: badClock)
        XCTAssertTrue(built.items.isEmpty)
        XCTAssertFalse(built.hasValidDay)
        let valid = snapshot(items: [item("event", start: 11, end: 12)])
        XCTAssertTrue(DailyActivityPresentation.make(snapshot: valid, now: badClock, rowLimit: 3).requiresRefresh)
        let malformed = DailyActivityPayload(snapshot: valid, omissions: [.init(expiresAt: date(24), count: -1)],
            omissionCountUnknown: false, heroVerifiedUntil: date(11))
        XCTAssertNil(malformed.presentation(at: date(10), rowLimit: 3).hiddenCount)
        XCTAssertTrue(malformed.presentation(at: date(10), rowLimit: 3).requiresRefresh)
        let overflow = DailyActivityPayload(snapshot: valid, omissions: [.init(expiresAt: date(24), count: Int.max)],
            omissionCountUnknown: false, heroVerifiedUntil: date(11))
        XCTAssertTrue(overflow.presentation(at: date(10), rowLimit: 3).requiresRefresh)
        XCTAssertNil(overflow.presentation(at: date(10), rowLimit: 3).hiddenCount)
    }

    func testDailyRouteUsesRepresentedDayProfileAndNoPrivateContentAfterRollover() throws {
        let snapshot = snapshot(items: [item("provider-secret", start: 12, end: 13, title: "Secret title")])
        let attributes = TimetableActivityAttributes(snapshot: snapshot)
        let payload = try XCTUnwrap(DailyActivityPayload.make(snapshot: snapshot, attributes: attributes, now: date(10)))
        let state = TimetableActivityAttributes.ContentState(daily: payload)
        let url = try XCTUnwrap(TimetableActivityRouteResolver().url(attributes: attributes, state: state, now: date(25)))
        XCTAssertEqual(try AppRouteCodec().route(from: url), .calendar(
            day: .init(year: 2026, month: 9, day: 19), profile: .everything, entryID: nil))
        XCTAssertFalse(url.absoluteString.contains("secret"))
        XCTAssertFalse(url.absoluteString.contains("provider"))
        let mismatched = DailyActivitySnapshot(profile: .init(id: .saved(UUID()), name: "Other", symbolName: "calendar"),
            dayStart: snapshot.dayStart, dayEnd: snapshot.dayEnd, timeZoneIdentifier: snapshot.timeZoneIdentifier,
            generatedAt: snapshot.generatedAt, items: snapshot.items)
        XCTAssertNil(TimetableActivityRouteResolver().url(attributes: .init(snapshot: mismatched), state: state, now: date(10)))
        XCTAssertNil(TimetableActivityRouteResolver().url(attributes: attributes,
            state: .init(generatedAt: date(10), entries: [], omittedEntryCount: 0, sourceOmittedEntryCount: 0), now: date(10)))
    }

    private var profile: DailyActivityProfile { .init(id: .everything, name: "Everything", symbolName: "calendar") }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }
    private func date(_ hours: Double) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 19))!.addingTimeInterval(hours * 3_600)
    }
    private func scope(empty: Bool = false) -> ProfileScope {
        .init(identity: .everything, calendarIDs: empty ? [] : ["calendar"], reminderListIDs: empty ? [] : ["tasks"],
              routineIDs: [], defaultCalendarID: nil, defaultReminderListID: nil)
    }
    private func snapshot(items: [DailyActivityItem]) -> DailyActivitySnapshot {
        .init(profile: profile, dayStart: date(0), dayEnd: date(24), timeZoneIdentifier: "Asia/Singapore",
              generatedAt: date(10), items: items)
    }
    private func item(_ id: String, kind: DailyActivityItem.Kind = .event, start: Double,
                      end: Double? = nil, allDay: Bool = false, title: String? = nil) -> DailyActivityItem {
        .init(id: id, kind: kind, title: title ?? id, shortTitle: "ITEM", start: date(start),
              end: end.map { date($0) }, isAllDay: allDay)
    }
    private func event(_ id: String, start: Double = 12, end: Double = 13,
                       allDay: Bool = false, calendarID: String = "calendar", occurrence: Date? = nil) -> CalendarEventSnapshot {
        .init(id: id, title: id, start: date(start), end: date(end), isAllDay: allDay, calendarID: calendarID,
              calendarTitle: "Calendar", allowsModification: false, hasRecurrence: occurrence != nil, occurrenceDate: occurrence)
    }
    private func task(_ id: String, due: Date?, hasTime: Bool = true, completed: Bool = false,
                      listID: String = "tasks", alarm: ReminderAlarmSnapshot = .none) -> ReminderSnapshot {
        .init(id: id, title: id, notes: nil, dueDate: due, dueHasTime: hasTime, priority: 0,
              listID: listID, listTitle: "Tasks", isCompleted: completed, allowsModification: false,
              hasRecurrence: false, alarm: alarm)
    }
    private func build(events: [CalendarEventSnapshot] = [], reminders: [ReminderSnapshot] = [],
                       scope: ProfileScope? = nil) -> DailyActivitySnapshot {
        DailyActivitySnapshotBuilder(calendar: calendar).makeSnapshot(profile: profile, scope: scope ?? self.scope(),
            events: events, reminders: reminders, now: date(10))
    }
}
