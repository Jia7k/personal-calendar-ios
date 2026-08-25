# Calendar Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add editable Personal, School, Work, and custom calendar profiles; a virtual merged Everything profile; consistent profile filtering and creation defaults across the app; and independently configured profile-aware timetable widgets and Live Activities.

**Architecture:** Persist saved profile memberships in one SwiftData `ProfileRecord`, keep `Everything` derived, and expose one immutable `ProfileScope` per operation. A long-lived selection controller publishes scope revisions to the four main tabs. Provider data remains in EventKit/Reminders, routines remain app-owned, the widget extension reads only a privacy-minimized App Group catalog, and ActivityKit state carries an immutable profile identity.

**Tech Stack:** Swift 6, SwiftUI, Observation, SwiftData, EventKit, WidgetKit, AppIntents, ActivityKit, XCTest, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-25-calendar-profiles-design.md`

## Global Constraints

- Never run the global test suite. Run only the exact `-only-testing` class or method named in each task.
- Keep `project.yml` as the Xcode project source of truth. Run `xcodegen generate`; never hand-edit `project.pbxproj`.
- Use the existing main `ModelContext` for profiles, routines, categories, and backup.
- Treat Calendar and Reminders identifiers as opaque strings. Never parse, normalize, or substitute them.
- Never pass an empty profile ID set to existing EventKit fetch methods; their empty-set behavior means “all sources.”
- Preserve missing external IDs in persisted membership so exact-source reconnection works.
- Clear cross-profile caches before a fetch for a different scope; a failed School refresh must never display Personal data.
- Do not add another create button. Universal Quick Entry remains the only app-wide creation affordance.
- Do not query EventKit from the widget extension. The app is the only catalog writer.
- Do not claim instant widget refresh while the app is suspended or a week-long Live Activity lifecycle.
- Use the existing professional, comfortable light-mode palette; pair profile color with icon and text.
- Commit after every task only after its focused RED/GREEN command and `git diff --check` pass.

## Shared Contracts

Create one widget-safe identity under `PersonalCalendar/ProfileShared` and compile it into both targets:

```swift
enum ProfileIdentity: Hashable, Codable, Sendable {
    case everything
    case saved(UUID)

    var storageKey: String {
        switch self {
        case .everything: "everything"
        case let .saved(id): "saved:\(id.uuidString.lowercased())"
        }
    }

    init?(storageKey: String) {
        if storageKey == "everything" { self = .everything; return }
        guard storageKey.hasPrefix("saved:"),
              let id = UUID(uuidString: String(storageKey.dropFirst(6))) else { return nil }
        self = .saved(id)
    }
}
```

App-only immutable boundaries:

```swift
struct ProfileDraft: Equatable, Sendable {
    var name: String
    var colorHex: String
    var symbolName: String
    var calendarIDs: Set<String>
    var reminderListIDs: Set<String>
    var routineIDs: Set<UUID>
    var defaultCalendarID: String?
    var defaultReminderListID: String?
}

struct ProfileSnapshot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let colorHex: String
    let symbolName: String
    let sortOrder: Int
    let calendarIDs: Set<String>
    let reminderListIDs: Set<String>
    let routineIDs: Set<UUID>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
}

struct ProfileScope: Equatable, Sendable {
    let identity: ProfileIdentity
    let calendarIDs: Set<String>
    let reminderListIDs: Set<String>
    let routineIDs: Set<UUID>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
}

struct ProfileMembership: Equatable, Sendable {
    let calendarIDs: Set<String>
    let reminderListIDs: Set<String>
    let routineIDs: Set<UUID>
}
```

## File Map

New source files:

- `PersonalCalendar/ProfileShared/ProfileIdentity.swift`
- `PersonalCalendar/Profiles/ProfileModels.swift`
- `PersonalCalendar/Persistence/ProfileRecord.swift`
- `PersonalCalendar/Persistence/ProfileRepository.swift`
- `PersonalCalendar/Persistence/SwiftDataProfileRepository.swift`
- `PersonalCalendar/Profiles/ProfileMigrationCoordinator.swift`
- `PersonalCalendar/Profiles/ProfileScopeResolver.swift`
- `PersonalCalendar/Profiles/ProfileSelectionController.swift`
- `PersonalCalendar/Profiles/ProfileSourceFetcher.swift`
- `PersonalCalendar/Persistence/RoutineProfileMutationCoordinator.swift`
- `PersonalCalendar/Features/Profiles/ProfileSelectorToolbar.swift`
- `PersonalCalendar/Features/Settings/ProfilesSettingsModel.swift`
- `PersonalCalendar/Features/Settings/ProfilesSettingsView.swift`
- `PersonalCalendar/Features/Settings/ProfileEditorView.swift`
- `PersonalCalendar/Features/QuickEntry/CreationProfileResolver.swift`
- `PersonalCalendar/TimetableShared/TimetableWidgetCatalog.swift`
- `PersonalCalendar/TimetableShared/TimetableWidgetSelectionResolver.swift`
- `PersonalCalendarWidgets/TimetableProfileIntent.swift`

Focused test files:

- `PersonalCalendarTests/Profiles/ProfileRepositoryTests.swift`
- `PersonalCalendarTests/Profiles/ProfileSettingsStateTests.swift`
- `PersonalCalendarTests/Profiles/ProfileMigrationCoordinatorTests.swift`
- `PersonalCalendarTests/Profiles/ProfileScopeResolverTests.swift`
- `PersonalCalendarTests/Profiles/ProfileSelectionControllerTests.swift`
- `PersonalCalendarTests/Profiles/ProfileEnvironmentTests.swift`
- `PersonalCalendarTests/Profiles/RoutineProfileMutationCoordinatorTests.swift`
- `PersonalCalendarTests/Profiles/ProfileFeatureScopeTests.swift`
- `PersonalCalendarTests/Profiles/ProfileCreationTests.swift`
- `PersonalCalendarTests/Profiles/ProfileSettingsModelTests.swift`
- `PersonalCalendarTests/Profiles/ProfileBackupTests.swift`
- `PersonalCalendarTests/Timetable/TimetableWidgetCatalogTests.swift`
- `PersonalCalendarTests/Timetable/TimetableWidgetSelectionTests.swift`
- `PersonalCalendarTests/Timetable/TimetableProfileActivityTests.swift`
- `PersonalCalendarUITests/ProfileFlowUITests.swift`

---

### Task 1: Add profile identity, persistence, and repository invariants

**Files:**

- Create: `PersonalCalendar/ProfileShared/ProfileIdentity.swift`
- Create: `PersonalCalendar/Profiles/ProfileModels.swift`
- Create: `PersonalCalendar/Persistence/ProfileRecord.swift`
- Create: `PersonalCalendar/Persistence/ProfileRepository.swift`
- Create: `PersonalCalendar/Persistence/SwiftDataProfileRepository.swift`
- Modify: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Modify: `project.yml`
- Test: `PersonalCalendarTests/Profiles/ProfileRepositoryTests.swift`

- [ ] **Step 1: Write the focused repository RED**

Cover create/list/update/reorder, many-to-many membership, missing external ID retention, default-membership validation, and last-profile deletion protection.

```swift
@MainActor
final class ProfileRepositoryTests: XCTestCase {
    func testManyToManyMembershipAndEverythingUnionRemainExact() throws {
        let subject = makeSubject()
        let routine = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let personal = try subject.create(.fixture(
            name: "Personal", calendars: ["home", "shared"],
            lists: ["personal"], routines: [routine],
            defaultCalendar: "home", defaultList: "personal"
        ), id: nil)
        let school = try subject.create(.fixture(
            name: "School", calendars: ["school", "shared"],
            lists: [], routines: [routine],
            defaultCalendar: "school", defaultList: nil
        ), id: nil)

        XCTAssertEqual(try subject.profile(id: personal).calendarIDs, ["home", "shared"])
        XCTAssertEqual(try subject.profile(id: school).routineIDs, [routine])
        XCTAssertEqual(try subject.unionMembership().calendarIDs, ["home", "school", "shared"])
        try subject.delete(id: school)
        XCTAssertThrowsError(try subject.delete(id: personal)) {
            XCTAssertEqual($0 as? ProfileRepositoryError, .cannotDeleteLastProfile)
        }
    }
}
```

- [ ] **Step 2: Generate the project and capture RED**

```sh
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileRepositoryTests
```

Expected RED: missing profile model/repository symbols.

- [ ] **Step 3: Implement the repository**

```swift
@Model
final class ProfileRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var symbolName: String
    var sortOrder: Int
    var calendarIDs: [String]
    var reminderListIDs: [String]
    var routineIDs: [UUID]
    var defaultCalendarID: String?
    var defaultReminderListID: String?
}

