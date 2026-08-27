import Foundation
import XCTest
@testable import PersonalCalendar

final class TimetableActivityRouteResolverTests: XCTestCase {
    private let subject = TimetableActivityRouteResolver()
    private let codec = AppRouteCodec()

    func testLegacyCompactEntryWithoutRouteIDDecodesAsNil() throws {
        let state = try decodedState(entryRouteID: nil)

        XCTAssertNil(try XCTUnwrap(state.entries.first).routeID)

        let encoded = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let entries = try XCTUnwrap(object["e"] as? [[String: Any]])
        XCTAssertNil(try XCTUnwrap(entries.first)["r"])
    }

    func testActivityCurrentAndUpcomingEntriesOpenExactProfileOccurrence() throws {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
        )
        let attributes = makeAttributes(profile: profile, timeZoneIdentifier: "Asia/Singapore")
        let cases: [(now: String, routeID: String, start: String, expectedDay: Int)] = [
            (
                now: "2026-08-27T02:30:00Z",
                routeID: "entry-0123456789abcdef",
                start: "2026-08-27T02:10:00Z",
                expectedDay: 27
            ),
            (
                now: "2026-08-27T03:30:00Z",
                routeID: "entry-fedcba9876543210",
                start: "2026-08-27T16:10:00Z",
                expectedDay: 28
            )
        ]

