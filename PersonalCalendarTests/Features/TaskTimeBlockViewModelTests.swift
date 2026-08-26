import XCTest
@testable import PersonalCalendar

@MainActor
final class TaskTimeBlockViewModelTests: XCTestCase {
    func testLoadFetchesOnlyTheExactResolvedProfileCalendarsAndSeedsWritableCapturedDefault() async {
        let fixture = makeFixture(
            context: profileContext(
                calendarIDs: ["school", "personal", "removed"],
                defaultCalendarID: "school"
            ),
            resolvedCalendarIDs: ["school", "personal"],
            descriptors: [
                descriptor("personal", title: "Personal"),
                descriptor("school", title: "School"),
                descriptor("outside", title: "Outside")
            ]
        )

        await fixture.subject.load()

        XCTAssertEqual(fixture.calendar.fetchCalendarIDs, [["school", "personal"]])
        XCTAssertEqual(fixture.resolver.requestedIdentities, [.saved(profileID)])
        XCTAssertEqual(fixture.subject.destinationCalendarID, "school")
        XCTAssertEqual(fixture.subject.phase, .ready)
    }

    func testEmptyResolvedProfileNeverUsesEmptyIDsAsFetchEverything() async {
        let fixture = makeFixture(
            context: profileContext(calendarIDs: [], defaultCalendarID: nil),
            resolvedCalendarIDs: [],
            descriptors: [descriptor("outside", title: "Outside")]
        )

        await fixture.subject.load()

        XCTAssertTrue(fixture.calendar.fetchCalendarIDs.isEmpty)
        XCTAssertTrue(fixture.calendar.createdDrafts.isEmpty)
        XCTAssertNil(fixture.subject.destinationCalendarID)
    }

    func testEverythingBlocksUntilAnExactSavedProfileIsChosen() async {
        let fixture = makeFixture(
            usesEverything: true,
            resolvedCalendarIDs: ["school"],
            descriptors: [descriptor("school", title: "School")]
        )

        await fixture.subject.load()

        XCTAssertTrue(fixture.subject.requiresProfileSelection)
        XCTAssertTrue(fixture.calendar.fetchCalendarIDs.isEmpty)
        XCTAssertTrue(fixture.resolver.requestedIdentities.isEmpty)

        await fixture.subject.chooseProfile(
            profileContext(calendarIDs: ["school"], defaultCalendarID: "school")
        )

        XCTAssertFalse(fixture.subject.requiresProfileSelection)
        XCTAssertEqual(fixture.resolver.requestedIdentities, [.saved(profileID)])
        XCTAssertEqual(fixture.calendar.fetchCalendarIDs, [["school"]])
        XCTAssertEqual(fixture.subject.destinationCalendarID, "school")
    }

    func testDeletedCapturedProfileFailsClosedWithoutFetchingOrFallingBackToEverything() async {
        let fixture = makeFixture(
            context: profileContext(calendarIDs: ["school"], defaultCalendarID: "school"),
            resolvedCalendarIDs: ["school"],
            descriptors: [descriptor("school", title: "School")]
        )
        fixture.resolver.error = ProfileRepositoryError.profileNotFound

        await fixture.subject.load()

        XCTAssertEqual(fixture.resolver.requestedIdentities, [.saved(profileID)])
        XCTAssertTrue(fixture.calendar.fetchCalendarIDs.isEmpty)
        XCTAssertTrue(fixture.calendar.createdDrafts.isEmpty)
        XCTAssertEqual(fixture.subject.phase, .failed(.profileUnavailable))
    }

