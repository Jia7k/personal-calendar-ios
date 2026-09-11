import XCTest
@testable import PersonalCalendar

final class EventPreviewActionContentTests: XCTestCase {
    func testPhysicalLocationSupportsDirectionsAndCopy() {
        let subject = EventPreviewActionContent.resolve(
            location: "  SIT Building, 1 Punggol Coast Road  ",
            eventURL: nil,
            notes: nil
        )

        XCTAssertEqual(subject.location, "SIT Building, 1 Punggol Coast Road")
        XCTAssertEqual(subject.directionsLocation, "SIT Building, 1 Punggol Coast Road")
        XCTAssertNil(subject.meetingURL)
    }

    func testOnlineOnlyPlaceholdersSupportCopyWithoutMisleadingDirections() {
        for location in [
            "Online",
            " virtual ",
            "Zoom",
            "Microsoft Teams",
            "Microsoft Teams Meeting",
            "Google Meet",
            "Webex",
            "Remote"
        ] {
            let subject = EventPreviewActionContent.resolve(
                location: location,
                eventURL: nil,
                notes: nil
            )

            XCTAssertEqual(subject.location, location.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertNil(subject.directionsLocation, "Expected no directions for \(location)")
        }
    }

    func testOnlineJoinWrapperWithMeetingLinkIsNotUsedAsDirectionsQuery() {
        let subject = EventPreviewActionContent.resolve(
            location: "Join https://zoom.us/j/222",
            eventURL: nil,
            notes: nil
        )

        XCTAssertEqual(subject.location, "Join https://zoom.us/j/222")
        XCTAssertNil(subject.directionsLocation)
        XCTAssertEqual(subject.meetingURL?.absoluteString, "https://zoom.us/j/222")
    }

    func testUnsafeCustomSchemeLinkOnlyLocationHasNoDirectionsOrMeetingAction() {
        let subject = EventPreviewActionContent.resolve(
            location: "zoommtg://zoom.us/j/123",
            eventURL: nil,
            notes: nil
        )

        XCTAssertEqual(subject.location, "zoommtg://zoom.us/j/123")
        XCTAssertNil(subject.directionsLocation)
        XCTAssertNil(subject.meetingURL)
    }

    func testMixedPhysicalAndMeetingLocationUsesOnlyPhysicalTextForDirections() {
        let subject = EventPreviewActionContent.resolve(
            location: "SIT Building, 1 Punggol Coast Road; https://zoom.us/j/222",
            eventURL: nil,
            notes: nil
        )

        XCTAssertEqual(
            subject.location,
            "SIT Building, 1 Punggol Coast Road; https://zoom.us/j/222"
        )
        XCTAssertEqual(subject.directionsLocation, "SIT Building, 1 Punggol Coast Road")
        XCTAssertEqual(subject.meetingURL?.absoluteString, "https://zoom.us/j/222")
    }

    func testBlankLocationProvidesNoLocationActions() {
        let subject = EventPreviewActionContent.resolve(
            location: " \n\t ",
            eventURL: nil,
            notes: nil
        )

        XCTAssertNil(subject.location)
        XCTAssertNil(subject.directionsLocation)
    }

    func testExplicitRecognizedMeetingURLWinsDeterministicallyOverLocationAndNotes() {
        let subject = EventPreviewActionContent.resolve(
            location: "Join https://zoom.us/j/222",
            eventURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            notes: "Backup https://teams.microsoft.com/l/meetup-join/333"
        )

        XCTAssertEqual(subject.meetingURL?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(subject.meetingDestination, "meet.google.com")
    }

    func testRecognizedMeetingURLIsExtractedFromLocationBeforeNotes() {
        let subject = EventPreviewActionContent.resolve(
            location: "Online: https://zoom.us/j/222.",
            eventURL: URL(string: "https://example.com/not-a-meeting"),
            notes: "Backup https://teams.microsoft.com/l/meetup-join/333"
        )

        XCTAssertEqual(subject.meetingURL?.absoluteString, "https://zoom.us/j/222")
        XCTAssertEqual(subject.meetingDestination, "zoom.us")
    }

    func testFirstRecognizedURLInNotesWinsWhenEarlierURLsAreUnrecognized() {
        let subject = EventPreviewActionContent.resolve(
            location: nil,
            eventURL: nil,
            notes: "Docs https://example.com/x then https://teams.microsoft.com/l/meetup-join/333 and https://zoom.us/j/444"
        )

        XCTAssertEqual(
            subject.meetingURL?.absoluteString,
            "https://teams.microsoft.com/l/meetup-join/333"
        )
    }

    func testUnsafeMalformedAndLookalikeURLsAreRejected() {
        let values = [
            "zoommtg://zoom.us/j/123",
            "javascript:https://zoom.us/j/123",
            "https://zoom.us.evil.example/j/123",
            "https://example.com/zoom.us/j/123",
            "https://",
            "not a URL"
        ]

        for value in values {
            let subject = EventPreviewActionContent.resolve(
                location: nil,
                eventURL: URL(string: value),
                notes: value
            )
            XCTAssertNil(subject.meetingURL, "Expected unsafe value to be rejected: \(value)")
        }
    }

    func testHTTPAndHTTPSAreTheOnlyAllowedSchemesForRecognizedHosts() {
        XCTAssertEqual(
            EventPreviewActionContent.resolve(
                location: nil,
                eventURL: URL(string: "http://meet.google.com/abc-defg-hij"),
                notes: nil
            ).meetingURL?.scheme,
            "http"
        )
        XCTAssertNil(
            EventPreviewActionContent.resolve(
                location: nil,
                eventURL: URL(string: "ftp://meet.google.com/abc-defg-hij"),
                notes: nil
            ).meetingURL
        )
    }
}