        for value in cases {
            let state = makeState(entries: [
                makeEntry(
                    id: "synthetic-\(value.expectedDay)",
                    routeID: value.routeID,
                    start: value.start,
                    end: value.expectedDay == 27
                        ? "2026-08-27T03:10:00Z"
                        : "2026-08-27T17:10:00Z"
                )
            ])

            XCTAssertEqual(
                try decodedRoute(subject.url(
                    attributes: attributes,
                    state: state,
                    now: instant(value.now)
                )),
                .calendar(
                    day: .init(year: 2026, month: 8, day: value.expectedDay),
                    profile: profile,
                    entryID: value.routeID
                )
            )
        }
    }

    func testActivityWithoutEntryRouteIDFallsBackToExactProfileAndCurrentLocalDay() throws {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "B2000000-0000-4000-8000-000000000002")!
        )
        let attributes = makeAttributes(profile: profile, timeZoneIdentifier: "Asia/Singapore")
        let now = instant("2026-08-27T16:15:00Z")
        let overnightLegacyState = makeState(entries: [
            makeEntry(
                id: "legacy-overnight",
                routeID: nil,
                start: "2026-08-27T15:30:00Z",
                end: "2026-08-27T16:30:00Z"
            )
        ])

        for state in [overnightLegacyState, makeState(entries: [])] {
            XCTAssertEqual(
                try decodedRoute(subject.url(
                    attributes: attributes,
                    state: state,
                    now: now
                )),
                .calendar(
                    day: .init(year: 2026, month: 8, day: 28),
                    profile: profile,
                    entryID: nil
                )
            )
        }
    }

    func testActivityRoutesForDifferentProfilesRemainDistinct() throws {
        let school = ProfileIdentity.saved(
            UUID(uuidString: "C3000000-0000-4000-8000-000000000003")!
        )
        let personal = ProfileIdentity.saved(
            UUID(uuidString: "D4000000-0000-4000-8000-000000000004")!
        )
        let now = instant("2026-08-27T02:30:00Z")
        let state = makeState(entries: [makeEntry(
            id: "synthetic-occurrence",
            routeID: "entry-aaaaaaaaaaaaaaaa",
            start: "2026-08-27T02:10:00Z",
            end: "2026-08-27T03:10:00Z"
        )])

        let schoolURL = try XCTUnwrap(subject.url(
            attributes: makeAttributes(profile: school),
            state: state,
            now: now
        ))
        let personalURL = try XCTUnwrap(subject.url(
            attributes: makeAttributes(profile: personal),
            state: state,
            now: now
        ))

        XCTAssertNotEqual(schoolURL, personalURL)
        XCTAssertEqual(
            try codec.route(from: schoolURL),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: school,
                entryID: "entry-aaaaaaaaaaaaaaaa"
            )
        )
        XCTAssertEqual(
            try codec.route(from: personalURL),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: personal,
                entryID: "entry-aaaaaaaaaaaaaaaa"
            )
        )
    }

    func testActivityURLContainsNoTitleLocationOrSyntheticEntryID() throws {
        let state = makeState(entries: [makeEntry(
            id: "private-provider-display-id",
            title: "Private Algorithms Title",
            location: "Secret Room 42",
            routeID: "entry-bbbbbbbbbbbbbbbb",
            start: "2026-08-27T02:10:00Z",
            end: "2026-08-27T03:10:00Z"
        )])

        let url = try XCTUnwrap(subject.url(
            attributes: makeAttributes(profile: .everything),
            state: state,
            now: instant("2026-08-27T02:30:00Z")
        ))
        let encoded = url.absoluteString.lowercased()

        XCTAssertFalse(encoded.contains("private"))
        XCTAssertFalse(encoded.contains("algorithms"))
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertFalse(encoded.contains("synthetic"))
        XCTAssertEqual(
            try codec.route(from: url),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: .everything,
                entryID: "entry-bbbbbbbbbbbbbbbb"
            )
        )
    }

    func testActivityInvalidTimeZoneAndMalformedNonblankRouteIDHaveNoURL() throws {
        let validState = makeState(entries: [makeEntry(
            routeID: "entry-cccccccccccccccc",
            start: "2026-08-27T02:10:00Z",
            end: "2026-08-27T03:10:00Z"
        )])
        let malformedState = try decodedState(entryRouteID: "private-display-id")
        let now = instant("2026-08-27T02:30:00Z")

        XCTAssertNil(subject.url(
            attributes: makeAttributes(
                profile: .everything,
                timeZoneIdentifier: "Mars/Olympus_Mons"
            ),
            state: validState,
            now: now
        ))
        XCTAssertNil(subject.url(
            attributes: makeAttributes(profile: .everything),
            state: malformedState,
            now: now
        ))
    }

    private func makeAttributes(
        profile: ProfileIdentity,
        timeZoneIdentifier: String = "Asia/Singapore"
    ) -> TimetableActivityAttributes {
        TimetableActivityAttributes(
            profileIdentity: profile,
            profileName: "School",
            weekStart: instant("2026-08-23T16:00:00Z"),
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func makeState(
        entries: [TimetableActivityAttributes.ContentState.Entry]
    ) -> TimetableActivityAttributes.ContentState {
        TimetableActivityAttributes.ContentState(
            generatedAt: instant("2026-08-27T00:00:00Z"),
            entries: entries,
            omittedEntryCount: 0,
            sourceOmittedEntryCount: 0
        )
    }

    private func makeEntry(
        id: String = "synthetic-entry-id",
        title: String = "Algorithms",
        location: String? = "LT19",
        routeID: String?,
        start: String,
        end: String
    ) -> TimetableActivityAttributes.ContentState.Entry {
        TimetableActivityAttributes.ContentState.Entry(
            id: id,
            title: title,
            shortTitle: "ALG",
            start: instant(start),
            end: instant(end),
            location: location,
            routeID: routeID
        )
    }

    private func decodedState(
        entryRouteID: String?
    ) throws -> TimetableActivityAttributes.ContentState {
        var entry: [String: Any] = [
            "i": "legacy-synthetic-id",
            "t": "Legacy Overnight Studio",
            "s": "LEG",
            "b": instant("2026-08-27T15:30:00Z").timeIntervalSinceReferenceDate,
            "e": instant("2026-08-27T16:30:00Z").timeIntervalSinceReferenceDate,
            "l": "Legacy Room"
        ]
        if let entryRouteID {
            entry["r"] = entryRouteID
        }
        let object: [String: Any] = [
            "g": instant("2026-08-27T15:00:00Z").timeIntervalSinceReferenceDate,
            "e": [entry],
            "o": 0,
            "u": 0
        ]
        return try JSONDecoder().decode(
            TimetableActivityAttributes.ContentState.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func decodedRoute(
        _ url: URL?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AppRoute {
        try codec.route(from: XCTUnwrap(url, file: file, line: line))
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
