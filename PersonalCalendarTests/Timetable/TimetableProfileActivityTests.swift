import XCTest
@testable import PersonalCalendar

@MainActor
final class TimetableProfileActivityTests: XCTestCase {
    private static let schoolID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let personalID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let deletedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    func testReconcileUpdatesEachActivityFromItsOwnProfileAndEndsDeletedProfile() async {
        let school = profile(
            id: .saved(Self.schoolID),
            name: "School",
            entries: [Self.math]
        )
        let personal = profile(
            id: .saved(Self.personalID),
            name: "Personal",
            entries: [Self.dentist]
        )
        let driver = RecordingProfileActivityDriver(activities: [
            descriptor(id: "school-live", profile: school),
            descriptor(id: "personal-live", profile: personal),
            TimetableActivityDescriptor(
                id: "deleted-live",
                attributes: attributes(
                    identity: .saved(Self.deletedID),
                    name: "Deleted"
                )
            )
        ])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: Self.calendar)

        await subject.reconcile(catalog: catalog(profiles: [school, personal]), now: Self.now)

        XCTAssertEqual(driver.updates.map(\.id), ["school-live", "personal-live"])
        XCTAssertEqual(
            driver.updates.first(where: { $0.id == "school-live" })?.state.snapshot.entries,
            [Self.math]
        )
        XCTAssertEqual(
            driver.updates.first(where: { $0.id == "personal-live" })?.state.snapshot.entries,
            [Self.dentist]
        )
        XCTAssertEqual(driver.ends.map(\.id), ["deleted-live"])
        XCTAssertTrue(driver.requests.isEmpty)
    }

    func testStartRequestsActivityForExplicitProfile() async {
        let school = profile(
            id: .saved(Self.schoolID),
            name: "School",
            entries: [Self.math]
        )
        let driver = RecordingProfileActivityDriver()
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: Self.calendar)

        await subject.start(profile: school, now: Self.now)

        XCTAssertEqual(driver.requests.count, 1)
        XCTAssertEqual(driver.requests.first?.attributes.profileIdentity, .saved(Self.schoolID))
        XCTAssertEqual(driver.requests.first?.attributes.profileName, "School")
        XCTAssertEqual(driver.requests.first?.attributes.weekStart, Self.weekStart)
        XCTAssertEqual(driver.requests.first?.attributes.timeZoneIdentifier, "Asia/Singapore")
        XCTAssertEqual(driver.requests.first?.state.snapshot, school.snapshot)
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertTrue(driver.ends.isEmpty)
    }

    func testStartingDifferentProfileEndsOldActivityBeforeRequestingReplacement() async {
        let personal = profile(
            id: .saved(Self.personalID),
            name: "Personal",
            entries: [Self.dentist]
        )
        let school = profile(
            id: .saved(Self.schoolID),
            name: "School",
            entries: [Self.math]
        )
        let driver = RecordingProfileActivityDriver(activities: [
            descriptor(id: "personal-live", profile: personal)
        ])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: Self.calendar)

        await subject.start(profile: school, now: Self.now)

        XCTAssertEqual(driver.ends.map(\.id), ["personal-live"])
        XCTAssertEqual(driver.ends.map(\.immediately), [true])
        XCTAssertEqual(driver.requests.map(\.attributes.profileIdentity), [.saved(Self.schoolID)])
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertEqual(
            driver.operations,
            ["end:personal-live", "request:\(ProfileIdentity.saved(Self.schoolID).storageKey)"]
        )
    }

    func testPermissionTombstoneEndsAffectedActivityWithoutUpdatingOrReplacingIt() async {
        let school = profile(
            id: .saved(Self.schoolID),
            name: "School",
            entries: [Self.math]
        )
        let tombstone = profile(
            id: .saved(Self.schoolID),
            name: "School",
            availability: .calendarAccessRequired
        )
        let driver = RecordingProfileActivityDriver(activities: [
            descriptor(id: "school-live", profile: school)
        ])
        let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: Self.calendar)

        await subject.reconcile(catalog: catalog(profiles: [tombstone]), now: Self.now)

        XCTAssertEqual(driver.ends.map(\.id), ["school-live"])
        XCTAssertEqual(driver.ends.map(\.immediately), [true])
        XCTAssertTrue(driver.updates.isEmpty)
        XCTAssertTrue(driver.requests.isEmpty)
    }

    private func catalog(profiles: [TimetableWidgetProfile]) -> TimetableWidgetCatalogV1 {
        let everythingAvailability: TimetableAvailability = profiles.allSatisfy {
            $0.snapshot.availability == .calendarAccessRequired
        } ? .calendarAccessRequired : .ready
        let everythingEntries = profiles.flatMap(\.snapshot.entries)
        let everything = profile(
            id: .everything,
            name: "Everything",
            availability: everythingAvailability,
            entries: everythingEntries
        )
        return TimetableWidgetCatalogV1(
            version: TimetableWidgetCatalogV1.currentVersion,
            generatedAt: Self.generatedAt,
            profiles: [everything] + profiles
        )
    }

    private func profile(
        id: ProfileIdentity,
        name: String,
        availability: TimetableAvailability = .ready,
        entries: [TimetableEntry] = []
    ) -> TimetableWidgetProfile {
        TimetableWidgetProfile(
            id: id,
            name: name,
            colorHex: "#4F6F64",
            symbolName: id == .everything ? "rectangle.3.group.fill" : "graduationcap.fill",
            snapshot: TimetableSnapshotV1(
                version: TimetableSnapshotV1.currentVersion,
                availability: availability,
                generatedAt: Self.generatedAt,
                weekStart: Self.weekStart,
                timeZoneIdentifier: "Asia/Singapore",
                entries: entries
            )
        )
    }

    private func descriptor(
        id: String,
        profile: TimetableWidgetProfile
    ) -> TimetableActivityDescriptor {
        TimetableActivityDescriptor(
            id: id,
            attributes: attributes(identity: profile.id, name: profile.name)
        )
    }

    private func attributes(
        identity: ProfileIdentity,
        name: String
    ) -> TimetableActivityAttributes {
        TimetableActivityAttributes(
            profileIdentity: identity,
            profileName: name,
            weekStart: Self.weekStart,
            timeZoneIdentifier: "Asia/Singapore"
        )
    }

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return value
    }

    private static func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 31,
            hour: hour,
            minute: minute
        ))!
    }

    private static let generatedAt = date(hour: 8)
    private static let weekStart = date(hour: 0)
    private static let now = date(hour: 9, minute: 30)

    private static let math = TimetableEntry(
        id: "occurrence:1788138000000:0",
        title: "INF 2001 Lecture",
        shortTitle: "I01",
        start: date(hour: 9),
        end: date(hour: 11),
        location: "Online"
    )

    private static let dentist = TimetableEntry(
        id: "occurrence:1788156000000:0",
        title: "Dentist",
        shortTitle: "DENT",
        start: date(hour: 14),
        end: date(hour: 15),
        location: "Clinic"
    )
}

