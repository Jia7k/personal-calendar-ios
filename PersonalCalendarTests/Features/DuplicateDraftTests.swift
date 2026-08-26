import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class DuplicateDraftTests: XCTestCase {
    private let profileID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let categoryID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let eventStart = Date(timeIntervalSinceReferenceDate: 100_000)
    private let confirmedStart = Date(timeIntervalSinceReferenceDate: 200_000)
    private let taskDue = Date(timeIntervalSinceReferenceDate: 300_000)
    private let taskAlarm = Date(timeIntervalSinceReferenceDate: 299_100)
    private let recurrence = RecurrenceRuleDraft(
        frequency: .weekly,
        interval: 2,
        weekdays: [2, 4],
        endDate: nil
    )

    func testEventDuplicateDraftKeepsUserFieldsAndDurationAtConfirmedStart() {
        let source = event()

        let draft = EventEditorViewModel.duplicateDraft(
            from: source,
            confirmedStart: confirmedStart,
            destinationCalendarID: "school"
        )

        XCTAssertEqual(
            draft,
            EventDraft(
                title: "INF 2003 Lecture",
                start: confirmedStart,
                end: confirmedStart.addingTimeInterval(5_400),
                isAllDay: false,
                calendarID: "school",
                notes: "Bring the lab worksheet",
                location: "E2-08-01",
                alarms: .replace([-1_800]),
                recurrence: .replace(recurrence)
            )
        )
    }

    func testAllDayEventDuplicatePreservesCalendarDaySpanAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let sourceStart = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 8)
        )!
        let sourceEnd = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 9)
        )!
        let newStart = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 16)
        )!
        let expectedEnd = calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 17)
        )!
        let source = CalendarEventSnapshot(
            id: "all-day",
            mutationID: "all-day-mutation",
            title: "Study break",
            start: sourceStart,
            end: sourceEnd,
            isAllDay: true,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: false
        )

        let draft = EventEditorViewModel.duplicateDraft(
            from: source,
            confirmedStart: newStart,
            destinationCalendarID: "school",
            calendar: calendar
        )

        XCTAssertEqual(draft.start, newStart)
        XCTAssertEqual(draft.end, expectedEnd)
        XCTAssertTrue(draft.isAllDay)
    }

    func testEventDuplicateShiftsFiniteRecurrenceEndWithNewStartDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let originalStart = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 3, hour: 9)
        )!
        let newStart = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 10, hour: 9)
        )!
        let originalEndDate = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 31)
        )!
        let expectedEndDate = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 7)
        )!
        let finiteRule = RecurrenceRuleDraft(
            frequency: .weekly,
            interval: 1,
            weekdays: [2],
            endDate: originalEndDate
        )
        let source = CalendarEventSnapshot(
            id: "finite-series",
            mutationID: "finite-series-mutation",
            title: "Tutorial",
            start: originalStart,
            end: originalStart.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "school",
            calendarTitle: "School",
            allowsModification: true,
            hasRecurrence: true,
            recurrence: .editable(finiteRule)
        )

        let draft = EventEditorViewModel.duplicateDraft(
            from: source,
            confirmedStart: newStart,
            destinationCalendarID: "school",
            calendar: calendar
        )

        guard case let .replace(shiftedRule) = draft.recurrence else {
            return XCTFail("Expected the finite repeat rule to be preserved")
        }
        XCTAssertEqual(shiftedRule.endDate, expectedEndDate)
    }

    func testEventDuplicateEditorPerformsNoWriteUntilSaveAndCreatesANewItem() async {
        let service = DuplicateCalendarService(
            calendars: [calendarDescriptor("school")]
        )
        let draft = EventEditorViewModel.duplicateDraft(
            from: event(),
            confirmedStart: confirmedStart,
            destinationCalendarID: "school"
        )

        let subject = EventEditorViewModel.create(
            service: service,
            savedDefaultCalendarID: nil,
            creationProfile: profileContext(),
            initialDraft: draft
        )

        XCTAssertTrue(service.createdDrafts.isEmpty)
        XCTAssertTrue(service.updatedIDs.isEmpty)
        XCTAssertTrue(service.deletedIDs.isEmpty)
        XCTAssertTrue(service.eventLookups.isEmpty)

        await subject.requestSave()

        XCTAssertEqual(service.createdDrafts, [draft])
        XCTAssertTrue(service.updatedIDs.isEmpty)
        XCTAssertTrue(service.deletedIDs.isEmpty)
        XCTAssertTrue(service.eventLookups.isEmpty)
    }

    func testEventDuplicateSaveFailsClosedWhenProfileMembershipChanges() async {
        let service = DuplicateCalendarService(
            calendars: [calendarDescriptor("school")]
        )
        var liveCalendarIDs: Set<String> = ["school"]
        let draft = EventEditorViewModel.duplicateDraft(
            from: event(),
            confirmedStart: confirmedStart,
            destinationCalendarID: "school"
        )
        let subject = EventEditorViewModel.create(
            service: service,
            savedDefaultCalendarID: nil,
            initialDraft: draft,
            creationDestinationCalendarIDs: ["school"],
            resolveCreationDestinationCalendarIDs: { liveCalendarIDs }
        )

        liveCalendarIDs = []
        await subject.requestSave()

        XCTAssertTrue(service.createdDrafts.isEmpty)
        XCTAssertEqual(subject.phase, .failed(action: .save, error: .invalidDestination))
    }

    func testEventDuplicateTapFailsClosedWhenProfileScopeCannotResolve() async {
        let service = DuplicateCalendarService(
            calendars: [calendarDescriptor("source-calendar")],
            event: event()
        )
        let subject = EventEditorViewModel.edit(
            displayID: "display-event-id",
            service: service,
            duplicateDestinationCalendarIDs: ["source-calendar"],
            resolveDuplicateDestinationCalendarIDs: {
                throw DuplicateTestError.unavailable
            }
        )
        await subject.load()

        XCTAssertTrue(subject.canDuplicate)
        XCTAssertNil(subject.makeDuplicate(confirmedStart: confirmedStart) { _ in })
        XCTAssertTrue(service.createdDrafts.isEmpty)
    }

    func testEventDuplicateTapFailsWhenCategoryCannotBeReadFaithfully() async {
        let service = DuplicateCalendarService(
            calendars: [calendarDescriptor("source-calendar")],
            event: event()
        )
        let subject = EventEditorViewModel.edit(
            displayID: "display-event-id",
            service: service,
            categories: ThrowingDuplicateCategoryRepository(),
            duplicateDestinationCalendarIDs: ["source-calendar"],
            resolveDuplicateDestinationCalendarIDs: { ["source-calendar"] }
        )
        await subject.load()

        XCTAssertNil(subject.makeDuplicate(confirmedStart: confirmedStart) { _ in })
        XCTAssertTrue(service.createdDrafts.isEmpty)
    }

    func testTaskDuplicateDraftMaterializesUserFieldsForCreation() throws {
        let source = task()

        let draft = try XCTUnwrap(
            TaskEditorViewModel.duplicateDraft(
                from: source,
                destinationListID: "school-tasks",
                creationProfile: profileContext(),
                availableLists: [reminderListDescriptor("school-tasks")]
            )
        )

        XCTAssertEqual(
            draft,
            ReminderDraft(
                title: "Submit assignment",
                notes: "Attach the bibliography",
                dueDate: taskDue,
                dueHasTime: true,
                priority: 5,
                listID: "school-tasks",
                alarm: .replace(taskAlarm),
                recurrence: .replace(recurrence)
            )
        )
    }

    func testTaskDuplicateDraftRejectsDestinationOutsideTheWritableProfileSet() {
        let context = profileContext()
        let availableLists = [
            reminderListDescriptor("school-tasks"),
            reminderListDescriptor("outside"),
            reminderListDescriptor("locked", writable: false)
        ]

        XCTAssertNil(
            TaskEditorViewModel.duplicateDraft(
                from: task(),
                destinationListID: "outside",
                creationProfile: context,
                availableLists: availableLists
            )
        )
        XCTAssertNil(
            TaskEditorViewModel.duplicateDraft(
                from: task(),
                destinationListID: "locked",
                creationProfile: context,
                availableLists: availableLists
            )
        )
    }

    func testTaskDuplicateEditorPerformsNoWriteUntilSaveAndCreatesANewItem() async throws {
        let service = DuplicateRemindersService(
            lists: [reminderListDescriptor("school-tasks")]
        )
        let draft = try XCTUnwrap(
            TaskEditorViewModel.duplicateDraft(
                from: task(),
                destinationListID: "school-tasks",
                creationProfile: profileContext(),
                availableLists: service.lists()
            )
        )

        let subject = TaskEditorViewModel.creating(
            service: service,
            creationProfile: profileContext(),
            initialDraft: draft
        )

        XCTAssertTrue(service.createdDrafts.isEmpty)
        XCTAssertTrue(service.updatedIDs.isEmpty)
        XCTAssertTrue(service.deletedIDs.isEmpty)
        XCTAssertTrue(service.reminderLookups.isEmpty)

        await subject.requestSave()

        XCTAssertEqual(service.createdDrafts, [draft])
        XCTAssertTrue(service.updatedIDs.isEmpty)
        XCTAssertTrue(service.deletedIDs.isEmpty)
        XCTAssertTrue(service.reminderLookups.isEmpty)
    }

    func testTaskDuplicateSaveFailsClosedWhenProfileMembershipChanges() async throws {
        let service = DuplicateRemindersService(
            lists: [reminderListDescriptor("school-tasks")]
        )
        var liveListIDs: Set<String> = ["school-tasks"]
        let draft = try XCTUnwrap(
            TaskEditorViewModel.duplicateDraft(
                from: task(),
                destinationListID: "school-tasks",
                creationProfile: profileContext(),
                availableLists: service.lists()
            )
        )
        let subject = TaskEditorViewModel.creating(
            service: service,
            initialDraft: draft,
            creationDestinationListIDs: ["school-tasks"],
            resolveCreationDestinationListIDs: { liveListIDs }
        )

        liveListIDs = []
        await subject.requestSave()

        XCTAssertTrue(service.createdDrafts.isEmpty)
        XCTAssertEqual(subject.phase, .failed(.save, .invalidDestination))
    }

    func testTaskDuplicateTapFailsClosedWhenProfileScopeCannotResolve() {
        let service = DuplicateRemindersService(
            lists: [reminderListDescriptor("source-list")],
            reminder: task()
        )
        let subject = TaskEditorViewModel.editing(
            reminderID: task().id,
            service: service,
            duplicateDestinationListIDs: ["source-list"],
            resolveDuplicateDestinationListIDs: {
                throw DuplicateTestError.unavailable
            }
        )

        XCTAssertTrue(subject.canDuplicate)
        XCTAssertNil(subject.makeDuplicate { _ in })
        XCTAssertTrue(service.createdDrafts.isEmpty)
    }

    func testTaskDuplicateTapFailsWhenCategoryCannotBeReadFaithfully() {
        let service = DuplicateRemindersService(
            lists: [reminderListDescriptor("source-list")],
            reminder: task()
        )
        let subject = TaskEditorViewModel.editing(
            reminderID: task().id,
            service: service,
            categories: ThrowingDuplicateCategoryRepository(),
            duplicateDestinationListIDs: ["source-list"],
            resolveDuplicateDestinationListIDs: { ["source-list"] }
        )

        XCTAssertNil(subject.makeDuplicate { _ in })
        XCTAssertTrue(service.createdDrafts.isEmpty)
    }

    func testRoutineDuplicateDraftCopiesScheduleAndCategoryButNotIdentityOrState() {
        let source = routine()

        let draft = RoutinesViewModel.duplicateDraft(from: source)

        XCTAssertEqual(
            draft,
            RoutineDraft(
                title: "Review notes Copy",
                weekdays: [2, 3, 4, 5, 6],
                window: .evening,
                reminderHour: 19,
                reminderMinute: 30,
                categoryID: categoryID
            )
        )
    }

    func testRoutineDuplicateWaitsForExplicitProfileAwareSaveAndStartsWithoutHistory() {
        let repository = DuplicateRoutineRepository()
        let profileMutations = DuplicateRoutineProfileMutations()
        let subject = RoutinesViewModel(
            repository: repository,
            routineProfileMutations: profileMutations,
            selectedProfileID: { self.profileID }
        )
        let draft = RoutinesViewModel.duplicateDraft(from: routine())

        XCTAssertTrue(repository.createdDrafts.isEmpty)
        XCTAssertTrue(repository.completionWrites.isEmpty)
        XCTAssertTrue(profileMutations.createCalls.isEmpty)

        XCTAssertTrue(subject.create(draft))

        XCTAssertTrue(repository.createdDrafts.isEmpty)
        XCTAssertTrue(repository.completionWrites.isEmpty)
        XCTAssertEqual(
            profileMutations.createCalls,
            [.init(draft: draft, profileID: profileID)]
        )
    }

    private func event() -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: "display-event-id",
            mutationID: "opaque-provider-mutation-id",
            title: "INF 2003 Lecture",
            start: eventStart,
            end: eventStart.addingTimeInterval(5_400),
            isAllDay: false,
            calendarID: "source-calendar",
            calendarTitle: "Source Calendar",
            allowsModification: true,
            hasRecurrence: true,
            notes: "Bring the lab worksheet",
            location: "E2-08-01",
            alarms: .editable([-1_800]),
            recurrence: .editable(recurrence)
        )
    }

    private func task() -> ReminderSnapshot {
        ReminderSnapshot(
            id: "opaque-provider-reminder-id",
            title: "Submit assignment",
            notes: "Attach the bibliography",
            dueDate: taskDue,
            dueHasTime: true,
            priority: 5,
            listID: "source-list",
            listTitle: "Source List",
            isCompleted: true,
            allowsModification: true,
            hasRecurrence: true,
            alarm: .editable(taskAlarm),
            recurrence: .editable(recurrence)
        )
    }

    private func routine() -> RoutineSnapshot {
        RoutineSnapshot(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            title: "Review notes",
            weekdays: [2, 3, 4, 5, 6],
            window: .evening,
            reminderHour: 19,
            reminderMinute: 30,
            isPaused: true,
            isArchived: true,
            categoryID: categoryID
        )
    }

    private func profileContext() -> CreationProfileContext {
        CreationProfileContext(
            profileID: profileID,
            profileName: "School",
            memberCalendarIDs: ["school"],
            memberReminderListIDs: ["school-tasks", "locked"],
            defaultCalendarID: "school",
            defaultReminderListID: "school-tasks",
            requiresExplicitCalendarDestination: false,
            requiresExplicitReminderDestination: false
        )
    }

    private func calendarDescriptor(
        _ id: String,
        writable: Bool = true
    ) -> CalendarDescriptor {
        .init(
            id: id,
            title: id,
            colorHex: "#3A8D7C",
            allowsContentModifications: writable
        )
    }

    private func reminderListDescriptor(
        _ id: String,
        writable: Bool = true
    ) -> ReminderListDescriptor {
        .init(
            id: id,
            title: id,
            colorHex: "#3A8D7C",
            allowsContentModifications: writable
        )
    }
}

