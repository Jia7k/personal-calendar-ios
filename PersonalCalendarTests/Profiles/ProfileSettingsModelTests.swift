import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class ProfileSettingsModelTests: XCTestCase {
    private static let personalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let schoolID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testEditorPreservesMissingExternalIDsAndReportsWaitingCounts() throws {
        let profile = profileDraft(
            name: "School",
            calendarIDs: ["school", "missing-calendar"],
            reminderListIDs: ["assignments", "missing-list"]
        )
        let fixture = try makeFixture(
            profiles: [(Self.schoolID, profile)],
            calendars: [calendar(id: "school", writable: true)],
            lists: [list(id: "assignments", writable: true)]
        )

        var editor = try fixture.subject.makeEditor(profileID: Self.schoolID)

        XCTAssertEqual(editor.draft.calendarIDs, ["school", "missing-calendar"])
        XCTAssertEqual(editor.draft.reminderListIDs, ["assignments", "missing-list"])
        XCTAssertEqual(editor.waitingCalendarCount, 1)
        XCTAssertEqual(editor.waitingReminderListCount, 1)

        editor.draft.name = "School renamed"
        _ = try fixture.subject.save(editor)

        let saved = try fixture.repository.profile(id: Self.schoolID)
        XCTAssertEqual(saved.calendarIDs, ["school", "missing-calendar"])
        XCTAssertEqual(saved.reminderListIDs, ["assignments", "missing-list"])
    }

    func testEditorDefaultsUseOnlyWritableCheckedCurrentSources() throws {
        let profile = profileDraft(
            name: "School",
            calendarIDs: ["missing-calendar", "read-only-calendar", "writable-calendar"],
            reminderListIDs: ["missing-list", "read-only-list", "writable-list"],
            defaultCalendarID: "read-only-calendar",
            defaultReminderListID: "read-only-list"
        )
        let fixture = try makeFixture(
            profiles: [(Self.schoolID, profile)],
            calendars: [
                calendar(id: "read-only-calendar", writable: false),
                calendar(id: "writable-calendar", writable: true),
                calendar(id: "unchecked-calendar", writable: true)
            ],
            lists: [
                list(id: "read-only-list", writable: false),
                list(id: "writable-list", writable: true),
                list(id: "unchecked-list", writable: true)
            ]
        )

        let editor = try fixture.subject.makeEditor(profileID: Self.schoolID)

        XCTAssertNil(editor.validatedDefaultCalendarID)
        XCTAssertNil(editor.validatedDefaultReminderListID)
        XCTAssertEqual(editor.defaultCalendarChoices.map(\.id), ["writable-calendar"])
        XCTAssertEqual(editor.defaultReminderListChoices.map(\.id), ["writable-list"])

        _ = try fixture.subject.save(editor)

        let saved = try fixture.repository.profile(id: Self.schoolID)
        XCTAssertNil(saved.defaultCalendarID)
        XCTAssertNil(saved.defaultReminderListID)
        XCTAssertTrue(saved.calendarIDs.contains("read-only-calendar"))
        XCTAssertTrue(saved.reminderListIDs.contains("read-only-list"))
    }

    func testCreateUpdateAndReorderRoundTripThroughRepository() throws {
        let fixture = try makeFixture()
        var create = try fixture.subject.makeEditor(profileID: nil)
        create.draft = profileDraft(name: "Work", calendarIDs: ["work"])

        let workID = try fixture.subject.save(create)

        var update = try fixture.subject.makeEditor(profileID: Self.schoolID)
        update.draft.name = "Study"
        update.draft.colorHex = "#3A8D7C"
        _ = try fixture.subject.save(update)
        try fixture.subject.reorder([workID, Self.personalID, Self.schoolID])

        XCTAssertEqual(fixture.subject.profiles.map(\.id), [workID, Self.personalID, Self.schoolID])
        XCTAssertEqual(fixture.subject.profiles.map(\.name), ["Work", "Personal", "Study"])
        XCTAssertEqual(try fixture.repository.list().map(\.id), [workID, Self.personalID, Self.schoolID])
    }

    func testDeletingLastSavedProfileIsRejectedWithoutDeletionCallback() throws {
        let fixture = try makeFixture(
            profiles: [(Self.personalID, profileDraft(name: "Personal"))]
        )
        let recorder = ProfileSettingsCallbackRecorder()
        let subject = makeModel(fixture: fixture, recorder: recorder)
        try subject.reload()

        XCTAssertThrowsError(try subject.delete(id: Self.personalID)) { error in
            XCTAssertEqual(error as? ProfileRepositoryError, .cannotDeleteLastProfile)
        }

        XCTAssertEqual(subject.profiles.map(\.id), [Self.personalID])
        XCTAssertTrue(recorder.deletedIDs.isEmpty)
    }

    func testDeletingActiveProfileFallsBackToEverythingThroughSelectionController() throws {
        let fixture = try makeFixture(active: .saved(Self.schoolID))
        let initialRevision = fixture.selection.scopeRevision

        try fixture.subject.delete(id: Self.schoolID)

        XCTAssertEqual(fixture.subject.profiles.map(\.id), [Self.personalID])
        XCTAssertEqual(fixture.selection.activeIdentity, .everything)
        XCTAssertEqual(fixture.selection.scopeRevision, initialRevision + 1)
        XCTAssertEqual(fixture.settings.activeProfileIdentity, .everything)
    }

    func testMembershipUpdateEmitsExactlyOneVisibilityChangedCallback() throws {
        let fixture = try makeFixture(
            profiles: [
                (
                    Self.personalID,
                    profileDraft(name: "Personal", calendarIDs: ["home"])
                ),
                (Self.schoolID, profileDraft(name: "School"))
            ],
            calendars: [
                calendar(id: "home", writable: true),
                calendar(id: "shared", writable: true)
            ]
        )
        let recorder = ProfileSettingsCallbackRecorder()
        let subject = makeModel(fixture: fixture, recorder: recorder)
        try subject.reload()
        var editor = try subject.makeEditor(profileID: Self.personalID)
        editor.draft.calendarIDs.insert("shared")

        _ = try subject.save(editor)

        XCTAssertEqual(
            recorder.changeCalls,
            [ProfileSettingsChangeCall(id: Self.personalID, visibilityChanged: true)]
        )
    }

    private func makeFixture(
        profiles: [(UUID, ProfileDraft)]? = nil,
        calendars: [CalendarDescriptor] = [],
        lists: [ReminderListDescriptor] = [],
        routines: [RoutineSnapshot] = [],
        active: ProfileIdentity = .everything
    ) throws -> ProfileSettingsFixture {
        let container = try ModelContainer(
            for: ProfileRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let repository = SwiftDataProfileRepository(context: container.mainContext)
        let seeds = profiles ?? [
            (Self.personalID, profileDraft(name: "Personal", calendarIDs: ["home"])),
            (Self.schoolID, profileDraft(name: "School", calendarIDs: ["school"]))
        ]
        for (id, draft) in seeds {
            _ = try repository.create(draft, id: id)
        }
        let settings = AppSettingsStore(defaults: .ephemeral)
        settings.setActiveProfile(active)
        let selection = ProfileSelectionController(repository: repository, settings: settings)
        try selection.reloadProfiles()
        let calendarService = FakeCalendarService(
            access: .granted,
            descriptors: calendars
        )
        let remindersService = FakeRemindersService(
            access: .granted,
            descriptors: lists
        )
        let routineRepository = FakeRoutineRepository(routines: routines)
        let subject = ProfilesSettingsModel(
            repository: repository,
            calendar: calendarService,
            reminders: remindersService,
            routines: routineRepository,
            profileDidChange: { id, visibilityChanged in
                try selection.profileDidChange(id: id, visibilityChanged: visibilityChanged)
            },
            profileWasDeleted: { id in
                try selection.profileWasDeleted(id: id)
            }
        )
        try subject.reload()
        return ProfileSettingsFixture(
            container: container,
            repository: repository,
            settings: settings,
            selection: selection,
            calendarService: calendarService,
            remindersService: remindersService,
            routineRepository: routineRepository,
            subject: subject
        )
    }

    private func makeModel(
        fixture: ProfileSettingsFixture,
        recorder: ProfileSettingsCallbackRecorder
    ) -> ProfilesSettingsModel {
        ProfilesSettingsModel(
            repository: fixture.repository,
            calendar: fixture.calendarService,
            reminders: fixture.remindersService,
            routines: fixture.routineRepository,
            profileDidChange: { id, visibilityChanged in
                recorder.changeCalls.append(
                    ProfileSettingsChangeCall(id: id, visibilityChanged: visibilityChanged)
                )
            },
            profileWasDeleted: { id in recorder.deletedIDs.append(id) }
        )
    }

    private func profileDraft(
        name: String,
        calendarIDs: Set<String> = [],
        reminderListIDs: Set<String> = [],
        routineIDs: Set<UUID> = [],
        defaultCalendarID: String? = nil,
        defaultReminderListID: String? = nil
    ) -> ProfileDraft {
        ProfileDraft(
            name: name,
            colorHex: "#4868A8",
            symbolName: "person.fill",
            calendarIDs: calendarIDs,
            reminderListIDs: reminderListIDs,
            routineIDs: routineIDs,
            defaultCalendarID: defaultCalendarID,
            defaultReminderListID: defaultReminderListID
        )
    }

    private func calendar(id: String, writable: Bool) -> CalendarDescriptor {
        CalendarDescriptor(
            id: id,
            title: id,
            colorHex: "#4868A8",
            allowsContentModifications: writable
        )
    }

    private func list(id: String, writable: Bool) -> ReminderListDescriptor {
        ReminderListDescriptor(
            id: id,
            title: id,
            colorHex: "#4868A8",
            allowsContentModifications: writable
        )
    }
}

@MainActor
private struct ProfileSettingsFixture {
    let container: ModelContainer
    let repository: SwiftDataProfileRepository
    let settings: AppSettingsStore
    let selection: ProfileSelectionController
    let calendarService: FakeCalendarService
    let remindersService: FakeRemindersService
    let routineRepository: FakeRoutineRepository
    let subject: ProfilesSettingsModel
}

private struct ProfileSettingsChangeCall: Equatable {
    let id: UUID
    let visibilityChanged: Bool
}

@MainActor
private final class ProfileSettingsCallbackRecorder {
    var changeCalls: [ProfileSettingsChangeCall] = []
    var deletedIDs: [UUID] = []
}