@MainActor
protocol ProfileRepository: AnyObject {
    func list() throws -> [ProfileSnapshot]
    func profile(id: UUID) throws -> ProfileSnapshot
    func create(_ draft: ProfileDraft, id: UUID?) throws -> UUID
    func update(id: UUID, draft: ProfileDraft) throws
    func reorder(_ ids: [UUID]) throws
    func delete(id: UUID) throws
    func removeRoutineID(_ id: UUID) throws
    func unionMembership() throws -> ProfileMembership
}
```

Validate all fields before mutation:

- Trim nonblank names and reject case/fold-equivalent duplicates.
- Canonicalize strict `#RRGGBB`.
- Restrict symbols to the app-provided allowlist.
- Reject duplicate membership values.
- Require defaults to belong to their membership set.
- Preserve missing external IDs without consulting EventKit.
- Keep dense ordering and one `context.transaction` plus `context.save()` per write.
- Deny deletion of the last saved profile.

- [ ] **Step 4: Add the schema/shared-target wiring**

Add `ProfileRecord.self` to `PersonalCalendarApp` and all in-memory containers that construct `AppEnvironment`. Add `PersonalCalendar/ProfileShared` to the widget target sources in `project.yml`.

- [ ] **Step 5: Run focused GREEN**

```sh
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileRepositoryTests
git diff --check
```

- [ ] **Step 6: Commit**

```sh
git add project.yml PersonalCalendar/ProfileShared PersonalCalendar/Profiles/ProfileModels.swift PersonalCalendar/Persistence/ProfileRecord.swift PersonalCalendar/Persistence/ProfileRepository.swift PersonalCalendar/Persistence/SwiftDataProfileRepository.swift PersonalCalendar/App/PersonalCalendarApp.swift PersonalCalendarTests/Profiles/ProfileRepositoryTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: add calendar profile persistence"
```

---

### Task 2: Persist active selection and immutable legacy migration input

**Files:**

- Modify: `PersonalCalendar/Settings/AppSettingsStore.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileSettingsStateTests.swift`

- [ ] **Step 1: Write the settings-state RED**

```swift
@MainActor
final class ProfileSettingsStateTests: XCTestCase {
    func testLegacySnapshotDoesNotChangeWhenLegacyReconciliationRuns() {
        let defaults = UserDefaults.ephemeral
        defaults.set(["school", "birthdays"], forKey: "selectedCalendarIDs")
        defaults.set(["assignments"], forKey: "selectedReminderListIDs")
        let subject = AppSettingsStore(defaults: defaults)

        subject.reconcileSources(
            calendarAccess: .granted,
            calendars: [.writable(id: "school")],
            remindersAccess: .granted,
            lists: []
        )

        XCTAssertEqual(subject.legacyProfileSelection.calendarIDs, ["school", "birthdays"])
        XCTAssertEqual(subject.legacyProfileSelection.reminderListIDs, ["assignments"])
    }

    func testTypedProfileSelectionRoundTrips() {
        let defaults = UserDefaults.ephemeral
        let subject = AppSettingsStore(defaults: defaults)
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        subject.setActiveProfile(.saved(id))
        let restored = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.activeProfileIdentity, .saved(id))
        XCTAssertEqual(restored.lastActiveSavedProfileID, id)
    }
}
```

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileSettingsStateTests
```

- [ ] **Step 3: Implement exact persisted state**

```swift
struct LegacyProfileSelectionSnapshot: Equatable, Sendable {
    let calendarIDs: Set<String>
    let reminderListIDs: Set<String>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
    let calendarSelectionWasExplicit: Bool
    let reminderSelectionWasExplicit: Bool
}

enum ProfileMigrationPart: String, CaseIterable {
    case records, calendar, reminders, routines
}
```

Capture `legacyProfileSelection` during initialization before reconciliation. Persist active identity, last saved ID, each migration marker, and per-provider legacy-reconciliation disablement. Add an internal restore method that replaces the captured legacy snapshot and resets migration markers for v1 backup restore. Keep old fields until all feature callers migrate.

- [ ] **Step 4: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileSettingsStateTests
git diff --check
git add PersonalCalendar/Settings/AppSettingsStore.swift PersonalCalendarTests/Profiles/ProfileSettingsStateTests.swift
git commit -m "feat: persist profile selection and migration state"
```

---

### Task 3: Seed and migrate Personal, School, and Work idempotently

**Files:**

- Create: `PersonalCalendar/Profiles/ProfileMigrationCoordinator.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileMigrationCoordinatorTests.swift`

- [ ] **Step 1: Write migration RED**

```swift
@MainActor
final class ProfileMigrationCoordinatorTests: XCTestCase {
    func testDeniedProviderStaysPendingThenMigratesExactlyOnceAfterGrant() throws {
        let fixture = makeFixture(
            calendarAccess: .denied,
            reminderAccess: .granted,
            legacyCalendars: ["school", "birthdays"],
            legacyLists: ["assignments"],
            routines: [Self.readRoutine]
        )

        try fixture.subject.run()
        var personal = try fixture.repository.profile(id: SeedProfile.personalID)
        XCTAssertEqual(personal.calendarIDs, [])
        XCTAssertEqual(personal.reminderListIDs, ["assignments"])
        XCTAssertFalse(fixture.settings.didMigrateProfilePart(.calendar))

        fixture.calendar.accessState = .granted
        fixture.calendar.stubbedCalendars = [.writable(id: "school"), .readOnly(id: "birthdays")]
        try fixture.subject.run()
        try fixture.subject.run()

        personal = try fixture.repository.profile(id: SeedProfile.personalID)
        XCTAssertEqual(personal.calendarIDs, ["school", "birthdays"])
        XCTAssertEqual(try fixture.repository.list().map(\.id), [
            SeedProfile.personalID, SeedProfile.schoolID, SeedProfile.workID
        ])
    }
}
```