@MainActor
private final class DuplicateCalendarService: CalendarServicing {
    var accessState: AccessState = .granted
    let calendarValues: [CalendarDescriptor]
    var eventValue: CalendarEventSnapshot?
    private(set) var createdDrafts: [EventDraft] = []
    private(set) var updatedIDs: [String] = []
    private(set) var deletedIDs: [String] = []
    private(set) var eventLookups: [String] = []

    init(
        calendars: [CalendarDescriptor],
        event: CalendarEventSnapshot? = nil
    ) {
        calendarValues = calendars
        eventValue = event
    }

    func requestFullAccess() async -> AccessState { accessState }
    func calendars() -> [CalendarDescriptor] { calendarValues }
    func fetchEvents(
        in interval: DateInterval,
        calendarIDs: Set<String>
    ) throws -> [CalendarEventSnapshot] { [] }
    func createEvent(_ draft: EventDraft) throws -> String? {
        createdDrafts.append(draft)
        return "new-event-id"
    }
    func event(id: String) -> CalendarEventSnapshot? {
        eventLookups.append(id)
        return eventValue
    }
    func updateEvent(
        id: String,
        draft: EventDraft,
        scope: RecurrenceEditScope
    ) throws {
        updatedIDs.append(id)
    }
    func deleteEvent(id: String, scope: RecurrenceEditScope) throws {
        deletedIDs.append(id)
    }
}

