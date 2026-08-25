import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileFeatureScopeTests: XCTestCase {
    private static let schoolID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let personalID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let studyRoutineID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private static let personalRoutineID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testSchoolScopeIsCapturedOnceAcrossEveryFeatureWithoutProviderWrites() async {
        let fixture = makeFixture(scope: Self.schoolScope)

        await fixture.loadAll()

        XCTAssertEqual(
            fixture.calendarService.fetchCalendarIDs,
            [Set(["school-calendar"]), Set(["school-calendar"])]
        )
        XCTAssertEqual(
            fixture.remindersService.fetchListIDs,
            [Set(["school-list"]), Set(["school-list"]), Set(["school-list"])]
        )
        XCTAssertEqual(
            Set(fixture.calendarModel.agenda.items.map(\.title)),
            ["School event", "School task", "Study"]
        )
        XCTAssertEqual(
            Set(fixture.todayModel.agenda.items.map(\.title)),
            ["School event", "School task", "Study"]
        )
        XCTAssertEqual(
            (fixture.tasksModel.today + fixture.tasksModel.upcoming + fixture.tasksModel.completed)
                .map(\.id),
            ["school-task"]
        )
        XCTAssertEqual(fixture.routinesModel.active.map(\.id), [Self.studyRoutineID])
        XCTAssertEqual(fixture.routineRepository.completedDaysCallCounts[Self.studyRoutineID], 3)
        XCTAssertNil(fixture.routineRepository.completedDaysCallCounts[Self.personalRoutineID])
        XCTAssertFalse(fixture.calendarModel.isProfileEmpty)
        XCTAssertFalse(fixture.todayModel.isProfileEmpty)
        XCTAssertFalse(fixture.tasksModel.isProfileEmpty)
        XCTAssertFalse(fixture.routinesModel.isProfileEmpty)
        XCTAssertEqual(fixture.totalWrites, 0)
        XCTAssertEqual(fixture.scopeProvider.readCount, 4)
    }

    func testEmptySavedScopePublishesNoDataWithoutExternalFetches() async {
        let fixture = makeFixture(scope: Self.emptySchoolScope)

        await fixture.loadAll()

        XCTAssertTrue(fixture.calendarService.fetchCalendarIDs.isEmpty)
        XCTAssertTrue(fixture.remindersService.fetchListIDs.isEmpty)
        XCTAssertEqual(fixture.routineRepository.completedDaysCallCount, 0)
        XCTAssertEqual(fixture.visibleItemCount, 0)
        XCTAssertTrue(fixture.calendarModel.isProfileEmpty)
        XCTAssertTrue(fixture.todayModel.isProfileEmpty)
        XCTAssertTrue(fixture.tasksModel.isProfileEmpty)
        XCTAssertTrue(fixture.routinesModel.isProfileEmpty)
        XCTAssertEqual(fixture.totalWrites, 0)
        XCTAssertEqual(fixture.scopeProvider.readCount, 4)
    }

    func testSchoolFetchFailureNeverPublishesPersonalCacheDuringOrAfterSuspension() async {
        let fixture = makeFixture(scope: Self.personalScope)
        await fixture.tasksModel.load()
        XCTAssertEqual(fixture.visibleTaskIDs, ["personal-task"])

        fixture.scopeProvider.scope = Self.schoolScope
        fixture.remindersService.fetchError = ProfileFeatureScopeTestError.fetchFailed
        fixture.remindersService.suspendNextFetch = true
        let schoolLoad = Task { await fixture.tasksModel.load() }
        for _ in 0..<100 where !fixture.remindersService.isFetchSuspended {
            await Task.yield()
        }

        XCTAssertTrue(fixture.remindersService.isFetchSuspended)
        XCTAssertTrue(fixture.visibleTaskIDs.isEmpty)

        fixture.remindersService.resumeSuspendedFetch()
        await schoolLoad.value

        XCTAssertTrue(fixture.visibleTaskIDs.isEmpty)
        XCTAssertNotNil(fixture.tasksModel.refreshErrorMessage)
        XCTAssertEqual(
            fixture.remindersService.fetchListIDs,
            [Set(["personal-list"]), Set(["school-list"])]
        )
        XCTAssertEqual(fixture.scopeProvider.readCount, 2)
        XCTAssertEqual(fixture.totalWrites, 0)
    }

    private static let schoolScope = ProfileScope(
        identity: .saved(schoolID),
        calendarIDs: ["school-calendar"],
        reminderListIDs: ["school-list"],
        routineIDs: [studyRoutineID],
        defaultCalendarID: "school-calendar",
        defaultReminderListID: "school-list"
    )

    private static let personalScope = ProfileScope(
        identity: .saved(personalID),
        calendarIDs: ["personal-calendar"],
        reminderListIDs: ["personal-list"],
        routineIDs: [personalRoutineID],
        defaultCalendarID: "personal-calendar",
        defaultReminderListID: "personal-list"
    )

    private static let emptySchoolScope = ProfileScope(
        identity: .saved(schoolID),
        calendarIDs: [],
        reminderListIDs: [],
        routineIDs: [],
        defaultCalendarID: nil,
        defaultReminderListID: nil
    )

    private func makeFixture(scope: ProfileScope) -> ProfileFeatureScopeFixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 24, hour: 9)
        )!
        let today = LocalDay(date: now, calendar: calendar)
        let weekday = calendar.component(.weekday, from: now)
        let scopeProvider = MutableProfileScopeProvider(scope: scope)
        let calendarService = FakeCalendarService(
            access: .granted,
            events: [
                event(
                    id: "personal-event",
                    title: "Personal event",
                    calendarID: "personal-calendar",
                    start: now.addingTimeInterval(3_600)
                ),
                event(
                    id: "school-event",
                    title: "School event",
                    calendarID: "school-calendar",
                    start: now.addingTimeInterval(7_200)
                )
            ],
            descriptors: [
                calendarDescriptor(id: "personal-calendar"),
                calendarDescriptor(id: "school-calendar")
            ]
        )
        let remindersService = FakeRemindersService(
            access: .granted,
            reminders: [
                reminder(
                    id: "personal-task",
                    title: "Personal task",
                    listID: "personal-list",
                    due: now.addingTimeInterval(10_800)
                ),
                reminder(
                    id: "school-task",
                    title: "School task",
                    listID: "school-list",
                    due: now.addingTimeInterval(14_400)
                )
            ],
            descriptors: [
                reminderDescriptor(id: "personal-list"),
                reminderDescriptor(id: "school-list")
            ]
        )
        let routineRepository = FakeRoutineRepository(
            routines: [
                routine(id: Self.personalRoutineID, title: "Personal routine", weekday: weekday),
                routine(id: Self.studyRoutineID, title: "Study", weekday: weekday)
            ]
        )
        let settings = AppSettingsStore(defaults: .ephemeral)

        let calendarModel = CalendarViewModel(
            today: today,
            calendarService: calendarService,
            remindersService: remindersService,
            routines: routineRepository,
            composer: AgendaComposer(),
            settings: settings,
            currentScope: { try scopeProvider.currentScope() },
            systemCalendar: calendar
        )
        let todayModel = TodayViewModel(
            calendar: calendarService,
            reminders: remindersService,
            routines: routineRepository,
            composer: AgendaComposer(),
            settings: settings,
            currentScope: { try scopeProvider.currentScope() },
            calendarProvider: { calendar },
            now: { now }
        )
        let tasksModel = TasksViewModel(
            service: remindersService,
            settings: settings,
            currentScope: { try scopeProvider.currentScope() },
            calendar: calendar,
            now: { now }
        )
        let routinesModel = RoutinesViewModel(
            repository: routineRepository,
            currentScope: { try scopeProvider.currentScope() },
            calendar: calendar,
            now: { now }
        )

        return ProfileFeatureScopeFixture(
            scopeProvider: scopeProvider,
            calendarService: calendarService,
            remindersService: remindersService,
            routineRepository: routineRepository,
            calendarModel: calendarModel,
            todayModel: todayModel,
            tasksModel: tasksModel,
            routinesModel: routinesModel
        )
    }

    private func calendarDescriptor(id: String) -> CalendarDescriptor {
        CalendarDescriptor(
            id: id,
            title: id,
            colorHex: "#4868A8",
            allowsContentModifications: true
        )
    }

    private func reminderDescriptor(id: String) -> ReminderListDescriptor {
        ReminderListDescriptor(
            id: id,
            title: id,
            colorHex: "#4868A8",
            allowsContentModifications: true
        )
    }

    private func event(
        id: String,
        title: String,
        calendarID: String,
        start: Date
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: id,
            mutationID: id,
            title: title,
            start: start,
            end: start.addingTimeInterval(1_800),
            isAllDay: false,
            calendarID: calendarID,
            calendarTitle: calendarID,
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func reminder(
        id: String,
        title: String,
        listID: String,
        due: Date
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            id: id,
            title: title,
            notes: nil,
            dueDate: due,
            dueHasTime: true,
            priority: 0,
            listID: listID,
            listTitle: listID,
            isCompleted: false,
            allowsModification: true,
            hasRecurrence: false
        )
    }

    private func routine(id: UUID, title: String, weekday: Int) -> RoutineSnapshot {
        RoutineSnapshot(
            id: id,
            title: title,
            weekdays: [weekday],
            window: .anytime,
            reminderHour: nil,
            reminderMinute: nil,
            isPaused: false,
            isArchived: false
        )
    }
}

