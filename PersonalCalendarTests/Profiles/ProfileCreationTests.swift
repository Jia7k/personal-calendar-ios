import Foundation
import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileCreationTests: XCTestCase {
    private static let personalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let schoolID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testEverythingRequiresSavedProfileThenChosenProfileSuppliesExactDefaults() throws {
        let resolver = CreationProfileResolver(
            profiles: [
                profile(id: Self.personalID, name: "Personal", defaultCalendarID: "home"),
                profile(id: Self.schoolID, name: "School", defaultCalendarID: "school", defaultReminderListID: "assignments")
            ],
            resolveScope: { identity in
                switch identity {
                case .everything:
                    XCTFail("Everything must not be resolved as a creation destination")
                    return self.scope(identity: .everything)
                case .saved(Self.schoolID):
                    return self.scope(
                        identity: .saved(Self.schoolID),
                        calendarIDs: ["school"],
                        reminderListIDs: ["assignments"],
                        defaultCalendarID: "school",
                        defaultReminderListID: "assignments"
                    )
                case .saved:
                    return self.scope(identity: .saved(Self.personalID), calendarIDs: ["home"], defaultCalendarID: "home")
                }
            }
        )

        XCTAssertEqual(
            try resolver.resolve(active: .everything),
            .chooseSavedProfile([Self.personalID, Self.schoolID])
        )

        let context = try resolver.resolve(chosen: Self.schoolID)
        XCTAssertEqual(context.profileID, Self.schoolID)
        XCTAssertEqual(context.profileName, "School")
        XCTAssertEqual(context.memberCalendarIDs, ["school"])
        XCTAssertEqual(context.memberReminderListIDs, ["assignments"])
        XCTAssertEqual(context.defaultCalendarID, "school")
        XCTAssertEqual(context.defaultReminderListID, "assignments")
        XCTAssertFalse(context.requiresExplicitCalendarDestination)
        XCTAssertFalse(context.requiresExplicitReminderDestination)
    }

    func testCapturedProfileResolutionNeverFallsBackToEverythingOrAnotherProfile() throws {
        let profiles = [
            profile(id: Self.personalID, name: "Personal", defaultCalendarID: "home"),
            profile(id: Self.schoolID, name: "School", defaultCalendarID: "school")
        ]
        let resolver = CreationProfileResolver(
            profiles: profiles,
            resolveScope: { identity in
                switch identity {
                case .saved(Self.schoolID):
                    return self.scope(
                        identity: identity,
                        calendarIDs: ["school"],
                        defaultCalendarID: "school"
                    )
                case .saved:
                    return self.scope(
                        identity: identity,
                        calendarIDs: ["home"],
                        defaultCalendarID: "home"
                    )
                case .everything:
                    XCTFail("Everything must not become a creation destination")
                    return self.scope(identity: .everything)
                }
            }
        )

        XCTAssertEqual(
            try resolver.resolve(captured: .saved(Self.schoolID), active: .everything),
            .ready(try resolver.resolve(chosen: Self.schoolID))
        )
        XCTAssertEqual(
            try resolver.resolve(
                captured: .saved(UUID(uuidString: "99999999-9999-4999-8999-999999999999")!),
                active: .saved(Self.personalID)
            ),
            .chooseSavedProfile([Self.personalID, Self.schoolID])
        )
        XCTAssertEqual(
            try resolver.resolve(captured: nil, active: .everything),
            .chooseSavedProfile([Self.personalID, Self.schoolID])
        )
    }

    func testMissingProfileDefaultsRequireExplicitDestinationBeforeQuickEntrySaves() {
        let calendar = FakeCalendarService(
            access: .granted,
            descriptors: [calendarDescriptor(id: "school")],
            defaultCalendarID: "school"
        )
        let reminders = FakeRemindersService(
            access: .granted,
            descriptors: [listDescriptor(id: "assignments")],
            defaultListID: "assignments"
        )
        let context = creationContext(
            defaultCalendarID: nil,
            defaultReminderListID: nil,
            requiresExplicitCalendarDestination: true,
            requiresExplicitReminderDestination: true
        )

        let eventSaver = RecordingCreationSaver()
        let event = QuickEntryViewModel(
            parser: StaticCreationParser(eventPreview(destinationID: nil)),
            saver: eventSaver,
            context: parseContext(),
            destinations: .resolve(calendar: calendar, reminders: reminders, context: context),
            creationProfile: context
        )
        event.text = "Class tomorrow at 9am"
        event.parse()
        event.confirmSave()

        XCTAssertEqual(event.errorMessage, "Choose a calendar before saving.")
        XCTAssertTrue(eventSaver.received.isEmpty)

        let taskSaver = RecordingCreationSaver()
        let task = QuickEntryViewModel(
            parser: StaticCreationParser(taskPreview(destinationID: nil)),
            saver: taskSaver,
            context: parseContext(),
            destinations: .resolve(calendar: calendar, reminders: reminders, context: context),
            creationProfile: context
        )
        task.text = "Submit assignment tomorrow"
        task.parse()
        task.confirmSave()

        XCTAssertEqual(task.errorMessage, "Choose a reminder list before saving.")
        XCTAssertTrue(taskSaver.received.isEmpty)
    }

    func testExplicitDestinationOutsideProfileIsAllowedAndClearlyIdentified() {
        let calendar = FakeCalendarService(
            access: .granted,
            descriptors: [calendarDescriptor(id: "school"), calendarDescriptor(id: "work")],
            defaultCalendarID: "school"
        )
        let reminders = FakeRemindersService(access: .granted)
        let context = creationContext(
            calendarIDs: ["school"],
            defaultCalendarID: nil,
            requiresExplicitCalendarDestination: true
        )
        let saver = RecordingCreationSaver()
        let subject = QuickEntryViewModel(
            parser: StaticCreationParser(eventPreview(destinationID: nil)),
            saver: saver,
            context: parseContext(),
            destinations: .resolve(calendar: calendar, reminders: reminders, context: context),
            creationProfile: context
        )
        subject.text = "Work review tomorrow at 9am"
        subject.parse()

        subject.selectDestination("work")
        XCTAssertEqual(subject.destinationVisibilityHint, "Outside School")
        subject.confirmSave()

        XCTAssertEqual(saver.received.map(\.destinationID), ["work"])
    }

    func testRouterRejectsNilRequiredDestinationButAllowsExplicitOutsideOverride() throws {
        let calendar = FakeCalendarService(
            access: .granted,
            descriptors: [calendarDescriptor(id: "school"), calendarDescriptor(id: "work")],
            defaultCalendarID: "school"
        )
        let context = creationContext(
            calendarIDs: ["school"],
            defaultCalendarID: nil,
            requiresExplicitCalendarDestination: true
        )
        let subject = SaveRouter(
            calendar: calendar,
            reminders: FakeRemindersService(access: .granted),
            routines: FakeRoutineRepository(),
            routineProfileMutations: RecordingRoutineProfileMutator(),
            creationProfile: context,
            localCalendar: configuredCalendar()
        )

        XCTAssertThrowsError(try subject.save(eventPreview(destinationID: nil))) { error in
            XCTAssertEqual(error as? QuickEntrySaveError, .explicitDestinationRequired)
        }
        XCTAssertTrue(calendar.createdDrafts.isEmpty)

        XCTAssertEqual(try subject.save(eventPreview(destinationID: "work")), .event(id: "created-event-1"))
        XCTAssertEqual(calendar.createdDrafts.map(\.calendarID), ["work"])
    }

    func testRoutineCreationUsesAtomicMutatorWithCapturedProfileID() throws {
        let mutator = RecordingRoutineProfileMutator()
        let context = creationContext()
        let repository = FakeRoutineRepository()
        let subject = SaveRouter(
            calendar: FakeCalendarService(access: .granted),
            reminders: FakeRemindersService(access: .granted),
            routines: repository,
            routineProfileMutations: mutator,
            creationProfile: context,
            localCalendar: configuredCalendar()
        )

        let outcome = try subject.save(routinePreview())

        XCTAssertEqual(outcome, .routine(id: mutator.createdID))
        XCTAssertEqual(mutator.profileIDs, [Self.schoolID])
        XCTAssertEqual(mutator.drafts.map(\.title), ["Study"])
        XCTAssertTrue(repository.routines.isEmpty)
    }

    func testFutureCreateEditorsUseProfileDefaultsWhileEditFactoriesRemainSourceOwned() {
        let calendar = FakeCalendarService(
            access: .granted,
            descriptors: [calendarDescriptor(id: "home"), calendarDescriptor(id: "school")]
        )
        let reminders = FakeRemindersService(
            access: .granted,
            descriptors: [listDescriptor(id: "personal"), listDescriptor(id: "assignments")]
        )
        let context = creationContext(
            calendarIDs: ["school"],
            reminderListIDs: ["assignments"],
            defaultCalendarID: "school",
            defaultReminderListID: "assignments"
        )

        let event = EventEditorViewModel.create(
            service: calendar,
            savedDefaultCalendarID: "home",
            creationProfile: context
        )
        let task = TaskEditorViewModel.creating(
            service: reminders,
            savedDefaultListID: "personal",
            creationProfile: context
        )

        XCTAssertEqual(event.destinationCalendarID, "school")
        XCTAssertEqual(task.form.listID, "assignments")
    }

    private func profile(
        id: UUID,
        name: String,
        defaultCalendarID: String? = nil,
        defaultReminderListID: String? = nil
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            id: id,
            name: name,
            colorHex: "#4868A8",
            symbolName: "person.fill",
            sortOrder: id == Self.personalID ? 0 : 1,
            calendarIDs: defaultCalendarID.map { [$0] } ?? [],
            reminderListIDs: defaultReminderListID.map { [$0] } ?? [],
            routineIDs: [],
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID
        )
    }

    private func scope(
        identity: ProfileIdentity,
        calendarIDs: Set<String> = [],
        reminderListIDs: Set<String> = [],
        defaultCalendarID: String? = nil,
        defaultReminderListID: String? = nil
    ) -> ProfileScope {
        ProfileScope(
            identity: identity,
            calendarIDs: calendarIDs,
            reminderListIDs: reminderListIDs,
            routineIDs: [],
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID
        )
    }

    private func creationContext(
        calendarIDs: Set<String> = ["school"],
        reminderListIDs: Set<String> = ["assignments"],
        defaultCalendarID: String? = "school",
        defaultReminderListID: String? = "assignments",
        requiresExplicitCalendarDestination: Bool = false,
        requiresExplicitReminderDestination: Bool = false
    ) -> CreationProfileContext {
        CreationProfileContext(
            profileID: Self.schoolID,
            profileName: "School",
            memberCalendarIDs: calendarIDs,
            memberReminderListIDs: reminderListIDs,
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID,
            requiresExplicitCalendarDestination: requiresExplicitCalendarDestination,
            requiresExplicitReminderDestination: requiresExplicitReminderDestination
        )
    }

    private func calendarDescriptor(id: String) -> CalendarDescriptor {
        CalendarDescriptor(id: id, title: id.capitalized, colorHex: "#4868A8", allowsContentModifications: true)
    }

    private func listDescriptor(id: String) -> ReminderListDescriptor {
        ReminderListDescriptor(id: id, title: id.capitalized, colorHex: "#4868A8", allowsContentModifications: true)
    }

    private func configuredCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func parseContext() -> QuickEntryParseContext {
        let calendar = configuredCalendar()
        return QuickEntryParseContext(
            now: calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 10))!,
            calendar: calendar,
            locale: Locale(identifier: "en_SG"),
            timeZone: calendar.timeZone
        )
    }

    private func eventPreview(destinationID: String?) -> QuickEntryPreview {
        let calendar = configuredCalendar()
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 9))!
        return QuickEntryPreview(
            kind: .event,
            title: "Class",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            destinationID: destinationID
        )
    }

    private func taskPreview(destinationID: String?) -> QuickEntryPreview {
        QuickEntryPreview(kind: .task, title: "Assignment", destinationID: destinationID)
    }

    private func routinePreview() -> QuickEntryPreview {
        QuickEntryPreview(
            kind: .routine,
            title: "Study",
            routineWindow: .evening,
            weekdays: [2, 3, 4, 5, 6]
        )
    }
}

private struct StaticCreationParser: QuickEntryParsing {
    let preview: QuickEntryPreview

    init(_ preview: QuickEntryPreview) {
        self.preview = preview
    }

    func parse(_ text: String, context: QuickEntryParseContext) throws -> QuickEntryPreview {
        preview
    }
}

@MainActor
private final class RecordingCreationSaver: QuickEntrySaving {
    private(set) var received: [QuickEntryPreview] = []

    func save(_ preview: QuickEntryPreview) throws -> QuickEntrySaveOutcome {
        received.append(preview)
        return switch preview.kind {
        case .event: .event(id: "event")
        case .task: .task(id: "task")
        case .routine: .routine(id: UUID())
        }
    }
}

@MainActor
private final class RecordingRoutineProfileMutator: RoutineProfileMutating {
    let createdID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private(set) var drafts: [RoutineDraft] = []
    private(set) var profileIDs: [UUID] = []

    func create(draft: RoutineDraft, profileID: UUID) throws -> UUID {
        drafts.append(draft)
        profileIDs.append(profileID)
        return createdID
    }

    func delete(id: UUID) throws {}
}