@MainActor
private final class DuplicateRemindersService: RemindersServicing {
    var accessState: AccessState = .granted
    let listValues: [ReminderListDescriptor]
    var reminderValue: ReminderSnapshot?
    private(set) var createdDrafts: [ReminderDraft] = []
    private(set) var updatedIDs: [String] = []
    private(set) var deletedIDs: [String] = []
    private(set) var reminderLookups: [String] = []

    init(
        lists: [ReminderListDescriptor],
        reminder: ReminderSnapshot? = nil
    ) {
        listValues = lists
        reminderValue = reminder
    }

    func requestFullAccess() async -> AccessState { accessState }
    func lists() -> [ReminderListDescriptor] { listValues }
    func fetchReminders(listIDs: Set<String>) async throws -> [ReminderSnapshot] { [] }
    func createReminder(_ draft: ReminderDraft) throws -> String? {
        createdDrafts.append(draft)
        return "new-reminder-id"
    }
    func setCompleted(id: String, completed: Bool) throws {}
    func reminder(id: String) -> ReminderSnapshot? {
        reminderLookups.append(id)
        return reminderValue
    }
    func updateReminder(id: String, draft: ReminderDraft) throws {
        updatedIDs.append(id)
    }
    func deleteReminder(id: String) throws {
        deletedIDs.append(id)
    }
}

