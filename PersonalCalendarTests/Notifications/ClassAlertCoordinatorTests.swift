import XCTest
@testable import PersonalCalendar

@MainActor
final class ClassAlertCoordinatorTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 8
        ))!
    }

    func testClassAlertsAreOffByDefault() {
        let profile = makeProfile(calendarIDs: ["school"])
        let event = makeEvent(
            id: "class-1",
            calendarID: "school",
            start: now.addingTimeInterval(3_600)
        )

        let requests = makeSubject().requests(
            profiles: [profile],
            preferences: [:],
            events: [event],
            now: now
        )

        XCTAssertTrue(requests.isEmpty)
    }

    func testEnabledProfileUsesExactMembershipLeadTimeAndCalendarRoute() throws {
        let profile = makeProfile(calendarIDs: ["school"])
        let start = now.addingTimeInterval(2 * 3_600)
        let schoolEvent = makeEvent(
            id: "class-1",
            calendarID: "school",
            start: start
        )
        let unrelated = makeEvent(
            id: "birthday-1",
            calendarID: "birthdays",
            start: start
        )

        let requests = makeSubject().requests(
            profiles: [profile],
            preferences: [profile.id: .init(enabled: true, leadMinutes: 20)],
            events: [unrelated, schoolEvent],
            now: now
        )

        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            request.fireDate,
            calendar.date(byAdding: .minute, value: -20, to: start)
        )
        XCTAssertEqual(request.categoryIdentifier, NotificationCategoryIdentifier.classAlert)
        let routeText = try XCTUnwrap(request.userInfo[NotificationPayloadKey.route])
        let route = try AppRouteCodec().route(from: XCTUnwrap(URL(string: routeText)))
        XCTAssertEqual(
            route,
            .calendar(
                day: .init(year: 2026, month: 8, day: 24),
                profile: .saved(profile.id),
                entryID: AppRouteEntryIdentity.make(
                    displayID: schoolEvent.id,
                    occurrenceStart: schoolEvent.start
                )
            )
        )
    }

    func testAllDayPastInvalidLeadAndOutsideHorizonEventsAreExcluded() {
        let profile = makeProfile(calendarIDs: ["school"])
        let events = [
            makeEvent(id: "all-day", calendarID: "school", start: now.addingTimeInterval(3_600), isAllDay: true),
            makeEvent(id: "already-started", calendarID: "school", start: now.addingTimeInterval(-60)),
            makeEvent(id: "too-late", calendarID: "school", start: now.addingTimeInterval(3 * 86_400))
        ]

        let requests = ClassAlertCoordinator(
            calendar: calendar,
            horizonDays: 2,
            maximumRequests: 12
        ).requests(
            profiles: [profile],
            preferences: [profile.id: .init(enabled: true, leadMinutes: 10)],
            events: events,
            now: now
        )
        let invalidLead = makeSubject().requests(
            profiles: [profile],
            preferences: [profile.id: .init(enabled: true, leadMinutes: 17)],
            events: [makeEvent(id: "valid", calendarID: "school", start: now.addingTimeInterval(3_600))],
            now: now
        )

        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(invalidLead.isEmpty)
    }

    func testRequestsAreDeterministicAndRespectBudget() {
        let profile = makeProfile(calendarIDs: ["school"])
        let events = (0..<5).reversed().map { index in
            makeEvent(
                id: "class-\(index)",
                calendarID: "school",
                start: now.addingTimeInterval(Double(index + 1) * 3_600)
            )
        }

        let requests = ClassAlertCoordinator(
            calendar: calendar,
            horizonDays: 14,
            maximumRequests: 3
        ).requests(
            profiles: [profile],
            preferences: [profile.id: .init(enabled: true, leadMinutes: 10)],
            events: events,
            now: now
        )

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map(\.title), ["Class 0", "Class 1", "Class 2"])
        XCTAssertEqual(requests.map(\.fireDate), requests.map(\.fireDate).sorted())
    }

    func testDeletedProfileOrRevokedCalendarMembershipRemovesItsAlerts() {
        let deletedProfile = makeProfile(calendarIDs: ["school"])
        let retainedProfile = makeProfile(calendarIDs: ["personal"])
        let preferences = [
            deletedProfile.id: ClassAlertPreference(enabled: true, leadMinutes: 10),
            retainedProfile.id: ClassAlertPreference(enabled: true, leadMinutes: 10)
        ]
        let events = [
            makeEvent(id: "class", calendarID: "school", start: now.addingTimeInterval(3_600)),
            makeEvent(id: "dentist", calendarID: "personal", start: now.addingTimeInterval(7_200))
        ]

        let afterDeletion = makeSubject().requests(
            profiles: [retainedProfile],
            preferences: preferences,
            events: events,
            now: now
        )
        let afterMembershipRemoval = makeSubject().requests(
            profiles: [makeProfile(id: retainedProfile.id, calendarIDs: [])],
            preferences: preferences,
            events: events,
            now: now
        )

        XCTAssertEqual(afterDeletion.map(\.title), ["Dentist"])
        XCTAssertTrue(afterMembershipRemoval.isEmpty)
    }

    private func makeSubject() -> ClassAlertCoordinator {
        .init(calendar: calendar, horizonDays: 14, maximumRequests: 12)
    }

    private func makeProfile(
        id: UUID = UUID(),
        calendarIDs: Set<String>
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            id: id,
            name: "School",
            colorHex: "#4868A8",
            symbolName: "graduationcap.fill",
            sortOrder: 0,
            calendarIDs: calendarIDs,
            reminderListIDs: [],
            routineIDs: [],
            defaultCalendarID: calendarIDs.first,
            defaultReminderListID: nil
        )
    }

    private func makeEvent(
        id: String,
        calendarID: String,
        start: Date,
        isAllDay: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: id,
            title: id == "dentist" ? "Dentist" : "Class \(id.split(separator: "-").last ?? "")",
            start: start,
            end: start.addingTimeInterval(3_600),
            isAllDay: isAllDay,
            calendarID: calendarID,
            calendarTitle: calendarID,
            allowsModification: true,
            hasRecurrence: false
        )
    }
}
