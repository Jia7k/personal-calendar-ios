import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class TimetableSurfaceRouteBuilderTests: XCTestCase {
    private let builder = TimetableSurfaceRouteBuilder()
    private let codec = AppRouteCodec()

    func testExactSavedProfileDayAndOpaqueEntryRoundTrip() throws {
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
        )

        let url = try builder.url(
            profile: profile,
            date: instant("2026-08-27T15:45:00Z"),
            timeZoneIdentifier: "Asia/Singapore",
            entryRouteID: " \nentry-0123456789abcdef\t"
        )

        XCTAssertEqual(
            try codec.route(from: url),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: profile,
                entryID: "entry-0123456789abcdef"
            )
        )
    }

    func testEverythingProfileAndBlankEntryRoundTripAsDayNavigation() throws {
        let url = try builder.url(
            profile: .everything,
            date: instant("2026-08-27T15:45:00Z"),
            timeZoneIdentifier: "Asia/Singapore",
            entryRouteID: " \n\t "
        )

        XCTAssertEqual(
            try codec.route(from: url),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: .everything,
                entryID: nil
            )
        )
    }

    func testSuppliedTimeZoneControlsDayNearMidnight() throws {
        let date = instant("2026-08-27T16:30:00Z")

        let singaporeRoute = try codec.route(from: builder.url(
            profile: .everything,
            date: date,
            timeZoneIdentifier: "Asia/Singapore",
            entryRouteID: nil
        ))
        let newYorkRoute = try codec.route(from: builder.url(
            profile: .everything,
            date: date,
            timeZoneIdentifier: "America/New_York",
            entryRouteID: nil
        ))

        XCTAssertEqual(
            singaporeRoute,
            .calendar(
                day: .init(year: 2026, month: 8, day: 28),
                profile: .everything,
                entryID: nil
            )
        )
        XCTAssertEqual(
            newYorkRoute,
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: .everything,
                entryID: nil
            )
        )
    }

    func testGregorianDayRemainsCorrectAcrossDSTTransition() throws {
        let beforeFallback = try codec.route(from: builder.url(
            profile: .everything,
            date: instant("2026-11-01T05:30:00Z"),
            timeZoneIdentifier: "America/New_York",
            entryRouteID: nil
        ))
        let afterFallback = try codec.route(from: builder.url(
            profile: .everything,
            date: instant("2026-11-01T06:30:00Z"),
            timeZoneIdentifier: "America/New_York",
            entryRouteID: nil
        ))
        let expected = AppRoute.calendar(
            day: .init(year: 2026, month: 11, day: 1),
            profile: .everything,
            entryID: nil
        )

        XCTAssertEqual(beforeFallback, expected)
        XCTAssertEqual(afterFallback, expected)
    }

    func testInvalidTimeZoneFailsClosed() {
        XCTAssertThrowsError(
            try builder.url(
                profile: .everything,
                date: instant("2026-08-27T15:45:00Z"),
                timeZoneIdentifier: "Mars/Olympus_Mons",
                entryRouteID: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? TimetableSurfaceRouteBuilderError,
                .invalidTimeZoneIdentifier("Mars/Olympus_Mons")
            )
        }
    }

    func testURLDoesNotContainPrivateDisplayDataAndHasOnlyAllowedRouteFields() throws {
        let forbiddenFixtureData = [
            "PRIVATE-TITLE-CS2040S",
            "PRIVATE-LOCATION-LT19",
            "PRIVATE-DISPLAY-ID-123",
            "PRIVATE-NOTES-BRING-LAPTOP",
            "PRIVATE-MUTATION-ID-456",
            "PRIVATE-CALDAV-PROVIDER-PAYLOAD"
        ]
        let profile = ProfileIdentity.saved(
            UUID(uuidString: "B2000000-0000-4000-8000-000000000002")!
        )

        let url = try builder.url(
            profile: profile,
            date: instant("2026-08-27T15:45:00Z"),
            timeZoneIdentifier: "Asia/Singapore",
            entryRouteID: "entry-fedcba9876543210"
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.scheme, "personalcalendar")
        XCTAssertEqual(components.host, "v1")
        XCTAssertEqual(components.path, "/calendar")
        XCTAssertEqual(
            Set((components.queryItems ?? []).map(\.name)),
            Set(["day", "profile", "entry"])
        )
        XCTAssertEqual(components.queryItems?.count, 3)
        XCTAssertNil(components.user)
        XCTAssertNil(components.password)
        XCTAssertNil(components.port)
        XCTAssertNil(components.fragment)
        for forbiddenValue in forbiddenFixtureData {
            XCTAssertFalse(url.absoluteString.contains(forbiddenValue))
        }
    }

    func testTwoProfilesProduceDifferentRoutesForTheSameOccurrence() throws {
        let firstProfile = ProfileIdentity.saved(
            UUID(uuidString: "C3000000-0000-4000-8000-000000000003")!
        )
        let secondProfile = ProfileIdentity.saved(
            UUID(uuidString: "D4000000-0000-4000-8000-000000000004")!
        )
        let date = instant("2026-08-27T15:45:00Z")
        let entryRouteID = "entry-abcdef0123456789"

        let firstURL = try builder.url(
            profile: firstProfile,
            date: date,
            timeZoneIdentifier: "Asia/Singapore",
            entryRouteID: entryRouteID
        )
        let secondURL = try builder.url(
            profile: secondProfile,
            date: date,
            timeZoneIdentifier: "Asia/Singapore",
            entryRouteID: entryRouteID
        )

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(
            try codec.route(from: firstURL),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: firstProfile,
                entryID: entryRouteID
            )
        )
        XCTAssertEqual(
            try codec.route(from: secondURL),
            .calendar(
                day: .init(year: 2026, month: 8, day: 27),
                profile: secondProfile,
                entryID: entryRouteID
            )
        )
    }

    func testNoncanonicalUppercaseNonhexWrongPrefixAndLengthEntryIDsFailClosed() {
        let invalidValues = [
            "entry-0123456789abcdeF",
            "entry-0123456789abcdeg",
            "route-0123456789abcdef",
            "entry-0123456789abcde",
            "entry-0123456789abcdef0"
        ]

        assertInvalidEntryRouteIDs(invalidValues)
    }

    func testSyntheticZeroWidthPrivateLookingAndProviderLikeEntryIDsFailClosed() {
        let invalidValues = [
            "occurrence:1788138000000:0",
            "entry-01234567\u{200B}89abcdef",
            "EKEvent:PRIVATE-DISPLAY-ID-123",
            "caldav://provider.example/private-event"
        ]

        assertInvalidEntryRouteIDs(invalidValues)
    }

    private func assertInvalidEntryRouteIDs(
        _ values: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for value in values {
            XCTAssertThrowsError(
                try builder.url(
                    profile: .everything,
                    date: instant("2026-08-27T15:45:00Z"),
                    timeZoneIdentifier: "Asia/Singapore",
                    entryRouteID: value
                ),
                "Expected rejection for \(String(reflecting: value))",
                file: file,
                line: line
            ) { error in
                XCTAssertEqual(
                    error as? TimetableSurfaceRouteBuilderError,
                    .invalidEntryRouteID(value),
                    file: file,
                    line: line
                )
            }
        }
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