private enum DuplicateTestError: Error {
    case unavailable
}

@MainActor
private final class ThrowingDuplicateCategoryRepository: CategoryRepository {
    func list() throws -> [CategorySnapshot] {
        throw DuplicateTestError.unavailable
    }
    func create(name: String, colorHex: String) throws -> UUID {
        throw DuplicateTestError.unavailable
    }
    func update(id: UUID, name: String, colorHex: String) throws {
        throw DuplicateTestError.unavailable
    }
    func reorder(ids: [UUID]) throws {
        throw DuplicateTestError.unavailable
    }
    func delete(id: UUID, reassignedTo replacementID: UUID?) throws {
        throw DuplicateTestError.unavailable
    }
    func assign(
        categoryID: UUID?,
        to source: ExternalItemSource,
        externalID: String
    ) throws {
        throw DuplicateTestError.unavailable
    }
    func category(
        for source: ExternalItemSource,
        externalID: String
    ) throws -> CategorySnapshot? {
        throw DuplicateTestError.unavailable
    }
    func removeUnresolvedLinks(
        for source: ExternalItemSource,
        validExternalIDs: Set<String>
    ) throws {
        throw DuplicateTestError.unavailable
    }
    func seedDefaultsIfNeeded(settings: AppSettingsStore) throws {
        throw DuplicateTestError.unavailable
    }
}

