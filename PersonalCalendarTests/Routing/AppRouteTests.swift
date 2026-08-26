import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class AppRouteTests: XCTestCase {
    private let codec = AppRouteCodec()

    func testTodayRoundTripsThroughVersionedURL() throws {
        XCTAssertEqual(try codec.route(from: codec.url(for: .today)), .today)
    }

    func testCalendarDayProfileAndOpaqueEntryRoundTripThroughVersionedURL() throws {
        let route = AppRoute.calendar(
            day: .init(year: 2026, month: 8, day: 27),
            profile: .saved(UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!),
            entryID: "entry-opaque-4df8"
        )

        XCTAssertEqual(try codec.route(from: codec.url(for: route)), route)
    }

    func testTaskRoundTripsThroughVersionedURL() throws {
        let route = AppRoute.task(
            id: "reminder-opaque-id",
            profile: .everything
        )

        XCTAssertEqual(try codec.route(from: codec.url(for: route)), route)
    }

    func testRoutineRoundTripsThroughVersionedURL() throws {
        let route = AppRoute.routine(
            id: UUID(uuidString: "B2000000-0000-4000-8000-000000000002")!,
            profile: .saved(UUID(uuidString: "C3000000-0000-4000-8000-000000000003")!)
        )

        XCTAssertEqual(try codec.route(from: codec.url(for: route)), route)
    }

    func testQuickEntryUnicodeTextRoundTripsThroughVersionedURL() throws {
        let route = AppRoute.quickEntry(
            text: "Réviser 研究ノート tomorrow at 9:30 ✨",
            profile: .saved(UUID(uuidString: "D4000000-0000-4000-8000-000000000004")!)
        )

        XCTAssertEqual(try codec.route(from: codec.url(for: route)), route)
    }

    func testUnknownSchemeIsRejected() {
        XCTAssertThrowsError(try codec.route(from: URL(string: "othercalendar://v1/today")!))
    }

    func testUnknownVersionIsRejected() {
        XCTAssertThrowsError(try codec.route(from: URL(string: "personalcalendar://v2/today")!))
    }

    func testUnknownRouteKindIsRejected() {
        XCTAssertThrowsError(try codec.route(from: URL(string: "personalcalendar://v1/not-a-route")!))
    }

    func testMalformedProfileUUIDIsRejected() {
        XCTAssertThrowsError(
            try codec.route(from: URL(string: "personalcalendar://v1/task?id=task-1&profile=saved:not-a-uuid")!)
        )
    }

    func testMalformedCalendarDayIsRejected() {
        XCTAssertThrowsError(
            try codec.route(from: URL(string: "personalcalendar://v1/calendar?day=2026-02-30")!)
        )
    }

    func testRequiredTaskAndRoutineIdentifiersAreRejectedWhenAbsent() {
        XCTAssertThrowsError(try codec.route(from: URL(string: "personalcalendar://v1/task")!))
        XCTAssertThrowsError(try codec.route(from: URL(string: "personalcalendar://v1/routine")!))
    }

    func testEntryIdentityIsStableOpaqueAndSensitiveToBothInputs() {
        let firstStart = Date(timeIntervalSince1970: 1_788_000_000)
        let same = AppRouteEntryIdentity.make(displayID: "event-display-id", occurrenceStart: firstStart)
        let differentDisplayID = AppRouteEntryIdentity.make(displayID: "other-display-id", occurrenceStart: firstStart)
        let differentOccurrence = AppRouteEntryIdentity.make(
            displayID: "event-display-id",
            occurrenceStart: firstStart.addingTimeInterval(60)
        )

        XCTAssertEqual(same, AppRouteEntryIdentity.make(displayID: "event-display-id", occurrenceStart: firstStart))
        XCTAssertNotEqual(same, differentDisplayID)
        XCTAssertNotEqual(same, differentOccurrence)
        XCTAssertFalse(same.contains("event-display-id"))
    }

    func testRepeatedEqualRoutesReceiveDistinctEnvelopes() throws {
        let controller = AppRouteController()
        controller.submit(.today)
        let first = try XCTUnwrap(controller.pending)

        controller.submit(.today)
        let second = try XCTUnwrap(controller.pending)

        XCTAssertEqual(first.route, second.route)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testControllerConsumesOnlyMatchingEnvelopeOnce() throws {
        let controller = AppRouteController()
        controller.submit(.today)
        let envelope = try XCTUnwrap(controller.pending)

        controller.consume(id: UUID())
        XCTAssertEqual(controller.pending, envelope)

        controller.consume(id: envelope.id)
        XCTAssertNil(controller.pending)

        controller.consume(id: envelope.id)
        XCTAssertNil(controller.pending)
    }

    func testRoutePresentationStateRequiresEveryHostAndRootToBeIdle() {
        XCTAssertTrue(AppRoutePresentationState().isIdle)

        XCTAssertFalse(AppRoutePresentationState(root: true).isIdle)
        XCTAssertFalse(AppRoutePresentationState(calendar: true).isIdle)
        XCTAssertFalse(AppRoutePresentationState(today: true).isIdle)
        XCTAssertFalse(AppRoutePresentationState(tasks: true).isIdle)
        XCTAssertFalse(AppRoutePresentationState(routines: true).isIdle)
    }
}