Also bind existing-install migration, fresh implicit selection, all three unavailable access states, immediate routine migration, exact default copying, partial-transaction retry, and no overwrite after completion.

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileMigrationCoordinatorTests
```

- [ ] **Step 3: Implement deterministic seeding**

```swift
enum SeedProfile {
    static let personalID = UUID(uuidString: "C0A10000-0000-4000-8000-000000000001")!
    static let schoolID   = UUID(uuidString: "C0A10000-0000-4000-8000-000000000002")!
    static let workID     = UUID(uuidString: "C0A10000-0000-4000-8000-000000000003")!
}

@MainActor
final class ProfileMigrationCoordinator {
    func run() throws
    func resetAndMigrate(legacy: LegacyProfileSelectionSnapshot) throws
}
```

Run order:

1. Insert only missing deterministic seed records.
2. Migrate all nonarchived routines to Personal immediately.
3. Migrate Calendar only after grant, unless a captured explicit nonempty selection is already authoritative.
4. Migrate Reminders under the same rule.
5. Copy defaults only when members and currently writable.
6. Persist each marker only after its own transaction.
7. Make Personal active only on first migration; never override a later choice.

- [ ] **Step 4: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileMigrationCoordinatorTests
git diff --check
git add PersonalCalendar/Profiles/ProfileMigrationCoordinator.swift PersonalCalendarTests/Profiles/ProfileMigrationCoordinatorTests.swift
git commit -m "feat: migrate existing selections into profiles"
```

---

### Task 4: Resolve immutable scopes and deterministic selection revisions

**Files:**

- Create: `PersonalCalendar/Profiles/ProfileScopeResolver.swift`
- Create: `PersonalCalendar/Profiles/ProfileSelectionController.swift`
- Create: `PersonalCalendar/Profiles/ProfileSourceFetcher.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileScopeResolverTests.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileSelectionControllerTests.swift`

- [ ] **Step 1: Write resolver RED**

```swift
func testEverythingIsOnlyTheDeduplicatedAssignedUnion() throws {
    let subject = makeResolver(
        profiles: [
            .fixture(name: "Personal", calendars: ["home", "shared"], lists: ["personal"]),
            .fixture(name: "School", calendars: ["school", "shared"], lists: ["assignments"])
        ],
        calendars: [.writable(id: "home"), .writable(id: "school"), .writable(id: "shared"), .readOnly(id: "birthdays")],
        lists: [.writable(id: "personal"), .writable(id: "assignments")]
    )
    let scope = try subject.resolve(.everything)
    XCTAssertEqual(scope.calendarIDs, ["home", "school", "shared"])
    XCTAssertFalse(scope.calendarIDs.contains("birthdays"))
    XCTAssertNil(scope.defaultCalendarID)
    XCTAssertNil(scope.defaultReminderListID)
}

func testEmptyProfileDoesNotCallProviders() async throws {
    let calendar = RecordingCalendarService()
    let reminders = RecordingRemindersService()
    let result = try await ProfileSourceFetcher(calendar: calendar, reminders: reminders)
        .fetch(scope: .emptySaved, interval: Self.week)
    XCTAssertEqual(result.events, [])
    XCTAssertEqual(result.reminders, [])
    XCTAssertEqual(calendar.fetchCalls, 0)
    XCTAssertEqual(reminders.fetchCalls, 0)
}
```

- [ ] **Step 2: Write controller RED**

```swift
func testMembershipChangeOnlyInvalidatesVisibleScope() throws {
    let subject = makeController(active: .saved(Self.personalID))
    let initial = subject.scopeRevision
    subject.profileDidChange(id: Self.schoolID, visibilityChanged: true)
    XCTAssertEqual(subject.scopeRevision, initial)
    subject.profileDidChange(id: Self.personalID, visibilityChanged: true)
    XCTAssertEqual(subject.scopeRevision, initial + 1)
    subject.select(.everything)
    let everythingRevision = subject.scopeRevision
    subject.profileDidChange(id: Self.schoolID, visibilityChanged: true)
    XCTAssertEqual(subject.scopeRevision, everythingRevision + 1)
}
```

- [ ] **Step 3: Capture both REDs**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileScopeResolverTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileSelectionControllerTests
```

- [ ] **Step 4: Implement**

Resolver rules:

- Intersect external membership with currently available descriptors only for the fetch scope.
- Preserve missing IDs in `ProfileSnapshot`.
- Return an empty provider scope under denied/restricted/not-determined access.
- Validate saved defaults against stored membership, current presence, and writability.
- Return union sets and nil defaults for Everything.

Controller contract:

```swift
@MainActor @Observable
final class ProfileSelectionController {
    private(set) var profiles: [ProfileSnapshot]
    private(set) var activeIdentity: ProfileIdentity
    private(set) var scopeRevision = 0

    func reloadProfiles() throws
    func select(_ identity: ProfileIdentity) throws
    func profileDidChange(id: UUID, visibilityChanged: Bool)
    func profileWasDeleted(id: UUID)
}
```

Persist only valid identities. A missing/deleted active saved profile falls back to Everything, never to another saved profile.

- [ ] **Step 5: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileScopeResolverTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileSelectionControllerTests
git diff --check
git add PersonalCalendar/Profiles/ProfileScopeResolver.swift PersonalCalendar/Profiles/ProfileSelectionController.swift PersonalCalendar/Profiles/ProfileSourceFetcher.swift PersonalCalendarTests/Profiles/ProfileScopeResolverTests.swift PersonalCalendarTests/Profiles/ProfileSelectionControllerTests.swift
git commit -m "feat: resolve and select calendar profile scopes"
```
+---

### Task 5: Compose profiles into the environment and refresh pipeline

**Files:**

- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/Refresh/AppRefreshCoordinator.swift`
- Modify: `PersonalCalendar/App/RootLifecycleController.swift`
- Modify: `PersonalCalendar/App/DemoEnvironment.swift`
- Modify: `PersonalCalendarTests/Support/Fakes.swift`
- Modify: `PersonalCalendarTests/App/DemoEnvironmentTests.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileEnvironmentTests.swift`

- [ ] **Step 1: Write the focused composition/ordering RED**

```swift
@MainActor
func testRefreshMigratesBeforeLegacyReconciliationAndPublishesOneScopeRevision() async throws {
    var operations: [String] = []
    let fixture = makeEnvironmentFixture(
        refreshPermissions: { operations.append("permissions") },
        migrateProfiles: { operations.append("profiles") },
        reconcileLegacy: { operations.append("legacy") },
        refreshAgenda: { operations.append("agenda") }
    )
    let before = fixture.selection.scopeRevision

    await fixture.refresh.refreshNow(reason: .foreground)

    XCTAssertEqual(operations, ["permissions", "profiles", "legacy", "agenda"])
    XCTAssertEqual(fixture.selection.scopeRevision, before + 1)
    XCTAssertTrue(fixture.environment.profiles === fixture.repository)
}
```

Also assert demo construction exposes exactly Personal/School/Work once and shares the same repository/context with routine mutation and backup.

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileEnvironmentTests
```

- [ ] **Step 3: Wire long-lived dependencies**

