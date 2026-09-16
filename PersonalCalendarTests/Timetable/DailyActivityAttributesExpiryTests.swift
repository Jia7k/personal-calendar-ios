import Foundation
import XCTest
@testable import PersonalCalendar

/// Source-only tests awaiting the approved physical iPhone 16 Pro run.
final class DailyActivityAttributesExpiryTests: XCTestCase {
    func testDailyInitializerDefaultsStartToSnapshotGenerationAndExpiresEightHoursLater() {
        let snapshot = snapshot(generatedAt: date(hour: 10))
        let attributes = TimetableActivityAttributes(snapshot: snapshot)

        XCTAssertEqual(attributes.activityStartedAt, date(hour: 10))
        XCTAssertEqual(attributes.activityEndsAt, date(hour: 18))
    }

    func testExplicitOriginalStartKeepsStaticAttributesAndExpiryAcrossRefreshes() {
        let startedAt = date(hour: 8)
        let original = TimetableActivityAttributes(snapshot: snapshot(generatedAt: startedAt), startedAt: startedAt)
        let refreshed = TimetableActivityAttributes(snapshot: snapshot(generatedAt: date(hour: 13)),
            startedAt: original.activityStartedAt)

        XCTAssertEqual(refreshed, original)
        XCTAssertEqual(refreshed.activityStartedAt, startedAt)
        XCTAssertEqual(refreshed.activityEndsAt, date(hour: 16))
        XCTAssertNotEqual(refreshed.activityEndsAt, date(hour: 21))
    }

    func testExpiryIsAbsoluteEightHourBoundaryAndDoesNotClampToRepresentedDay() throws {
        let attributes = TimetableActivityAttributes(snapshot: snapshot(generatedAt: date(hour: 20)))
        let expiry = try XCTUnwrap(attributes.activityEndsAt)

        XCTAssertEqual(expiry, date(hour: 28))
        XCTAssertEqual(expiry.timeIntervalSince(try XCTUnwrap(attributes.activityStartedAt)), 28_800)
        XCTAssertGreaterThan(expiry, try XCTUnwrap(attributes.dayEnd))
    }

    func testStartedAtRoundTripsUsingCompactOptionalCodingKey() throws {
        let attributes = TimetableActivityAttributes(snapshot: snapshot(generatedAt: date(hour: 11)),
            startedAt: date(hour: 9))
        let data = try JSONEncoder().encode(attributes)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["a"] as? Double, date(hour: 9).timeIntervalSinceReferenceDate)
        XCTAssertNil(object["activityStartedAt"])
        XCTAssertEqual(try JSONDecoder().decode(TimetableActivityAttributes.self, from: data), attributes)
    }

    func testExistingVersionThreeAttributesWithoutStartDecodeAsUnknownExpiry() throws {
        let attributes = TimetableActivityAttributes(snapshot: snapshot(generatedAt: date(hour: 10)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(attributes)) as? [String: Any])
        object.removeValue(forKey: "a")
        let decoded = try JSONDecoder().decode(TimetableActivityAttributes.self,
            from: JSONSerialization.data(withJSONObject: object))

        XCTAssertFalse(decoded.isLegacy)
        XCTAssertEqual(decoded.dayStart, attributes.dayStart)
        XCTAssertNil(decoded.activityStartedAt)
        XCTAssertNil(decoded.activityEndsAt)
    }

    func testVersionTwoAndCompatibilityInitializerDoNotInventAStartTime() throws {
        let legacyObject: [String: Any] = ["schemaVersion": 2, "profileIdentity": "everything",
            "profileName": "Everything", "weekStart": date(hour: 0).timeIntervalSinceReferenceDate,
            "timeZoneIdentifier": "Asia/Singapore"]
        let legacy = try JSONDecoder().decode(TimetableActivityAttributes.self,
            from: JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertTrue(legacy.isLegacy)
        XCTAssertNil(legacy.activityStartedAt)
        XCTAssertNil(legacy.activityEndsAt)

        let compatibility = TimetableActivityAttributes(profileIdentity: .everything, profileName: "Everything",
            weekStart: date(hour: 0), timeZoneIdentifier: "Asia/Singapore")
        XCTAssertNil(compatibility.activityStartedAt)
        XCTAssertNil(compatibility.activityEndsAt)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(compatibility)) as? [String: Any])
        XCTAssertNil(encoded["a"])
    }

    func testNonfiniteExplicitStartHasNoUsableExpiryBoundary() {
        let attributes = TimetableActivityAttributes(snapshot: snapshot(generatedAt: date(hour: 10)),
            startedAt: Date(timeIntervalSinceReferenceDate: .nan))
        XCTAssertNil(attributes.activityEndsAt)
    }

    private func date(hour: Double) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 19))!
            .addingTimeInterval(hour * 3_600)
    }

    private func snapshot(generatedAt: Date) -> DailyActivitySnapshot {
        .init(profile: .init(id: .everything, name: "Everything", symbolName: "calendar"),
            dayStart: date(hour: 0), dayEnd: date(hour: 24), timeZoneIdentifier: "Asia/Singapore",
            generatedAt: generatedAt, items: [])
    }
}