@MainActor
private final class DuplicateRoutineRepository: RoutineRepository {
    struct CompletionWrite: Equatable {
        let routineID: UUID
        let day: LocalDay
        let completed: Bool
    }

    private(set) var createdDrafts: [RoutineDraft] = []
    private(set) var completionWrites: [CompletionWrite] = []

    func list(includeArchived: Bool) throws -> [RoutineSnapshot] { [] }
    func create(_ draft: RoutineDraft) throws -> UUID {
        createdDrafts.append(draft)
        return UUID()
    }
    func update(id: UUID, draft: RoutineDraft) throws {}
    func setPaused(id: UUID, paused: Bool) throws {}
    func setArchived(id: UUID, archived: Bool) throws {}
    func delete(id: UUID) throws {}
    func setCompleted(
        routineID: UUID,
        day: LocalDay,
        completed: Bool
    ) throws {
        completionWrites.append(
            .init(routineID: routineID, day: day, completed: completed)
        )
    }
    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool { false }
    func completedDays(routineID: UUID) throws -> Set<LocalDay> { [] }
}

@MainActor
private final class DuplicateRoutineProfileMutations: RoutineProfileMutating {
    struct CreateCall: Equatable {
        let draft: RoutineDraft
        let profileID: UUID
    }

    private(set) var createCalls: [CreateCall] = []

    func create(draft: RoutineDraft, profileID: UUID) throws -> UUID {
        createCalls.append(.init(draft: draft, profileID: profileID))
        return UUID(uuidString: "12345678-1234-1234-1234-123456789012")!
    }

    func delete(id: UUID) throws {}
}