Add to `AppEnvironment`:

```swift
let profiles: any ProfileRepository
let profileScopes: ProfileScopeResolver
let profileSelection: ProfileSelectionController
let profileMigration: ProfileMigrationCoordinator
let routineProfileMutations: any RoutineProfileMutating
```

Construct each once from `container.mainContext` in live and demo factories. The refresh order is:

1. refresh permissions/descriptors
2. run deferred profile migration
3. skip legacy reconciliation for already migrated providers
4. reload selection snapshots
5. capture the active scope
6. await registered agenda refreshes
7. rebuild profile-aware timetable data
8. reschedule notifications only when Everything membership changed

Use an explicit composite input rather than adding revision integers:

```swift
struct AppContentRevision: Hashable {
    let lifecycle: Int
    let profileScope: Int
}
```

- [ ] **Step 4: Make notifications resolve Everything**

Update `makeNotificationRescheduler` to resolve `.everything`, short-circuit empty calendar/list sets, and filter routines by `scope.routineIDs`. Merely selecting a different visible profile does not reschedule notifications.

- [ ] **Step 5: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileEnvironmentTests
git diff --check
git add PersonalCalendar/App/AppEnvironment.swift PersonalCalendar/App/DemoEnvironment.swift PersonalCalendar/Refresh/AppRefreshCoordinator.swift PersonalCalendar/App/RootLifecycleController.swift PersonalCalendarTests/Support/Fakes.swift PersonalCalendarTests/App/DemoEnvironmentTests.swift PersonalCalendarTests/Profiles/ProfileEnvironmentTests.swift
git commit -m "feat: compose profile services and refresh lifecycle"
```

---

### Task 6: Make routine creation and profile membership atomic

**Files:**

- Create: `PersonalCalendar/Persistence/RoutineProfileMutationCoordinator.swift`
- Modify: `PersonalCalendar/Persistence/SwiftDataRoutineRepository.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesViewModel.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/App/DemoEnvironment.swift`
- Test: `PersonalCalendarTests/Profiles/RoutineProfileMutationCoordinatorTests.swift`

- [ ] **Step 1: Write atomic mutation RED**

```swift
@MainActor
final class RoutineProfileMutationCoordinatorTests: XCTestCase {
    func testCreateAndDeleteUpdateRoutineAndEveryMembershipInOneCommit() throws {
        let fixture = makeFixture()
        let routineID = try fixture.subject.create(
            draft: .readEveryNight,
            profileID: Self.schoolID
        )
        XCTAssertNotNil(try fixture.context.fetch(
            FetchDescriptor<RoutineRecord>(
                predicate: #Predicate { $0.id == routineID }
            )
        ).first)
        XCTAssertTrue(try fixture.profiles.profile(id: Self.schoolID).routineIDs.contains(routineID))

        try fixture.profiles.update(
            id: Self.personalID,
            draft: try fixture.profiles.profile(id: Self.personalID)
                .draft(addingRoutine: routineID)
        )
        try fixture.subject.delete(id: routineID)

        XCTAssertFalse(try fixture.profiles.list().contains {
            $0.routineIDs.contains(routineID)
        })
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<RoutineCompletionRecord>())
            .allSatisfy { $0.routineID != routineID })
    }
}
```

Include an injected-save-failure case proving neither side publishes a partial mutation.

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/RoutineProfileMutationCoordinatorTests
```

- [ ] **Step 3: Extract no-save routine primitives**

Keep public `SwiftDataRoutineRepository` behavior unchanged, but extract internal helpers that normalize/insert/delete records without saving. The coordinator must not call two saving repositories sequentially.

```swift
@MainActor
protocol RoutineProfileMutating {
    func create(draft: RoutineDraft, profileID: UUID) throws -> UUID
    func delete(id: UUID) throws
}

@MainActor
final class RoutineProfileMutationCoordinator: RoutineProfileMutating {
    func create(draft: RoutineDraft, profileID: UUID) throws -> UUID
    func delete(id: UUID) throws
}
```

Each operation uses the shared `ModelContext`, one transaction, and one save. Delete removes completions and the routine UUID from every saved profile.

- [ ] **Step 4: Route RoutinesViewModel create/delete**

Inject both `RoutineRepository` (read/update/pause/archive/completion) and `RoutineProfileMutating` (create/delete). Creation requires a selected saved profile ID; deletion prunes all profiles. Demo uses a small in-memory protocol adapter that preserves its fail-once behavior.

- [ ] **Step 5: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/RoutineProfileMutationCoordinatorTests
git diff --check
git add PersonalCalendar/Persistence/SwiftDataRoutineRepository.swift PersonalCalendar/Persistence/RoutineProfileMutationCoordinator.swift PersonalCalendar/Features/Routines/RoutinesViewModel.swift PersonalCalendar/App/AppEnvironment.swift PersonalCalendar/App/DemoEnvironment.swift PersonalCalendarTests/Profiles/RoutineProfileMutationCoordinatorTests.swift
git commit -m "feat: make routine profile membership atomic"
```

---

### Task 7: Apply one captured profile scope to all four feature models

**Files:**

- Modify: `PersonalCalendar/Features/Calendar/CalendarViewModel.swift`
- Modify: `PersonalCalendar/Features/Today/TodayViewModel.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksViewModel.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesViewModel.swift`
- Modify: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Modify: `PersonalCalendar/Features/Today/TodayView.swift`
- Modify: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesView.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileFeatureScopeTests.swift`

- [ ] **Step 1: Write the cross-feature happy-path and empty-scope RED**

```swift
@MainActor
func testSwitchingToSchoolRefreshesEveryFeatureWithTheSameScopeWithoutWrites() async throws {
    let school = ProfileScope(
        identity: .saved(Self.schoolID),
        calendarIDs: ["school-calendar"],
        reminderListIDs: ["school-list"],
        routineIDs: [Self.studyRoutine],
        defaultCalendarID: "school-calendar",
        defaultReminderListID: "school-list"
    )
    let fixture = makeFeatureFixture(scope: school)

    await fixture.calendar.load()
    await fixture.today.load()
    await fixture.tasks.load()
    fixture.routines.reload()

    XCTAssertEqual(fixture.calendarService.lastFetchIDs, ["school-calendar"])
    XCTAssertEqual(fixture.todayCalendar.lastFetchIDs, ["school-calendar"])
    XCTAssertEqual(fixture.reminders.allFetchIDs, [["school-list"], ["school-list"]])
    XCTAssertEqual(fixture.routines.active.map(\.id), [Self.studyRoutine])
    XCTAssertEqual(fixture.totalProviderWrites, 0)
}

@MainActor
func testEmptySchoolProfileShowsNoDataAndMakesNoFetchCalls() async {
    let fixture = makeFeatureFixture(scope: .emptySaved)
    await fixture.loadAll()
    XCTAssertEqual(fixture.visibleItemCount, 0)
    XCTAssertEqual(fixture.totalExternalFetches, 0)
}
```