@MainActor
private final class RecordingProfileActivityDriver: TimetableActivityDriving {
    struct RequestRecord {
        let attributes: TimetableActivityAttributes
        let state: TimetableActivityAttributes.ContentState
        let staleDate: Date?
    }

    struct UpdateRecord {
        let id: String
        let state: TimetableActivityAttributes.ContentState
        let staleDate: Date?
    }

    struct EndRecord {
        let id: String
        let immediately: Bool
    }

    var activitiesEnabled = true
    private var activities: [TimetableActivityDescriptor]
    private(set) var requests: [RequestRecord] = []
    private(set) var updates: [UpdateRecord] = []
    private(set) var ends: [EndRecord] = []
    private(set) var operations: [String] = []

    init(activities: [TimetableActivityDescriptor] = []) {
        self.activities = activities
    }

    func activityDescriptors() -> [TimetableActivityDescriptor] {
        activities
    }

    func request(
        attributes: TimetableActivityAttributes,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) throws -> String {
        let id = "requested-\(requests.count + 1)"
        requests.append(.init(attributes: attributes, state: state, staleDate: staleDate))
        activities.append(.init(id: id, attributes: attributes))
        operations.append("request:\(attributes.profileIdentity.storageKey)")
        return id
    }

    func update(
        id: String,
        state: TimetableActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        updates.append(.init(id: id, state: state, staleDate: staleDate))
        operations.append("update:\(id)")
    }

    func end(id: String, immediately: Bool) async {
        ends.append(.init(id: id, immediately: immediately))
        activities.removeAll { $0.id == id }
        operations.append("end:\(id)")
    }
}
