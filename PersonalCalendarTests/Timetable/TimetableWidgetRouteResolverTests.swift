import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class TimetableWidgetRouteResolverTests: XCTestCase {
    private let subject = TimetableWidgetRouteResolver()
    private let codec = AppRouteCodec()

    func testNextClassUsesCurrentOccurrenceOpaqueRouteIDAndExactProfile() throws {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
        )
        let routeID = "entry-0123456789abcdef"
        let snapshot = makeSnapshot(
            timeZoneIdentifier: "Asia/Singapore",
            entries: [
                entry(
                    id: "occurrence:1787799000000:0",
                    routeID: routeID,
                    start: "2026-08-26T16:10:00Z",
                    end: "2026-08-26T17:10:00Z"
                )
            ]
        )

        let route = try decodedRoute(subject.nextClassURL(
            content: .ready(profile: profile, profileName: "School", snapshot: snapshot),
            date: instant("2026-08-26T16:30:00Z")
        ))

        XCTAssertEqual(
            route,
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: profile,
                entryID: routeID
            )
        )
    }

    func testNextClassUsesUpcomingOccurrenceAndItsLocalStartDay() throws {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "B2000000-0000-4000-8000-000000000002")!
        )
        let routeID = "entry-fedcba9876543210"
        let snapshot = makeSnapshot(
            timeZoneIdentifier: "America/New_York",
            entries: [
                entry(
                    id: "occurrence:1787891400000:0",
                    routeID: routeID,
                    start: "2026-08-28T03:50:00Z",
                    end: "2026-08-28T04:50:00Z"
                )
            ]
        )

        let route = try decodedRoute(subject.nextClassURL(
            content: .ready(profile: profile, profileName: "Night School", snapshot: snapshot),
            date: instant("2026-08-28T03:30:00Z")
        ))

        XCTAssertEqual(
            route,
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: profile,
                entryID: routeID
            )
        )
    }

    func testNextClassAfterLastClassFallsBackToExactProfileAndCurrentLocalDay() throws {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "C3000000-0000-4000-8000-000000000003")!
        )
        let snapshot = makeSnapshot(
            timeZoneIdentifier: "Asia/Singapore",
            entries: [
                entry(
                    id: "occurrence:1787884860000:0",
                    routeID: "entry-aaaaaaaaaaaaaaaa",
                    start: "2026-08-27T16:01:00Z",
                    end: "2026-08-27T16:20:00Z"
                )
            ]
        )

        let route = try decodedRoute(subject.nextClassURL(
            content: .ready(profile: profile, profileName: "School", snapshot: snapshot),
            date: instant("2026-08-27T16:30:00Z")
        ))

        XCTAssertEqual(
            route,
            .calendar(
                day: .init(year: 2026, month: 8, day: 28),
                profile: profile,
                entryID: nil
            )
        )
    }

    func testWeekUsesExactProfileAndTimelineLocalDayWithoutEntryID() throws {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "D4000000-0000-4000-8000-000000000004")!
        )
        let snapshot = makeSnapshot(
            timeZoneIdentifier: "America/New_York",
            entries: [
                entry(
                    id: "occurrence:1787891400000:0",
                    routeID: "entry-bbbbbbbbbbbbbbbb",
                    start: "2026-08-28T03:50:00Z",
                    end: "2026-08-28T04:50:00Z"
                )
            ]
        )

        let route = try decodedRoute(subject.weekURL(
            content: .ready(profile: profile, profileName: "School", snapshot: snapshot),
            date: instant("2026-08-28T03:30:00Z")
        ))

        XCTAssertEqual(
            route,
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: profile,
                entryID: nil
            )
        )
    }

    func testTwoReadyWidgetConfigurationsProduceDifferentProfileURLs() throws {
        let school = ProfileIdentity.saved(
            UUID(uuidString: "E5000000-0000-4000-8000-000000000005")!
        )
        let personal = ProfileIdentity.saved(
            UUID(uuidString: "F6000000-0000-4000-8000-000000000006")!
        )
        let date = instant("2026-08-27T02:30:00Z")
        let snapshot = makeSnapshot(
            timeZoneIdentifier: "Asia/Singapore",
            entries: [
                entry(
                    id: "occurrence:1787797800000:0",
                    routeID: "entry-abcdef0123456789",
                    start: "2026-08-27T02:10:00Z",
                    end: "2026-08-27T03:10:00Z"
                )
            ]
        )

        let schoolURL = try XCTUnwrap(subject.nextClassURL(
            content: .ready(profile: school, profileName: "School", snapshot: snapshot),
            date: date
        ))
        let personalURL = try XCTUnwrap(subject.nextClassURL(
            content: .ready(profile: personal, profileName: "Personal", snapshot: snapshot),
            date: date
        ))

        XCTAssertNotEqual(schoolURL, personalURL)
        XCTAssertEqual(
            try codec.route(from: schoolURL),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: school,
                entryID: "entry-abcdef0123456789"
            )
        )
        XCTAssertEqual(
            try codec.route(from: personalURL),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: personal,
                entryID: "entry-abcdef0123456789"
            )
        )
    }

    func testChooseDeletedPermissionEmptyAndNoClassesStatesHaveNoURL() {
        let nonReadyContents: [TimetableWidgetContent] = [
            .chooseProfile,
            .profileDeleted,
            .calendarAccessRequired(profileName: "School"),
            .emptyProfile(profileName: "School"),
            .noClasses(profileName: "School")
        ]
        let date = instant("2026-08-27T02:30:00Z")

        for content in nonReadyContents {
            XCTAssertNil(subject.nextClassURL(content: content, date: date))
            XCTAssertNil(subject.weekURL(content: content, date: date))
        }
    }

    func testInvalidTimeZoneAndNoncanonicalRouteIDHaveNoURL() {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "A7000000-0000-4000-8000-000000000007")!
        )
        let date = instant("2026-08-27T02:30:00Z")
        let validEntry = entry(
            id: "occurrence:1787797800000:0",
            routeID: "entry-0123456789abcdef",
            start: "2026-08-27T02:10:00Z",
            end: "2026-08-27T03:10:00Z"
        )
        let invalidTimeZoneContent = TimetableWidgetContent.ready(
            profile: profile,
            profileName: "School",
            snapshot: makeSnapshot(
                timeZoneIdentifier: "Mars/Olympus_Mons",
                entries: [validEntry]
            )
        )
        let malformedRouteContent = TimetableWidgetContent.ready(
            profile: profile,
            profileName: "School",
            snapshot: makeSnapshot(
                timeZoneIdentifier: "Asia/Singapore",
                entries: [
                    entry(
                        id: "occurrence:1787797800000:0",
                        routeID: "occurrence:1787797800000:0",
                        start: "2026-08-27T02:10:00Z",
                        end: "2026-08-27T03:10:00Z"
                    )
                ]
            )
        )

        XCTAssertNil(subject.nextClassURL(content: invalidTimeZoneContent, date: date))
        XCTAssertNil(subject.weekURL(content: invalidTimeZoneContent, date: date))
        XCTAssertNil(subject.nextClassURL(content: malformedRouteContent, date: date))
    }

    func testReadyContentWithNonreadySnapshotAvailabilityFailsClosed() {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "A8000000-0000-4000-8000-000000000008")!
        )
        let date = instant("2026-08-27T02:30:00Z")
        let validEntry = entry(
            id: "occurrence:1787797800000:0",
            routeID: "entry-0123456789abcdef",
            start: "2026-08-27T02:10:00Z",
            end: "2026-08-27T03:10:00Z"
        )

        for availability in [
            TimetableAvailability.calendarAccessRequired,
            .emptyProfile,
            .noClasses
        ] {
            let content = TimetableWidgetContent.ready(
                profile: profile,
                profileName: "School",
                snapshot: makeSnapshot(availability: availability, entries: [validEntry])
            )

            XCTAssertNil(subject.nextClassURL(content: content, date: date))
            XCTAssertNil(subject.weekURL(content: content, date: date))
        }
    }

    private func decodedRoute(
        _ url: URL?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AppRoute {
        try codec.route(from: XCTUnwrap(url, file: file, line: line))
    }

    private func makeSnapshot(
        availability: TimetableAvailability = .ready,
        timeZoneIdentifier: String = "Asia/Singapore",
        entries: [TimetableEntry]
    ) -> TimetableSnapshotV1 {
        TimetableSnapshotV1(
            version: TimetableSnapshotV1.currentVersion,
            availability: availability,
            generatedAt: instant("2026-08-25T00:00:00Z"),
            weekStart: instant("2026-08-23T16:00:00Z"),
            timeZoneIdentifier: timeZoneIdentifier,
            entries: entries
        )
    }

    private func entry(
        id: String,
        routeID: String,
        start: String,
        end: String
    ) -> TimetableEntry {
        TimetableEntry(
            id: id,
            title: "Algorithms",
            shortTitle: "ALG",
            start: instant(start),
            end: instant(end),
            location: "LT19",
            routeID: routeID
        )
    }

    private func instant(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            XCTFail("Invalid test instant \(value)", file: file, line: line)
            return .distantPast
        }
        return date
    }
}