Add a suspended cross-profile failure case: Personal cache exists, scope changes to School, School fetch fails, and no Personal item remains visible.

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileFeatureScopeTests
```

- [ ] **Step 3: Inject a scope provider**

Each model receives:

```swift
private let currentScope: @MainActor () throws -> ProfileScope
```

At the beginning of each load, capture one scope and use that exact value for every provider and routine operation in that load. Compatibility initializers may construct a legacy scope for unrelated old unit fixtures, but all production initializers must pass the profile resolver.

Rules:

- Empty calendar/list set: publish empty for that provider without calling the service.
- Calendar/Today: filter routines before completion-history reads.
- Tasks: publish and mutation recovery use the current scope's list IDs.
- Today completion/undo: re-resolve scope before writing.
- Track `cachedScopeIdentity`; clear caches when it changes, then preserve caches only on same-scope refresh failure.
- Filter by exact opaque IDs even if a fake returns extra items.
- Add `isProfileEmpty`/profile-specific empty-state data without falling back to all sources.

- [ ] **Step 4: Drive host reloads with the composite revision**

Pass `AppContentRevision(lifecycle: lifecycle.revision, profileScope: selection.scopeRevision)` into all four views. Keep host-owned refresh after writes.

- [ ] **Step 5: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileFeatureScopeTests
git diff --check
git add PersonalCalendar/App/RootTabView.swift PersonalCalendar/Features/Calendar/CalendarViewModel.swift PersonalCalendar/Features/Calendar/CalendarHomeView.swift PersonalCalendar/Features/Today/TodayViewModel.swift PersonalCalendar/Features/Today/TodayView.swift PersonalCalendar/Features/Tasks/TasksViewModel.swift PersonalCalendar/Features/Tasks/TasksView.swift PersonalCalendar/Features/Routines/RoutinesViewModel.swift PersonalCalendar/Features/Routines/RoutinesView.swift PersonalCalendarTests/Profiles/ProfileFeatureScopeTests.swift
git commit -m "feat: filter every main feature by active profile"
```

---

### Task 8: Add the shared toolbar selector and profile management Settings UI

**Files:**

- Create: `PersonalCalendar/Features/Profiles/ProfileSelectorToolbar.swift`
- Create: `PersonalCalendar/Features/Settings/ProfilesSettingsModel.swift`
- Create: `PersonalCalendar/Features/Settings/ProfilesSettingsView.swift`
- Create: `PersonalCalendar/Features/Settings/ProfileEditorView.swift`
- Modify: all four main tab views
- Modify: `PersonalCalendar/Features/Settings/SettingsView.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileSettingsModelTests.swift`

- [ ] **Step 1: Write the Settings model RED**

```swift
@MainActor
func testEditorPreservesMissingSourcesButNeverUsesReadOnlyDefault() throws {
    let missing = "google-school-offline"
    let subject = makeModel(
        profile: .fixture(
            calendars: [missing, "public-holidays"],
            defaultCalendar: "public-holidays"
        ),
        calendars: [.readOnly(id: "public-holidays"), .writable(id: "work")]
    )

    XCTAssertEqual(subject.waitingCalendarCount, 1)
    XCTAssertEqual(subject.draft.calendarIDs, [missing, "public-holidays"])
    XCTAssertNil(subject.validatedDefaultCalendarID)
    XCTAssertEqual(subject.defaultCalendarChoices.map(\.id), ["work"])
}
```

Also cover create/update/reorder, last-profile delete rejection, active deletion fallback, and one membership callback with `visibilityChanged == true`.

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileSettingsModelTests
```

- [ ] **Step 3: Implement reusable toolbar selector**

`ProfileSelectorToolbar` is a 44-point `Menu` with Everything first, then saved profiles in order. Label: icon plus current name. Accessibility label/value: `Profile` / current name. Add it inside each tab's own `NavigationStack` at `.topBarTrailing`.

- [ ] **Step 4: Implement Settings CRUD**

`ProfilesSettingsView` contains:

- immutable Everything explanation
- ordered saved rows
- create/reorder actions
- delete confirmation that states provider content is untouched
- disabled final-profile deletion

`ProfileEditorView` contains:

- name, bounded symbol picker, approved light-mode color palette
- available Calendar and Reminder membership
- all routines, including archived
- writable defaults constrained to checked membership
- neutral `Waiting to reconnect` rows that do not reveal opaque IDs

After profile persistence succeeds, call the selection controller with whether visibility changed. Rebuild widgets for any membership change, refresh visible features only when the active scope is affected.

- [ ] **Step 5: Replace legacy Settings controls**

After migration completion, show `Profiles` instead of global visible-calendar/list/default controls. Keep legacy storage internally for backup v1 and migration only.

- [ ] **Step 6: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileSettingsModelTests
git diff --check
git add PersonalCalendar/Features/Profiles/ProfileSelectorToolbar.swift PersonalCalendar/Features/Settings/ProfilesSettingsModel.swift PersonalCalendar/Features/Settings/ProfilesSettingsView.swift PersonalCalendar/Features/Settings/ProfileEditorView.swift PersonalCalendar/Features/Settings/SettingsView.swift PersonalCalendar/Features/Calendar/CalendarHomeView.swift PersonalCalendar/Features/Today/TodayView.swift PersonalCalendar/Features/Tasks/TasksView.swift PersonalCalendar/Features/Routines/RoutinesView.swift PersonalCalendarTests/Profiles/ProfileSettingsModelTests.swift
git commit -m "feat: add profile selector and management UI"
```

---

### Task 9: Route creation through a chosen saved profile

**Files:**

- Create: `PersonalCalendar/Features/QuickEntry/CreationProfileResolver.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `PersonalCalendar/Features/QuickEntry/QuickEntryViewModel.swift`
- Modify: `PersonalCalendar/Features/QuickEntry/QuickEntrySheet.swift`
- Modify: `PersonalCalendar/QuickEntry/SaveRouter.swift`
- Modify: `PersonalCalendar/Features/EventEditor/EventEditorViewModel.swift`
- Modify: `PersonalCalendar/Features/Tasks/TaskEditorViewModel.swift`
- Modify: `PersonalCalendar/Features/Routines/RoutinesViewModel.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileCreationTests.swift`

- [ ] **Step 1: Write creation routing RED**

```swift
@MainActor
func testEverythingRequiresSavedProfileThenUsesThatProfilesExactDefaults() throws {
    let resolver = CreationProfileResolver(
        profiles: [.personal(defaultCalendar: "home"), .school(defaultCalendar: "school")],
        scopeResolver: scopes
    )
    XCTAssertEqual(try resolver.resolve(active: .everything), .chooseSavedProfile([
        Self.personalID, Self.schoolID
    ]))

    let context = try resolver.resolve(chosen: Self.schoolID)
    XCTAssertEqual(context.profileID, Self.schoolID)
    XCTAssertEqual(context.defaultCalendarID, "school")
    XCTAssertTrue(context.requiresExplicitCalendarDestination == false)
}

@MainActor
func testMissingProfileDefaultRequiresExplicitDestinationAndNeverWritesNil() async {
    let fixture = makeCreationFixture(defaultCalendar: nil)
    fixture.model.parse()
    await fixture.model.confirmSave()
    XCTAssertEqual(fixture.saver.received, [])
    XCTAssertEqual(fixture.model.errorMessage, "Choose a calendar before saving.")
}
```

Also cover read-only defaults, explicit override outside membership, routine membership assignment, and event/task edit preserving current sources.

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileCreationTests
```