    func testDestinationRemovedFromLiveProfileAfterLoadBlocksCreation() async {
        let fixture = makeFixture(
            context: profileContext(calendarIDs: ["school"], defaultCalendarID: "school"),
            resolvedCalendarIDs: ["school"],
            descriptors: [descriptor("school", title: "School")]
        )
        await fixture.subject.load()
        fixture.resolver.scope = scope(calendarIDs: ["personal"], defaultCalendarID: nil)

        await fixture.subject.save()

        XCTAssertEqual(fixture.subject.phase, .failed(.invalidDestination))
        XCTAssertTrue(fixture.calendar.createdDrafts.isEmpty)
        XCTAssertEqual(
            fixture.resolver.requestedIdentities,
            [.saved(profileID), .saved(profileID)]
        )
    }

    func testDestinationThatBecomesReadOnlyAfterLoadBlocksCreation() async {
        let fixture = makeFixture(
            context: profileContext(calendarIDs: ["school"], defaultCalendarID: "school"),
            resolvedCalendarIDs: ["school"],
            descriptors: [descriptor("school", title: "School")]
        )
        await fixture.subject.load()
        fixture.calendar.descriptors = [
            descriptor("school", title: "School", writable: false)
        ]

        await fixture.subject.save()

        XCTAssertEqual(fixture.subject.phase, .failed(.invalidDestination))
        XCTAssertTrue(fixture.calendar.createdDrafts.isEmpty)
    }

    func testFirstOverlappingSaveRequiresExplicitSecondConfirmation() async {
        let collision = event(
            id: "lecture",
            title: "Lecture",
            start: date(2026, 8, 24, 10, 0),
            end: date(2026, 8, 24, 11, 0),
            calendarID: "school"
        )
        let fixture = makeFixture(events: [collision])
        await fixture.subject.load()
        fixture.subject.setInterval(
            start: date(2026, 8, 24, 10, 30),
            end: date(2026, 8, 24, 11, 30)
        )

        XCTAssertEqual(fixture.subject.conflicts, ["Lecture"])

        await fixture.subject.save()

        XCTAssertTrue(fixture.subject.requiresConflictConfirmation)
        XCTAssertEqual(fixture.subject.phase, .awaitingConflictConfirmation)
        XCTAssertTrue(fixture.calendar.createdDrafts.isEmpty)

        await fixture.subject.save(confirmingConflicts: true)

        XCTAssertFalse(fixture.subject.requiresConflictConfirmation)
        XCTAssertEqual(fixture.calendar.createdDrafts.count, 1)
        XCTAssertEqual(fixture.subject.phase, .saved(id: "event-id"))
    }

    func testManualDateChangeRefetchesThatDayBeforeRequiringConflictConfirmation() async {
        let collision = event(
            id: "tutorial",
            title: "Tutorial",
            start: date(2026, 8, 25, 10, 0),
            end: date(2026, 8, 25, 11, 0),
            calendarID: "school"
        )
        let fixture = makeFixture(events: [collision])
        await fixture.subject.load()
        fixture.subject.setInterval(
            start: date(2026, 8, 25, 10, 30),
            end: date(2026, 8, 25, 11, 30)
        )

        await fixture.subject.save()

        XCTAssertEqual(fixture.calendar.fetchCalendarIDs, [["school"], ["school"]])
        XCTAssertEqual(fixture.calendar.fetchIntervals.last?.start, date(2026, 8, 25, 0, 0))
        XCTAssertEqual(fixture.calendar.fetchIntervals.last?.end, date(2026, 8, 26, 0, 0))
        XCTAssertEqual(fixture.subject.conflicts, ["Tutorial"])
        XCTAssertEqual(fixture.subject.phase, .awaitingConflictConfirmation)
        XCTAssertTrue(fixture.calendar.createdDrafts.isEmpty)
    }

