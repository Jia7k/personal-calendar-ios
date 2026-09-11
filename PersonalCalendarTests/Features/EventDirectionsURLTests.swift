import XCTest
@testable import PersonalCalendar

final class EventDirectionsURLTests: XCTestCase {
    func testPhysicalQueryBuildsAnHTTPSAppleMapsDirectionsURL() throws {
        let url = try XCTUnwrap(
            EventDirectionsURL.make(location: "SIT Building, 1 Punggol Coast Road")
        )
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "maps.apple.com")
        XCTAssertEqual(components.path, "/")
        XCTAssertEqual(
            components.queryItems,
            [URLQueryItem(name: "daddr", value: "SIT Building, 1 Punggol Coast Road")]
        )
    }

    func testBlankLocationDoesNotBuildDirectionsURL() {
        XCTAssertNil(EventDirectionsURL.make(location: " \n "))
    }
}