- [ ] **Step 3: Add the creation context**

```swift
struct CreationProfileContext: Equatable, Sendable {
    let profileID: UUID
    let profileName: String
    let memberCalendarIDs: Set<String>
    let memberReminderListIDs: Set<String>
    let defaultCalendarID: String?
    let defaultReminderListID: String?
    let requiresExplicitCalendarDestination: Bool
    let requiresExplicitReminderDestination: Bool
}
```

From a saved active profile, build this immediately. From Everything, present a saved-profile chooser in Root before constructing Quick Entry. `lastActiveSavedProfileID` may be highlighted but must not be auto-selected. Store the chosen profile ID on the Quick Entry session so foreground permission refresh does not switch its destination context.

- [ ] **Step 4: Make Quick Entry options profile-aware**

Continue listing all current writable destinations for explicit override, but seed only the chosen profile's validated defaults and show an “Outside School” hint for destinations outside membership. When a required default is absent/read-only:

- disable/remove System Default
- require explicit destination locally
- make the router reject nil as a second authority guard

Event/task override does not change profile membership. Routine create goes through `RoutineProfileMutating.create(draft:profileID:)`.

- [ ] **Step 5: Update future create factories**

Add the same optional `CreationProfileContext` to `EventEditorViewModel.create` and `TaskEditorViewModel.creating`. Leave edit factories unchanged so existing items preserve their current sources.

- [ ] **Step 6: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileCreationTests
git diff --check
git add PersonalCalendar/Features/QuickEntry/CreationProfileResolver.swift PersonalCalendar/App/RootTabView.swift PersonalCalendar/Features/QuickEntry/QuickEntryViewModel.swift PersonalCalendar/Features/QuickEntry/QuickEntrySheet.swift PersonalCalendar/QuickEntry/SaveRouter.swift PersonalCalendar/Features/EventEditor/EventEditorViewModel.swift PersonalCalendar/Features/Tasks/TaskEditorViewModel.swift PersonalCalendar/Features/Routines/RoutinesViewModel.swift PersonalCalendarTests/Profiles/ProfileCreationTests.swift
git commit -m "feat: route creation through saved profiles"
```
+---

### Task 10: Export backup v2 and migrate v1 restores into profiles

**Files:**

- Modify: `PersonalCalendar/Backup/BackupEnvelope.swift`
- Modify: `PersonalCalendar/Backup/BackupService.swift`
- Modify: `PersonalCalendar/Features/Settings/BackupSettingsView.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Test: `PersonalCalendarTests/Profiles/ProfileBackupTests.swift`

- [ ] **Step 1: Write v2 round-trip and v1 migration RED**

```swift
@MainActor
func testV2RoundTripPreservesProfilesAndSelection() throws {
    let fixture = makeFixture()
    try fixture.seedProfiles()
    fixture.settings.setActiveProfile(.saved(Self.schoolID))

    let data = try fixture.backup.exportData()
    try fixture.clearAppOwnedData()
    try fixture.backup.restore(data: data)

    XCTAssertEqual(try fixture.profiles.list().map(\.name), ["Personal", "School", "Work"])
    XCTAssertEqual(try fixture.profiles.profile(id: Self.schoolID).calendarIDs, ["google-school"])
    XCTAssertEqual(fixture.settings.activeProfileIdentity, .saved(Self.schoolID))
}

@MainActor
func testV1RestoreUsesDecodedLegacySelectionAsMigrationInput() throws {
    let fixture = makeFixture(existingActive: .everything)
    try fixture.backup.restore(data: makeV1Backup(
        selectedCalendars: ["legacy-school"],
        selectedLists: ["legacy-assignments"]
    ))
    let personal = try fixture.profiles.profile(id: SeedProfile.personalID)
    XCTAssertEqual(personal.calendarIDs, ["legacy-school"])
    XCTAssertEqual(personal.reminderListIDs, ["legacy-assignments"])
}
```

Also reject duplicate/invalid profiles, missing routine membership references, invalid defaults, and zero saved profiles before mutation.

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileBackupTests
```

- [ ] **Step 3: Split explicit v1/v2 DTOs**

Keep the exact existing shape as `BackupEnvelopeV1` and `SettingsBackupV1`. Add:

```swift
private struct BackupVersionHeader: Decodable { let version: Int }

struct BackupEnvelopeV2: Codable, Equatable, Sendable {
    let version: Int
    let exportedAt: Date
    let routines: [RoutineBackup]
    let completions: [CompletionBackup]
    let categories: [CategorySnapshot]
    let categoryLinks: [CategoryLinkBackup]
    let profiles: [ProfileSnapshot]
    let settings: SettingsBackupV2
}
```

Decode only the header first, then dispatch. Export v2 only. Validate every v2 field before deleting anything.

- [ ] **Step 4: Restore atomically and migrate v1 explicitly**

V2 transaction replaces profiles alongside existing app-owned records, saves once, then applies settings. V1 restore:

1. validate and restore v1 app-owned data
2. delete existing profiles
3. apply decoded legacy settings and replace the captured migration snapshot
4. reset profile migration markers
5. invoke `ProfileMigrationCoordinator.resetAndMigrate(legacy:)`
6. fall back to Everything if restored active identity is absent
7. rebuild the widget catalog after successful restore

`Everything` and derived widget files are never encoded.

- [ ] **Step 5: Update backup summary/UI**

Add a profile count to `BackupSummary` and destructive replacement copy. Keep the existing local file importer/exporter behavior.

- [ ] **Step 6: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileBackupTests
git diff --check
git add PersonalCalendar/Backup/BackupEnvelope.swift PersonalCalendar/Backup/BackupService.swift PersonalCalendar/Features/Settings/BackupSettingsView.swift PersonalCalendar/App/AppEnvironment.swift PersonalCalendarTests/Profiles/ProfileBackupTests.swift
git commit -m "feat: back up and migrate calendar profiles"
```

---

### Task 11: Replace the single timetable file with a profile catalog

**Files:**

- Create: `PersonalCalendar/TimetableShared/TimetableWidgetCatalog.swift`
- Create: `PersonalCalendar/TimetableShared/TimetableWidgetSelectionResolver.swift`
- Modify: `PersonalCalendar/TimetableShared/TimetableSnapshot.swift`
- Modify: `PersonalCalendar/TimetableShared/TimetableSnapshotStore.swift`
- Modify: `PersonalCalendar/Timetable/TimetableSnapshotBuilder.swift`
- Modify: `PersonalCalendar/Timetable/TimetableSnapshotCoordinator.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Test: `PersonalCalendarTests/Timetable/TimetableWidgetCatalogTests.swift`
- Test: `PersonalCalendarTests/Timetable/TimetableWidgetSelectionTests.swift`

- [ ] **Step 1: Write catalog/store RED**

```swift
func testCatalogRoundTripKeepsIndependentProfileSnapshotsAndEverythingUnion() throws {
    let file = temporaryURL()
    let store = TimetableWidgetCatalogStore(fileURL: file)
    let catalog = TimetableWidgetCatalogV1.fixture(
        profiles: [
            .profile(.saved(Self.schoolID), name: "School", events: [.math, .shared]),
            .profile(.saved(Self.personalID), name: "Personal", events: [.dentist, .shared])
        ],
        everything: [.math, .dentist, .shared]
    )
    try store.write(catalog)
    XCTAssertEqual(try store.read(), catalog)
    XCTAssertEqual(try store.read().snapshot(for: .saved(Self.schoolID))?.entries, [.math, .shared])
    XCTAssertEqual(try store.read().snapshot(for: .everything)?.entries, [.math, .dentist, .shared])
}
```

- [ ] **Step 2: Write pure selection RED**

```swift
func testNilAndDeletedWidgetSelectionsNeverFallBack() {
    let catalog = TimetableWidgetCatalogV1.fixture(profiles: [.school], everything: [.math])
    XCTAssertEqual(TimetableWidgetSelectionResolver.resolve(nil, in: catalog), .chooseProfile)
    XCTAssertEqual(
        TimetableWidgetSelectionResolver.resolve(.saved(Self.deletedID), in: catalog),
        .profileDeleted
    )
    XCTAssertEqual(
        TimetableWidgetSelectionResolver.resolve(.saved(Self.schoolID), in: catalog),
        .ready(.schoolSnapshot)
    )
}
```

- [ ] **Step 3: Capture both REDs**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableWidgetCatalogTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableWidgetSelectionTests
```