    func testConfirmedSaveCreatesOneExactEventAndRetainsReminderByConstruction() async {
        let task = reminder(
            id: "task/id with spaces?secret=1|occurrence",
            title: "Submit assignment"
        )
        let fixture = makeFixture(task: task)
        await fixture.subject.load()
        let start = date(2026, 8, 24, 13, 15)
        let end = date(2026, 8, 24, 14, 15)
        fixture.subject.setInterval(start: start, end: end)
        fixture.subject.selectDestination(calendarID: "school")

        await fixture.subject.save()
        await fixture.subject.save()

        XCTAssertEqual(
            fixture.calendar.createdDrafts,
            [
                EventDraft(
                    title: "Submit assignment",
                    start: start,
                    end: end,
                    isAllDay: false,
                    calendarID: "school",
                    notes: "personalcalendar-task:v1:task%2Fid%20with%20spaces%3Fsecret%3D1%7Coccurrence",
                    alarms: .clear,
                    recurrence: .clear
                )
            ]
        )
        XCTAssertEqual(fixture.subject.phase, .saved(id: "event-id"))
        XCTAssertEqual(task, reminder(
            id: "task/id with spaces?secret=1|occurrence",
            title: "Submit assignment"
        ))
        // The initializer intentionally has no RemindersServicing dependency, so
        // this feature has no construction path for completing/updating the task.
    }

    func testNilProviderIdentifierIsTerminalSuccess() async {
        let fixture = makeFixture(createResult: nil)
        await fixture.subject.load()

        await fixture.subject.save()
        await fixture.subject.save()

        XCTAssertEqual(fixture.calendar.createdDrafts.count, 1)
        XCTAssertEqual(fixture.subject.phase, .saved(id: nil))
    }

    func testProviderFailureKeepsExactFormAndSuggestionsReadyForRetry() async {
        let fixture = makeFixture()
        await fixture.subject.load()
        fixture.subject.setDurationMinutes(90)
        let start = date(2026, 8, 24, 15, 0)
        let end = date(2026, 8, 24, 16, 30)
        fixture.subject.setInterval(start: start, end: end)
        fixture.subject.selectDestination(calendarID: "school")
        let suggestions = fixture.subject.suggestions
        fixture.calendar.createError = TimeBlockProviderError.failed

        await fixture.subject.save()

        XCTAssertEqual(fixture.subject.phase, .failed(.writeFailed))
        XCTAssertEqual(fixture.subject.durationMinutes, 90)
        XCTAssertEqual(fixture.subject.start, start)
        XCTAssertEqual(fixture.subject.end, end)
        XCTAssertEqual(fixture.subject.destinationCalendarID, "school")
        XCTAssertEqual(fixture.subject.suggestions, suggestions)
        XCTAssertEqual(fixture.calendar.createdDrafts.count, 1)
    }