@MainActor
private final class MutableProfileScopeProvider {
    var scope: ProfileScope
    private(set) var readCount = 0

    init(scope: ProfileScope) {
        self.scope = scope
    }

    func currentScope() throws -> ProfileScope {
        readCount += 1
        return scope
    }
}

@MainActor
private struct ProfileFeatureScopeFixture {
    let scopeProvider: MutableProfileScopeProvider
    let calendarService: FakeCalendarService
    let remindersService: FakeRemindersService
    let routineRepository: FakeRoutineRepository
    let calendarModel: CalendarViewModel
    let todayModel: TodayViewModel
    let tasksModel: TasksViewModel
    let routinesModel: RoutinesViewModel

    func loadAll() async {
        await calendarModel.load()
        await todayModel.load()
        await tasksModel.load()
        routinesModel.reload()
    }

    var visibleTaskIDs: [String] {
        (tasksModel.today + tasksModel.upcoming + tasksModel.completed).map(\.id)
    }

    var visibleItemCount: Int {
        calendarModel.agenda.items.count
            + todayModel.agenda.items.count
            + visibleTaskIDs.count
            + routinesModel.active.count
            + routinesModel.archived.count
    }

    var totalWrites: Int {
        calendarService.successfulWriteCount
            + remindersService.successfulWriteCount
            + routineRepository.createdDrafts.count
            + routineRepository.updateCalls.count
            + routineRepository.pauseCalls.count
            + routineRepository.archiveCalls.count
            + routineRepository.deleteCalls.count
            + routineRepository.completionCalls.count
    }
}

private extension DayAgenda {
    var items: [AgendaItem] {
        allDay + scheduled + priority
    }
}

private enum ProfileFeatureScopeTestError: Error {
    case fetchFailed
}