- [ ] **Step 4: Implement the shared DTO/store**

```swift
enum TimetableProfileAvailability: String, Codable, Hashable, Sendable {
    case ready
    case calendarAccessRequired
    case emptyProfile
    case noClasses
}

struct TimetableWidgetProfile: Codable, Hashable, Identifiable, Sendable {
    let id: ProfileIdentity
    let name: String
    let colorHex: String
    let symbolName: String
    let snapshot: TimetableSnapshotV1
}

struct TimetableWidgetCatalogV1: Codable, Hashable, Sendable {
    static let currentVersion = 1
    let version: Int
    let generatedAt: Date
    let profiles: [TimetableWidgetProfile]
}
```

Store atomically as `timetable-catalog-v1.json`; add explicit `delete()` for fail-closed transitions. Keep a temporary decoder for the old single file only if needed to render “Choose a profile”; never infer a profile from it.

- [ ] **Step 5: Build per-profile snapshots without leaking EventKit IDs**

Fetch the union of current assigned Calendar IDs once. If the union is empty, do not call EventKit. Partition fetched events by saved-profile calendar membership and derive Everything by display identity. Filter all-day events as today. Bound each snapshot to the existing entry limit and string lengths.

Replace `TimetableEntry.id = event.id` with a synthetic occurrence ID built after deterministic sorting, for example `occurrence:<start epoch milliseconds>:<ordinal>`. Do not serialize calendar ID, mutation ID, notes, URLs, alarms, or recurrence.

- [ ] **Step 6: Implement failure policy**

- Ordinary fetch/write failure: retain previous catalog and report an app warning.
- Permission loss, profile deletion, or membership removal: write a reduced/tombstone catalog.
- If fail-closed write fails: delete catalog, call `WidgetCenter.reloadTimelines`, and end affected activities.
- Membership change rebuilds affected saved profile plus Everything.
- App-active profile selection alone does not rewrite pinned widget selection.

- [ ] **Step 7: Run focused GREEN and commit**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableWidgetCatalogTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableWidgetSelectionTests
git diff --check
git add PersonalCalendar/TimetableShared/TimetableWidgetCatalog.swift PersonalCalendar/TimetableShared/TimetableWidgetSelectionResolver.swift PersonalCalendar/TimetableShared/TimetableSnapshot.swift PersonalCalendar/TimetableShared/TimetableSnapshotStore.swift PersonalCalendar/Timetable/TimetableSnapshotBuilder.swift PersonalCalendar/Timetable/TimetableSnapshotCoordinator.swift PersonalCalendar/App/AppEnvironment.swift PersonalCalendarTests/Timetable/TimetableWidgetCatalogTests.swift PersonalCalendarTests/Timetable/TimetableWidgetSelectionTests.swift
git commit -m "feat: publish profile-aware timetable catalog"
```

---

### Task 12: Configure each timetable widget with an independent profile

**Files:**

- Create: `PersonalCalendarWidgets/TimetableProfileIntent.swift`
- Modify: `PersonalCalendarWidgets/TimetableWidgetProvider.swift`
- Modify: `PersonalCalendarWidgets/NextClassWidget.swift`
- Modify: `PersonalCalendarWidgets/WeekTimetableWidget.swift`
- Modify: `PersonalCalendarWidgets/PersonalCalendarWidgetsBundle.swift`
- Modify: `project.yml`
- Test: `PersonalCalendarTests/Timetable/TimetableWidgetSelectionTests.swift`

- [ ] **Step 1: Extend the pure resolver test for independent instances**

```swift
func testTwoWidgetConfigurationsResolveDifferentProfilesFromOneCatalog() {
    let catalog = TimetableWidgetCatalogV1.fixture(
        profiles: [.school, .personal],
        everything: [.math, .dentist]
    )
    XCTAssertEqual(
        TimetableWidgetSelectionResolver.resolve(.saved(Self.schoolID), in: catalog),
        .ready(.schoolSnapshot)
    )
    XCTAssertEqual(
        TimetableWidgetSelectionResolver.resolve(.saved(Self.personalID), in: catalog),
        .ready(.personalSnapshot)
    )
}
```

Run only the existing focused class:

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableWidgetSelectionTests
```

- [ ] **Step 2: Add AppIntent entities**

```swift
struct TimetableProfileEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profile")
    static var defaultQuery = TimetableProfileEntityQuery()
    let id: String
    let name: String
    let symbolName: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
    }
}

struct TimetableWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Timetable"
    @Parameter(title: "Profile") var profile: TimetableProfileEntity?
}
```

The query reads only widget-safe descriptors from the App Group catalog and includes Everything. It returns no synthetic fallback if the catalog is missing.

- [ ] **Step 3: Convert both widgets to AppIntentConfiguration**

Implement `AppIntentTimelineProvider`. Resolve `configuration.profile?.id` through `ProfileIdentity(storageKey:)` and the pure selection resolver.

Render distinct states:

- nil selection: `Choose a profile`
- deleted identity: `Choose another profile`
- access unavailable: provider access explanation
- empty profile: `No calendars in this profile`
- ready with no events: `No classes this week`
- ready with events: existing Next Class or Week UI, labelled with chosen profile

Keep widget kinds stable. Existing static instances receive nil and must be configured once.

- [ ] **Step 4: Build only the widget extension**

```sh
xcodegen generate
xcodebuild build -project PersonalCalendar.xcodeproj -target PersonalCalendarWidgets -destination 'generic/platform=iOS Simulator'
git diff --check
```

- [ ] **Step 5: Commit**

```sh
git add project.yml PersonalCalendarWidgets PersonalCalendarTests/Timetable/TimetableWidgetSelectionTests.swift PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: configure timetable widgets per profile"
```

---

### Task 13: Bind Live Activities to immutable profile identity

**Files:**