    private let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let localCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return calendar
    }()

    private func makeFixture(
        task: ReminderSnapshot? = nil,
        context: CreationProfileContext? = nil,
        usesEverything: Bool = false,
        resolvedCalendarIDs: Set<String> = ["school"],
        descriptors: [CalendarDescriptor]? = nil,
        events: [CalendarEventSnapshot] = [],
        createResult: String? = "event-id"
    ) -> (
        subject: TaskTimeBlockViewModel,
        calendar: TimeBlockCalendarSpy,
        resolver: TimeBlockScopeResolverSpy
    ) {
        let effectiveContext = usesEverything
            ? nil
            : context ?? profileContext(
                calendarIDs: ["school"],
                defaultCalendarID: "school"
            )
        let calendarService = TimeBlockCalendarSpy(
            descriptors: descriptors ?? [descriptor("school", title: "School")],
            events: events,
            createResult: createResult
        )
        let resolver = TimeBlockScopeResolverSpy(
            scope: scope(
                calendarIDs: resolvedCalendarIDs,
                defaultCalendarID: resolvedCalendarIDs.contains("school") ? "school" : nil
            )
        )
        let now = date(2026, 8, 24, 8, 0)
        let subject = TaskTimeBlockViewModel(
            task: task ?? reminder(),
            creationProfile: effectiveContext,
            calendarService: calendarService,
            resolveScope: { try resolver.resolve($0) },
            planner: TaskTimeBlockPlanner(calendar: localCalendar),
            calendar: localCalendar,
            now: { now }
        )
        return (subject, calendarService, resolver)
    }

    private func profileContext(
        calendarIDs: Set<String>,
        defaultCalendarID: String?
    ) -> CreationProfileContext {
        CreationProfileContext(
            profileID: profileID,
            profileName: "School",
            memberCalendarIDs: calendarIDs,
            memberReminderListIDs: ["school-tasks"],
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: "school-tasks",
            requiresExplicitCalendarDestination: defaultCalendarID == nil,
            requiresExplicitReminderDestination: false
        )
    }

    private func scope(
        calendarIDs: Set<String>,
        defaultCalendarID: String?
    ) -> ProfileScope {
        ProfileScope(
            identity: .saved(profileID),
            calendarIDs: calendarIDs,
            reminderListIDs: ["school-tasks"],
            routineIDs: [],
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: "school-tasks"
        )
    }

    private func reminder(
        id: String = "task-1",
        title: String = "Submit assignment"
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id,
            title: title,
            notes: "Keep this reminder",
            dueDate: date(2026, 8, 24, 17, 0),
            dueHasTime: true,
            priority: 5,
            listID: "school-tasks",
            listTitle: "School Tasks",
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func descriptor(
        _ id: String,
        title: String,
        writable: Bool = true
    ) -> CalendarDescriptor {
        CalendarDescriptor(
            id: id,
            title: title,
            colorHex: "#346B66",
            allowsContentModifications: writable
        )
    }

    private func event(
        id: String,
        title: String,
        start: Date,
        end: Date,
        calendarID: String
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: "mutation-\(id)",
            title: title,
            start: start,
            end: end,
            isAllDay: false,
            calendarID: calendarID,
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        localCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

@MainActor
private final class TimeBlockScopeResolverSpy {
    var scope: ProfileScope
    var error: Error?
    private(set) var requestedIdentities: [ProfileIdentity] = []

    init(scope: ProfileScope) {
        self.scope = scope
    }

    func resolve(_ identity: ProfileIdentity) throws -> ProfileScope {
        requestedIdentities.append(identity)
        if let error { throw error }
        return scope
    }
}

@MainActor
private final class TimeBlockCalendarSpy: CalendarServicing {
    var accessState: AccessState = .granted
    var descriptors: [CalendarDescriptor]
    var events: [CalendarEventSnapshot]
    var createResult: String?
    var createError: Error?
    private(set) var fetchCalendarIDs: [Set<String>] = []
    private(set) var fetchIntervals: [DateInterval] = []
    private(set) var createdDrafts: [EventDraft] = []

    init(
        descriptors: [CalendarDescriptor],
        events: [CalendarEventSnapshot],
        createResult: String?
    ) {
        self.descriptors = descriptors
        self.events = events
        self.createResult = createResult
    }

    func requestFullAccess() async -> AccessState { accessState }

    func calendars() -> [CalendarDescriptor] {
        accessState == .granted ? descriptors : []
    }

    func fetchEvents(
        in interval: DateInterval,
        calendarIDs: Set<String>
    ) throws -> [CalendarEventSnapshot] {
        fetchIntervals.append(interval)
        fetchCalendarIDs.append(calendarIDs)
        return events.filter {
            calendarIDs.contains($0.calendarID)
                && $0.start < interval.end
                && $0.end > interval.start
        }
    }

    func createEvent(_ draft: EventDraft) throws -> String? {
        createdDrafts.append(draft)
        if let createError { throw createError }
        return createResult
    }

    func event(id: String) -> CalendarEventSnapshot? {
        events.first { $0.id == id }
    }

    func updateEvent(
        id: String,
        draft: EventDraft,
        scope: RecurrenceEditScope
    ) throws {}

    func deleteEvent(id: String, scope: RecurrenceEditScope) throws {}
}

private enum TimeBlockProviderError: Error {
    case failed
}