- Modify: `PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift`
- Modify: `PersonalCalendar/Timetable/TimetableActivityDriver.swift`
- Modify: `PersonalCalendar/Timetable/TimetableLiveActivityCoordinator.swift`
- Modify: `PersonalCalendar/Features/Settings/TimetableSettingsView.swift`
- Modify: `PersonalCalendarWidgets/TimetableLiveActivity.swift`
- Modify: `PersonalCalendarWidgets/TimeRailsView.swift`
- Test: `PersonalCalendarTests/Timetable/TimetableProfileActivityTests.swift`

- [ ] **Step 1: Write activity reconciliation RED**

```swift
@MainActor
func testReconcileUpdatesEachActivityFromItsOwnProfileAndEndsDeletedProfile() async {
    let driver = RecordingActivityDriver(activities: [
        .init(id: "school-live", profile: .saved(Self.schoolID)),
        .init(id: "deleted-live", profile: .saved(Self.deletedID))
    ])
    let subject = TimetableLiveActivityCoordinator(driver: driver, calendar: Self.calendar)
    await subject.reconcile(catalog: .fixture(profiles: [.school], everything: [.math]))

    XCTAssertEqual(driver.updates.map(\.id), ["school-live"])
    XCTAssertEqual(driver.updates.first?.state.snapshot.entries, [.math])
    XCTAssertEqual(driver.ends, ["deleted-live"])
}
```

Also cover start with explicit profile, switching chosen profile causing end+request, and permission tombstone ending affected activity.

- [ ] **Step 2: Capture RED**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableProfileActivityTests
```

- [ ] **Step 3: Add profile identity to immutable attributes**

```swift
struct TimetableActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let snapshot: TimetableSnapshotV1
    }

    let profileIdentity: ProfileIdentity
    let profileName: String
    let weekStart: Date
    let timeZoneIdentifier: String
}
```

Change the driver to return descriptors, not IDs:

```swift
struct TimetableActivityDescriptor: Equatable, Sendable {
    let id: String
    let attributes: TimetableActivityAttributes
}
```

Activity attributes cannot be updated. A changed profile/week/time zone requires ending the old activity and requesting a new one. Reconciliation updates only when immutable attributes still match.

- [ ] **Step 4: Add the in-app profile picker**

`TimetableSettingsView` lists Everything and saved profiles, shows the selected profile's next-class/week summary, and starts/stops the activity. Remove hardcoded School copy. A deleted backing profile ends on next app runtime.

- [ ] **Step 5: Run focused GREEN and extension build**

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableProfileActivityTests
xcodebuild build -project PersonalCalendar.xcodeproj -target PersonalCalendarWidgets -destination 'generic/platform=iOS Simulator'
git diff --check
```

- [ ] **Step 6: Commit**

```sh
git add PersonalCalendar/TimetableShared/TimetableActivityAttributes.swift PersonalCalendar/Timetable/TimetableActivityDriver.swift PersonalCalendar/Timetable/TimetableLiveActivityCoordinator.swift PersonalCalendar/Features/Settings/TimetableSettingsView.swift PersonalCalendarWidgets/TimetableLiveActivity.swift PersonalCalendarWidgets/TimeRailsView.swift PersonalCalendarTests/Timetable/TimetableProfileActivityTests.swift
git commit -m "feat: bind timetable live activities to profiles"
```

---

### Task 14: Add the demo/profile happy path, update docs, and perform bounded release validation

**Files:**

- Modify: `PersonalCalendar/App/DemoEnvironment.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `README.md`
- Modify: existing stale UI tests only where profile UI intentionally replaces legacy controls
- Test: `PersonalCalendarUITests/ProfileFlowUITests.swift`

- [ ] **Step 1: Add deterministic demo fixtures**

Seed:

- Personal: Home calendar, Personal reminder list, one personal routine
- School: dedicated Google School calendar, Assignments list, one study routine
- Work: Work calendar/list
- unassigned: Birthdays calendar
- shared event/routine membership where needed to verify Everything deduplication

Add launch arguments that keep these IDs deterministic; do not infer membership from titles.

- [ ] **Step 2: Write one end-to-end focused UI happy path**

```swift
func testSchoolProfileFiltersAllTabsWhileEverythingExcludesUnassignedBirthdays() {
    launch(arguments: ["-demo-profiles"])

    chooseProfile("School")
    assertCalendarContains("INF 2003")
    assertTodayContains("INF 2003")
    selectTab("Tasks")
    XCTAssertTrue(app.buttons["Open task Assignment 1"].exists)
    selectTab("Routines")
    XCTAssertTrue(app.staticTexts["Review notes"].exists)

    chooseProfile("Everything")
    selectTab("Calendar")
    XCTAssertTrue(app.buttons.matching(identifier: "agenda-open-event-demo-school-event").firstMatch.exists)
    XCTAssertFalse(app.staticTexts["Birthday"].exists)
}
```

The test uses stable IDs for the selector and profile menu entries. It verifies visibility only; assert no provider mutation counters/side effects through the demo fixture's existing recording hooks if exposed.

- [ ] **Step 3: Run only the new UI class**

```sh
xcodegen generate
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/ProfileFlowUITests
```

- [ ] **Step 4: Update README**

Document:

- profiles reference Apple/Google calendars rather than copying them
- how to assign the dedicated School calendar
- why unassigned Birthdays do not appear in Everything
- per-widget profile configuration
- one-time reconfiguration of old static widgets
- local-only widget refresh limitations
- Live Activity lifecycle limits
- App Group and Development Team requirements for a physical device

- [ ] **Step 5: Run bounded compile validation**

Do not run all tests. Run only the new profile unit classes in separate commands and the widget build:

```sh
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileRepositoryTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileMigrationCoordinatorTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileFeatureScopeTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileCreationTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/ProfileBackupTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableWidgetCatalogTests
xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/TimetableProfileActivityTests
xcodebuild build -project PersonalCalendar.xcodeproj -target PersonalCalendarWidgets -destination 'generic/platform=iOS Simulator'
git diff --check
```

- [ ] **Step 6: Manual Simulator checklist**

- Personal/School/Work/Everything appear after onboarding.
- School can select the dedicated Google calendar.
- Birthdays stay absent when unassigned.
- One shared source appears once in Everything.
- Profile switching keeps the current tab and updates all four tabs.
- Empty profile never exposes all system sources.
- Saved-profile creation seeds its writable default.
- Everything creation asks for a saved profile.
- Missing source shows `Waiting to reconnect`.
- Two widget instances remain pinned to different profiles.
- Deleted widget profile asks for reconfiguration.
- Live Activity starts from the explicitly chosen profile.
- VoiceOver says `Profile, School`; profile control and rows are at least 44 points.
- Accessibility Dynamic Type keeps selector and profile editor usable.
- Light-mode colors remain readable and are never the only distinction.

- [ ] **Step 7: Commit the final integration**

```sh
git add PersonalCalendar/App/DemoEnvironment.swift PersonalCalendar/App/AppEnvironment.swift PersonalCalendarUITests/ProfileFlowUITests.swift README.md PersonalCalendar.xcodeproj/project.pbxproj
git commit -m "feat: complete calendar profile experience"
```

## Completion Evidence

Before declaring this plan complete, record:

- commit IDs for Tasks 1–14
- exact focused commands run and their pass counts
- widget extension build result
- Simulator/device used
- any manual-only physical-device signing step still outstanding
- no global test command was run
- no EventKit/Reminders provider content was copied, moved, or deleted by profile operations
