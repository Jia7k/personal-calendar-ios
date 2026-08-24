# Personal Calendar Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a working iPhone app that reads the user's Apple events and reminders, stores private routines locally, and combines them in Calendar and Today views with reliable permission handling.

**Architecture:** A SwiftUI app receives dependencies through `AppEnvironment`. EventKit services remain the source of truth for events and reminders, SwiftData owns routines and completion records, and `AgendaComposer` converts all three into source-neutral view data. Every external boundary has a protocol and test fake so feature view models can be tested without permissions or a real device.

**Tech Stack:** Swift 6, SwiftUI, Observation, EventKit, SwiftData, UserNotifications, XCTest, XCUITest, XcodeGen 2.x, iOS 17+

**Spec:** `docs/superpowers/specs/2026-08-24-personal-calendar-ios-design.md`

## Global Constraints

- Build a native iPhone app with SwiftUI and a deployment target of iOS 17.0 or later.
- Use no third-party runtime dependencies and no CloudKit entitlement, account system, backend, analytics SDK, or network service.
- Apple Calendar and Apple Reminders remain authoritative; never persist a second copy of their complete item content.
- Persist only app-owned routines, completion records, categories, category links, and settings locally.
- Use original copy and styling; do not copy TimeTree assets, icons, names, or exact screen compositions.
- Support Dark Mode, Dynamic Type, VoiceOver, 44-point touch targets, and Reduce Motion throughout implementation.
- Use the device's locale, calendar, time zone, and 12/24-hour preference for user-facing dates and times.
- Keep EventKit objects inside `@MainActor` services because they are mutable reference objects and are not domain models.
- Use `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription`; full access is required because the app reads and writes both stores.
- Generate `PersonalCalendar.xcodeproj` from the committed `project.yml`; never hand-edit `project.pbxproj`.
- Run `xcodegen generate` after every source-file addition or deletion and before each `xcodebuild` command.

## File map

### Project and app shell

- `project.yml` — XcodeGen project definition, build settings, targets, schemes, and privacy strings.
- `PersonalCalendar/App/PersonalCalendarApp.swift` — SwiftData container and production/demo dependency selection.
- `PersonalCalendar/App/AppEnvironment.swift` — dependency container and live/demo factories.
- `PersonalCalendar/App/DemoEnvironment.swift` — deterministic in-app demo services used only by UI-test launch arguments.
- `PersonalCalendar/App/RootTabView.swift` — Calendar, Today, Tasks, and Routines tab shell plus Settings entry.
- `PersonalCalendar/DesignSystem/CalendarTheme.swift` — semantic colors, spacing, shapes, and source icons.
- `PersonalCalendar/Resources/Assets.xcassets/Contents.json` — asset catalog declaration.
- `PersonalCalendar/Resources/Assets.xcassets/AccentColor.colorset/Contents.json` — original accessible accent color.

### Domain and services

- `PersonalCalendar/Domain/LocalDay.swift` — locale-safe local day identity and date conversion.
- `PersonalCalendar/Domain/CalendarEventSnapshot.swift` — immutable event value used outside EventKit.
- `PersonalCalendar/Domain/ReminderSnapshot.swift` — immutable reminder value used outside EventKit.
- `PersonalCalendar/Domain/RoutineSnapshot.swift` — immutable routine value used outside SwiftData.
- `PersonalCalendar/Domain/AgendaItem.swift` — source-neutral agenda row and ordering metadata.
- `PersonalCalendar/Domain/Drafts.swift` — validated creation inputs for events, reminders, and routines.
- `PersonalCalendar/Services/Permissions/PermissionCoordinator.swift` — independent Calendar, Reminders, and notification permission state.
- `PersonalCalendar/Services/Permissions/SystemNotificationAuthorizer.swift` — production notification authorization adapter.
- `PersonalCalendar/Services/EventKit/CalendarServicing.swift` — Calendar boundary.
- `PersonalCalendar/Services/EventKit/EventKitCalendarService.swift` — production Calendar implementation.
- `PersonalCalendar/Services/EventKit/RemindersServicing.swift` — Reminders boundary.
- `PersonalCalendar/Services/EventKit/EventKitRemindersService.swift` — production Reminders implementation.
- `PersonalCalendar/Services/Agenda/AgendaComposer.swift` — merge and ordering rules.
- `PersonalCalendar/Settings/AppSettingsStore.swift` — selected sources, defaults, and simple local preferences.

### Persistence and features

- `PersonalCalendar/Persistence/RoutineRecord.swift` — SwiftData routine model.
- `PersonalCalendar/Persistence/RoutineCompletionRecord.swift` — SwiftData occurrence completion model.
- `PersonalCalendar/Persistence/RoutineRepository.swift` — persistence boundary.
- `PersonalCalendar/Persistence/SwiftDataRoutineRepository.swift` — production repository and streak calculation input.
- `PersonalCalendar/Features/Calendar/MonthGridBuilder.swift` — 42-cell month and 7-cell week generation.
- `PersonalCalendar/Features/Calendar/CalendarViewModel.swift` — date selection, month loading, and tray state.
- `PersonalCalendar/Features/Calendar/CalendarHomeView.swift` — month/week host and tray interaction.
- `PersonalCalendar/Features/Calendar/MonthGridView.swift` — accessible calendar grid.
- `PersonalCalendar/Features/Calendar/DayTrayView.swift` — resting and expanded day content.
- `PersonalCalendar/Features/Calendar/NewEventSheet.swift` — basic event creation before the universal quick-entry milestone.
- `PersonalCalendar/Features/Today/TodayViewModel.swift` — current-day loading and refresh.
- `PersonalCalendar/Features/Today/TodayView.swift` — full-day agenda.
- `PersonalCalendar/Features/Tasks/TasksViewModel.swift` — reminder loading, creation, and completion.
- `PersonalCalendar/Features/Tasks/TasksView.swift` — Today, Upcoming, and Completed groupings.
- `PersonalCalendar/Features/Tasks/NewTaskSheet.swift` — basic reminder creation.
- `PersonalCalendar/Features/Routines/RoutinesViewModel.swift` — routine CRUD subset and completion.
- `PersonalCalendar/Features/Routines/RoutinesView.swift` — routine list and completion actions.
- `PersonalCalendar/Features/Routines/RoutineEditorView.swift` — create and edit basic routine fields.
- `PersonalCalendar/Features/Settings/SettingsView.swift` — source selection, defaults, and permission status.
- `PersonalCalendar/Features/Onboarding/PermissionOnboardingView.swift` — first-run explanation with separate, skippable permission requests.

### Tests

- `PersonalCalendarTests/Support/Fakes.swift` — deterministic service and repository fakes.
- `PersonalCalendarTests/Domain/LocalDayTests.swift`
- `PersonalCalendarTests/Services/PermissionCoordinatorTests.swift`
- `PersonalCalendarTests/Services/EventKitServiceMappingTests.swift`
- `PersonalCalendarTests/Persistence/RoutineRepositoryTests.swift`
- `PersonalCalendarTests/Services/AgendaComposerTests.swift`
- `PersonalCalendarTests/Features/MonthGridBuilderTests.swift`
- `PersonalCalendarTests/Features/FeatureViewModelTests.swift`
- `PersonalCalendarUITests/FoundationFlowUITests.swift`

---

### Task 1: Bootstrap the project and accessible tab shell

**Files:**
- Modify: `.gitignore`
- Create: `project.yml`
- Create: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Create: `PersonalCalendar/App/AppEnvironment.swift`
- Create: `PersonalCalendar/App/RootTabView.swift`
- Create: `PersonalCalendar/DesignSystem/CalendarTheme.swift`
- Create: `PersonalCalendar/Resources/Assets.xcassets/Contents.json`
- Create: `PersonalCalendar/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `PersonalCalendarUITests/FoundationFlowUITests.swift`

**Interfaces:**
- Consumes: none.
- Produces: `AppEnvironment`, `RootTab`, `RootTabView`, `CalendarTheme`, and the `PersonalCalendar` Xcode scheme used by every later task.

- [ ] **Step 1: Add the deterministic XcodeGen definition**

Append these Xcode-only paths to `.gitignore`:

```gitignore
DerivedData/
*.xcuserstate
xcuserdata/
```

Create `project.yml` with these target settings and privacy strings:

```yaml
name: PersonalCalendar
options:
  bundleIdPrefix: local.personalcalendar
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Automatic
targets:
  PersonalCalendar:
    type: application
    platform: iOS
    sources:
      - path: PersonalCalendar
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: local.personalcalendar.iphone
        PRODUCT_NAME: "My Calendar"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: "My Calendar"
        INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription: "Show and manage your calendar events in one personal schedule."
        INFOPLIST_KEY_NSRemindersFullAccessUsageDescription: "Show and manage your reminders alongside your schedule."
        INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
  PersonalCalendarTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: PersonalCalendarTests
    dependencies:
      - target: PersonalCalendar
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: local.personalcalendar.tests
        GENERATE_INFOPLIST_FILE: YES
  PersonalCalendarUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: PersonalCalendarUITests
    dependencies:
      - target: PersonalCalendar
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: local.personalcalendar.uitests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  PersonalCalendar:
    build:
      targets:
        PersonalCalendar: all
        PersonalCalendarTests: [test]
        PersonalCalendarUITests: [test]
    test:
      targets:
        - PersonalCalendarTests
        - PersonalCalendarUITests
```

Create `PersonalCalendar/Resources/Assets.xcassets/Contents.json`:

```json
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

Create `PersonalCalendar/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`:

```json
{
  "colors": [
    {
      "color": {
        "color-space": "srgb",
        "components": { "alpha": "1.000", "blue": "0.500", "green": "0.550", "red": "0.200" }
      },
      "idiom": "universal"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

Run: `brew install xcodegen`

Expected: XcodeGen 2.x is available on `PATH`.

Run: `xcodegen generate`

Expected: `PersonalCalendar.xcodeproj` is generated from `project.yml`.

- [ ] **Step 2: Write the failing launch test**

Create `PersonalCalendarUITests/FoundationFlowUITests.swift`:

```swift
import XCTest

final class FoundationFlowUITests: XCTestCase {
    func testLaunchShowsFourPrimaryTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Tasks"].exists)
        XCTAssertTrue(app.tabBars.buttons["Routines"].exists)
    }
}
```

- [ ] **Step 3: Run the test and confirm the app target is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testLaunchShowsFourPrimaryTabs`

Expected: FAIL because `PersonalCalendarApp` and `RootTabView` do not exist.

- [ ] **Step 4: Add the minimal app, environment, theme, and tab shell**

Use this root contract:

```swift
import SwiftUI

enum RootTab: Hashable {
    case calendar, today, tasks, routines
}

struct AppEnvironment {
    static let bootstrap = AppEnvironment()
}

enum CalendarTheme {
    static let accent = Color(red: 0.20, green: 0.55, blue: 0.50)
    static let cornerRadius: CGFloat = 16
    static let minimumTapSize: CGFloat = 44
}

struct RootTabView: View {
    @State private var selection: RootTab = .calendar

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { Text("Calendar") }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(RootTab.calendar)
            NavigationStack { Text("Today") }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(RootTab.today)
            NavigationStack { Text("Tasks") }
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(RootTab.tasks)
            NavigationStack { Text("Routines") }
                .tabItem { Label("Routines", systemImage: "repeat") }
                .tag(RootTab.routines)
        }
        .tint(CalendarTheme.accent)
    }
}

@main
struct PersonalCalendarApp: App {
    var body: some Scene {
        WindowGroup { RootTabView() }
    }
}
```

Place each declaration in the matching file from the task's file list.

- [ ] **Step 5: Generate, build, test, and commit**

Run: `xcodegen generate`

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testLaunchShowsFourPrimaryTabs`

Expected: PASS.

Run: `git add .gitignore project.yml PersonalCalendar PersonalCalendarUITests PersonalCalendar.xcodeproj`

Run: `git commit -m "build: bootstrap personal calendar app"`

---

### Task 2: Define local-day and agenda domain values

**Files:**
- Create: `PersonalCalendar/Domain/LocalDay.swift`
- Create: `PersonalCalendar/Domain/CalendarEventSnapshot.swift`
- Create: `PersonalCalendar/Domain/ReminderSnapshot.swift`
- Create: `PersonalCalendar/Domain/RoutineSnapshot.swift`
- Create: `PersonalCalendar/Domain/AgendaItem.swift`
- Create: `PersonalCalendar/Domain/Drafts.swift`
- Create: `PersonalCalendarTests/Domain/LocalDayTests.swift`

**Interfaces:**
- Consumes: Foundation and XCTest target from Task 1.
- Produces: `LocalDay`, `RoutineWindow`, `CalendarEventSnapshot`, `ReminderSnapshot`, `RoutineSnapshot`, `AgendaItem`, `EventDraft`, `ReminderDraft`, and `RoutineDraft`.

- [ ] **Step 1: Write failing date and window tests**

```swift
import XCTest
@testable import PersonalCalendar

final class LocalDayTests: XCTestCase {
    func testRoundTripUsesInjectedCalendarAndTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 23)))

        let day = LocalDay(date: date, calendar: calendar)

        XCTAssertEqual(day, LocalDay(year: 2026, month: 8, day: 24))
        XCTAssertEqual(day.startDate(in: calendar), calendar.startOfDay(for: date))
    }

    func testRoutineWindowAnchorsAreDeterministic() {
        XCTAssertEqual(RoutineWindow.morning.anchorHour, 9)
        XCTAssertEqual(RoutineWindow.afternoon.anchorHour, 13)
        XCTAssertEqual(RoutineWindow.evening.anchorHour, 18)
        XCTAssertNil(RoutineWindow.anytime.anchorHour)
    }

    func testNextLocalDayUsesCalendarAcrossDaylightSavingChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let day = LocalDay(year: 2026, month: 3, day: 8)
        let next = calendar.date(byAdding: .day, value: 1, to: day.startDate(in: calendar))!

        XCTAssertEqual(LocalDay(date: next, calendar: calendar), LocalDay(year: 2026, month: 3, day: 9))
        XCTAssertEqual(next.timeIntervalSince(day.startDate(in: calendar)), 23 * 60 * 60)
    }

    func testMonthBoundaryKeepsCalendarComponents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let next = calendar.date(byAdding: .day, value: 1, to: LocalDay(year: 2026, month: 8, day: 31).startDate(in: calendar))!
        XCTAssertEqual(LocalDay(date: next, calendar: calendar), LocalDay(year: 2026, month: 9, day: 1))
    }
}
```

- [ ] **Step 2: Run the tests and verify missing types fail**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/LocalDayTests`

Expected: FAIL with missing `LocalDay` and `RoutineWindow`.

- [ ] **Step 3: Implement exact date and snapshot contracts**

```swift
import Foundation

struct LocalDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    func startDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

enum RoutineWindow: String, Codable, CaseIterable, Sendable {
    case morning, afternoon, evening, anytime

    var anchorHour: Int? {
        switch self {
        case .morning: 9
        case .afternoon: 13
        case .evening: 18
        case .anytime: nil
        }
    }
}

struct CalendarEventSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let allowsModification: Bool
    let hasRecurrence: Bool
}

struct ReminderSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let dueDate: Date?
    var dueHasTime: Bool = false
    let priority: Int
    let listID: String
    let listTitle: String
    let isCompleted: Bool
    let allowsModification: Bool
    let hasRecurrence: Bool
}

struct RoutineSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let weekdays: Set<Int>
    let window: RoutineWindow
    let reminderHour: Int?
    let reminderMinute: Int?
    let isPaused: Bool
    let isArchived: Bool
}

enum AgendaSource: String, Equatable, Sendable { case event, task, routine }
enum AgendaPlacement: Equatable, Sendable { case allDay, timed(Date), window(RoutineWindow), unscheduled }

struct AgendaItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let source: AgendaSource
    let placement: AgendaPlacement
    let sortDate: Date?
    let priority: Int
    let isCompleted: Bool
    let allowsModification: Bool
}

struct EventDraft: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String?
}

struct ReminderDraft: Equatable, Sendable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var dueHasTime: Bool = false
    var priority: Int
    var listID: String?
}

struct RoutineDraft: Equatable, Sendable {
    var title: String
    var weekdays: Set<Int>
    var window: RoutineWindow
    var reminderHour: Int?
    var reminderMinute: Int?
}
```

Split the declarations into the matching domain files; do not keep a combined domain file.

- [ ] **Step 4: Run domain tests**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/LocalDayTests`

Expected: PASS.

- [ ] **Step 5: Commit the domain contracts**

Run: `git add PersonalCalendar/Domain PersonalCalendarTests/Domain`

Run: `git commit -m "feat: define calendar domain values"`

---

### Task 3: Add service boundaries and independent permission handling

**Files:**
- Create: `PersonalCalendar/Services/EventKit/CalendarServicing.swift`
- Create: `PersonalCalendar/Services/EventKit/RemindersServicing.swift`
- Create: `PersonalCalendar/Services/Permissions/PermissionCoordinator.swift`
- Create: `PersonalCalendar/Services/Permissions/SystemNotificationAuthorizer.swift`
- Create: `PersonalCalendarTests/Support/Fakes.swift`
- Create: `PersonalCalendarTests/Services/PermissionCoordinatorTests.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`

**Interfaces:**
- Consumes: domain snapshots and drafts from Task 2.
- Produces: `AccessState`, `CalendarDescriptor`, `ReminderListDescriptor`, `CalendarServicing`, `RemindersServicing`, `NotificationAuthorizing`, and `PermissionCoordinator`.

- [ ] **Step 1: Write failing permission tests with independent fakes**

```swift
import XCTest
@testable import PersonalCalendar

@MainActor
final class PermissionCoordinatorTests: XCTestCase {
    func testDeniedCalendarDoesNotBlockGrantedReminders() async {
        let calendar = FakeCalendarService(access: .denied)
        let reminders = FakeRemindersService(access: .notDetermined, requestedAccess: .granted)
        let notifications = FakeNotificationAuthorizer(access: .denied)
        let subject = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)

        await subject.refresh()
        await subject.requestReminders()

        XCTAssertEqual(subject.calendarAccess, .denied)
        XCTAssertEqual(subject.remindersAccess, .granted)
        XCTAssertEqual(subject.notificationAccess, .denied)
    }
}
```

- [ ] **Step 2: Run the test and verify protocols are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/PermissionCoordinatorTests`

Expected: FAIL with missing service contracts.

- [ ] **Step 3: Define the service interfaces and permission coordinator**

```swift
import Foundation

enum AccessState: Equatable, Sendable { case notDetermined, granted, denied, restricted }

struct CalendarDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

struct ReminderListDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

@MainActor
protocol CalendarServicing: AnyObject {
    var accessState: AccessState { get }
    func requestFullAccess() async -> AccessState
    func calendars() -> [CalendarDescriptor]
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot]
    func createEvent(_ draft: EventDraft) throws -> String
}

@MainActor
protocol RemindersServicing: AnyObject {
    var accessState: AccessState { get }
    func requestFullAccess() async -> AccessState
    func lists() -> [ReminderListDescriptor]
    func fetchReminders(listIDs: Set<String>) async -> [ReminderSnapshot]
    func createReminder(_ draft: ReminderDraft) throws -> String
    func setCompleted(id: String, completed: Bool) throws
}

@MainActor
protocol NotificationAuthorizing: AnyObject {
    var accessState: AccessState { get async }
    func requestAccess() async -> AccessState
}

@MainActor
@Observable
final class PermissionCoordinator {
    private(set) var calendarAccess: AccessState
    private(set) var remindersAccess: AccessState
    private(set) var notificationAccess: AccessState
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let notifications: any NotificationAuthorizing

    init(calendar: any CalendarServicing, reminders: any RemindersServicing, notifications: any NotificationAuthorizing) {
        self.calendar = calendar
        self.reminders = reminders
        self.notifications = notifications
        calendarAccess = calendar.accessState
        remindersAccess = reminders.accessState
        notificationAccess = .notDetermined
    }

    func refresh() async {
        calendarAccess = calendar.accessState
        remindersAccess = reminders.accessState
        notificationAccess = await notifications.accessState
    }

    func requestCalendar() async { calendarAccess = await calendar.requestFullAccess() }
    func requestReminders() async { remindersAccess = await reminders.requestFullAccess() }
    func requestNotifications() async { notificationAccess = await notifications.requestAccess() }
}
```

Add fakes whose stored results exactly implement these protocols. Update `AppEnvironment` to store all three services and the coordinator.

Use these fake shapes so later feature tests share one vocabulary:

```swift
@MainActor
final class FakeCalendarService: CalendarServicing {
    var accessState: AccessState
    var requestedAccess: AccessState
    var events: [CalendarEventSnapshot]
    var descriptors: [CalendarDescriptor]
    var createdDrafts: [EventDraft] = []

    init(access: AccessState, requestedAccess: AccessState? = nil, events: [CalendarEventSnapshot] = [], descriptors: [CalendarDescriptor] = []) {
        accessState = access
        self.requestedAccess = requestedAccess ?? access
        self.events = events
        self.descriptors = descriptors
    }

    func requestFullAccess() async -> AccessState { accessState = requestedAccess; return accessState }
    func calendars() -> [CalendarDescriptor] { descriptors }
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] { events }
    func createEvent(_ draft: EventDraft) throws -> String { createdDrafts.append(draft); return "created-event" }
}

struct CompletionCall: Equatable { let id: String; let completed: Bool }

@MainActor
final class FakeRemindersService: RemindersServicing {
    var accessState: AccessState
    var requestedAccess: AccessState
    var reminders: [ReminderSnapshot]
    var descriptors: [ReminderListDescriptor]
    var createdDrafts: [ReminderDraft] = []
    var completedCalls: [CompletionCall] = []

    init(access: AccessState, requestedAccess: AccessState? = nil, reminders: [ReminderSnapshot] = [], descriptors: [ReminderListDescriptor] = []) {
        accessState = access
        self.requestedAccess = requestedAccess ?? access
        self.reminders = reminders
        self.descriptors = descriptors
    }

    func requestFullAccess() async -> AccessState { accessState = requestedAccess; return accessState }
    func lists() -> [ReminderListDescriptor] { descriptors }
    func fetchReminders(listIDs: Set<String>) async -> [ReminderSnapshot] { reminders }
    func createReminder(_ draft: ReminderDraft) throws -> String { createdDrafts.append(draft); return "created-task" }
    func setCompleted(id: String, completed: Bool) throws { completedCalls.append(.init(id: id, completed: completed)) }
}

@MainActor
final class FakeNotificationAuthorizer: NotificationAuthorizing {
    private var state: AccessState
    private let requested: AccessState
    init(access: AccessState, requestedAccess: AccessState? = nil) { state = access; requested = requestedAccess ?? access }
    var accessState: AccessState { get async { state } }
    func requestAccess() async -> AccessState { state = requested; return state }
}
```

Create the production notification adapter:

```swift
import UserNotifications

@MainActor
final class SystemNotificationAuthorizer: NotificationAuthorizing {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    var accessState: AccessState {
        get async {
            let status = await center.notificationSettings().authorizationStatus
            switch status {
            case .authorized, .provisional, .ephemeral: .granted
            case .notDetermined: .notDetermined
            case .denied: .denied
            @unknown default: .restricted
            }
        }
    }

    func requestAccess() async -> AccessState {
        do { return try await center.requestAuthorization(options: [.alert, .sound]) ? .granted : .denied }
        catch { return .denied }
    }
}
```

- [ ] **Step 4: Run permission tests**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/PermissionCoordinatorTests`

Expected: PASS.

- [ ] **Step 5: Commit boundaries and permission behavior**

Run: `git add PersonalCalendar/App/AppEnvironment.swift PersonalCalendar/Services PersonalCalendarTests/Support PersonalCalendarTests/Services/PermissionCoordinatorTests.swift`

Run: `git commit -m "feat: add independent permission services"`

---

### Task 4: Implement basic Apple Calendar reading and creation

**Files:**
- Create: `PersonalCalendar/Services/EventKit/EventKitCalendarService.swift`
- Create: `PersonalCalendar/Services/EventKit/EventKitMapping.swift`
- Create: `PersonalCalendarTests/Services/EventKitServiceMappingTests.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`

**Interfaces:**
- Consumes: `CalendarServicing`, `CalendarDescriptor`, `CalendarEventSnapshot`, and `EventDraft`.
- Produces: `EventKitCalendarService` backed by one long-lived `EKEventStore`.

- [ ] **Step 1: Write failing mapper and validation tests**

```swift
import XCTest
@testable import PersonalCalendar

final class EventKitServiceMappingTests: XCTestCase {
    func testEventDraftRejectsBlankTitleAndInvertedDates() {
        let date = Date(timeIntervalSince1970: 100)
        XCTAssertThrowsError(try EventDraftValidator.validate(.init(title: " ", start: date, end: date.addingTimeInterval(60), isAllDay: false, calendarID: nil)))
        XCTAssertThrowsError(try EventDraftValidator.validate(.init(title: "Dentist", start: date, end: date.addingTimeInterval(-60), isAllDay: false, calendarID: nil)))
    }

    func testAuthorizationMappingRequiresFullAccess() {
        XCTAssertEqual(EventKitAccessMapper.map(.fullAccess), .granted)
        XCTAssertEqual(EventKitAccessMapper.map(.denied), .denied)
        XCTAssertEqual(EventKitAccessMapper.map(.writeOnly), .restricted)
    }
}
```

- [ ] **Step 2: Run tests and verify mapping types are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/EventKitServiceMappingTests`

Expected: FAIL with missing mapper and validator.

- [ ] **Step 3: Implement the EventKit service**

Use one injected store and map EventKit objects immediately into immutable snapshots:

```swift
import EventKit

enum DraftValidationError: Error, Equatable { case emptyTitle, invalidDateRange, readOnlyDestination }

enum EventDraftValidator {
    static func validate(_ draft: EventDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DraftValidationError.emptyTitle }
        guard draft.end > draft.start else { throw DraftValidationError.invalidDateRange }
    }
}

enum EventKitAccessMapper {
    static func map(_ status: EKAuthorizationStatus) -> AccessState {
        switch status {
        case .fullAccess, .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted, .writeOnly: .restricted
        @unknown default: .restricted
        }
    }
}

@MainActor
final class EventKitCalendarService: CalendarServicing {
    private let store: EKEventStore
    init(store: EKEventStore) { self.store = store }

    var accessState: AccessState { EventKitAccessMapper.map(EKEventStore.authorizationStatus(for: .event)) }

    func requestFullAccess() async -> AccessState {
        do { return try await store.requestFullAccessToEvents() ? .granted : .denied }
        catch { return .denied }
    }

    func calendars() -> [CalendarDescriptor] {
        guard accessState == .granted else { return [] }
        return store.calendars(for: .event).map {
            CalendarDescriptor(id: $0.calendarIdentifier, title: $0.title, colorHex: $0.cgColor.hexRGB, allowsContentModifications: $0.allowsContentModifications)
        }
    }

    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] {
        guard accessState == .granted else { return [] }
        let selected = store.calendars(for: .event).filter { calendarIDs.isEmpty || calendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: selected)
        return store.events(matching: predicate).map(CalendarEventSnapshot.init(event:))
    }

    func createEvent(_ draft: EventDraft) throws -> String {
        try EventDraftValidator.validate(draft)
        let destination = draft.calendarID.flatMap { id in store.calendars(for: .event).first { $0.calendarIdentifier == id } } ?? store.defaultCalendarForNewEvents
        guard let destination, destination.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
        let event = EKEvent(eventStore: store)
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.calendar = destination
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
}
```

Implement the `CGColor.hexRGB` and `CalendarEventSnapshot.init(event:)` mapping helpers in `EventKitMapping.swift`. Preserve title, dates, all-day status, source calendar, mutability, and `hasRecurrenceRules`.

- [ ] **Step 4: Run mapper tests and build the app**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/EventKitServiceMappingTests`

Run: `xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`

Expected: tests and build PASS.

- [ ] **Step 5: Commit Calendar integration**

Run: `git add PersonalCalendar/Services/EventKit PersonalCalendar/App/AppEnvironment.swift PersonalCalendarTests/Services/EventKitServiceMappingTests.swift PersonalCalendarTests/Support/Fakes.swift`

Run: `git commit -m "feat: read and create Apple calendar events"`

---

### Task 5: Implement basic Apple Reminders reading, creation, and completion

**Files:**
- Create: `PersonalCalendar/Services/EventKit/EventKitRemindersService.swift`
- Modify: `PersonalCalendar/Services/EventKit/EventKitMapping.swift`
- Modify: `PersonalCalendarTests/Services/EventKitServiceMappingTests.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`

**Interfaces:**
- Consumes: `RemindersServicing`, `ReminderListDescriptor`, `ReminderSnapshot`, and `ReminderDraft`.
- Produces: `EventKitRemindersService` backed by the same long-lived `EKEventStore` as Calendar.

- [ ] **Step 1: Add failing reminder validation and recurrence-visibility tests**

```swift
func testReminderDraftRejectsBlankTitle() {
    XCTAssertThrowsError(try ReminderDraftValidator.validate(.init(title: "\n", notes: nil, dueDate: nil, priority: 0, listID: nil)))
}

func testRecurringReminderSnapshotRepresentsOnlySuppliedOccurrence() {
    let snapshot = ReminderSnapshot(id: "r1", title: "Pay bill", notes: nil, dueDate: Date(), dueHasTime: false, priority: 0, listID: "l1", listTitle: "Tasks", isCompleted: false, allowsModification: true, hasRecurrence: true)
    XCTAssertTrue(snapshot.hasRecurrence)
    XCTAssertFalse(snapshot.isCompleted)
}
```

- [ ] **Step 2: Run mapper tests and confirm validation is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/EventKitServiceMappingTests`

Expected: FAIL with missing `ReminderDraftValidator`.

- [ ] **Step 3: Implement the Reminders service**

```swift
import EventKit

enum ReminderDraftValidator {
    static func validate(_ draft: ReminderDraft) throws {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DraftValidationError.emptyTitle }
    }
}

@MainActor
final class EventKitRemindersService: RemindersServicing {
    private let store: EKEventStore
    init(store: EKEventStore) { self.store = store }

    var accessState: AccessState { EventKitAccessMapper.map(EKEventStore.authorizationStatus(for: .reminder)) }

    func requestFullAccess() async -> AccessState {
        do { return try await store.requestFullAccessToReminders() ? .granted : .denied }
        catch { return .denied }
    }

    func lists() -> [ReminderListDescriptor] {
        guard accessState == .granted else { return [] }
        return store.calendars(for: .reminder).map {
            ReminderListDescriptor(id: $0.calendarIdentifier, title: $0.title, colorHex: $0.cgColor.hexRGB, allowsContentModifications: $0.allowsContentModifications)
        }
    }

    func fetchReminders(listIDs: Set<String>) async -> [ReminderSnapshot] {
        guard accessState == .granted else { return [] }
        let selected = store.calendars(for: .reminder).filter { listIDs.isEmpty || listIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForReminders(in: selected)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(ReminderSnapshot.init(reminder:)))
            }
        }
    }

    func createReminder(_ draft: ReminderDraft) throws -> String {
        try ReminderDraftValidator.validate(draft)
        let destination = draft.listID.flatMap { id in store.calendars(for: .reminder).first { $0.calendarIdentifier == id } } ?? store.defaultCalendarForNewReminders()
        guard let destination, destination.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = draft.notes
        reminder.priority = draft.priority
        reminder.calendar = destination
        if let dueDate = draft.dueDate {
            let requested: Set<Calendar.Component> = draft.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            var components = Calendar.current.dateComponents(requested, from: dueDate)
            components.calendar = .current
            components.timeZone = .current
            reminder.dueDateComponents = components
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func setCompleted(id: String, completed: Bool) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.calendar.allowsContentModifications else { throw DraftValidationError.readOnlyDestination }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }
}
```

Map only the occurrence EventKit supplies. Do not generate future recurring reminder snapshots.

`ReminderSnapshot.init(reminder:)` sets `dueHasTime` to true only when `dueDateComponents.hour` is present. `AgendaItem.init(reminder:)` uses `.timed(dueDate)` only when `dueHasTime` is true; a date-only reminder belongs in the Priority section for its due day.

Add this shared fixture to `PersonalCalendarTests/Support/Fakes.swift`:

```swift
extension ReminderSnapshot {
    static let sampleTask = ReminderSnapshot(id: "task", title: "Buy milk", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: "tasks", listTitle: "Tasks", isCompleted: false, allowsModification: true, hasRecurrence: false)
}
```

- [ ] **Step 4: Run tests and build**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/EventKitServiceMappingTests`

Run: `xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`

Expected: PASS.

- [ ] **Step 5: Commit Reminders integration**

Run: `git add PersonalCalendar/Services/EventKit PersonalCalendar/App/AppEnvironment.swift PersonalCalendarTests/Services/EventKitServiceMappingTests.swift`

Run: `git commit -m "feat: read and manage basic Apple reminders"`

---

### Task 6: Persist routines and completion history with SwiftData

**Files:**
- Create: `PersonalCalendar/Persistence/RoutineRecord.swift`
- Create: `PersonalCalendar/Persistence/RoutineCompletionRecord.swift`
- Create: `PersonalCalendar/Persistence/RoutineRepository.swift`
- Create: `PersonalCalendar/Persistence/SwiftDataRoutineRepository.swift`
- Create: `PersonalCalendarTests/Persistence/RoutineRepositoryTests.swift`
- Modify: `PersonalCalendarTests/Support/Fakes.swift`
- Modify: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`

**Interfaces:**
- Consumes: `LocalDay`, `RoutineDraft`, `RoutineSnapshot`, and `RoutineWindow`.
- Produces: `RoutineRepository`, `SwiftDataRoutineRepository`, `RoutineRecord`, `RoutineCompletionRecord`, and `RoutineStreakCalculator`.

- [ ] **Step 1: Write failing in-memory persistence tests**

```swift
import SwiftData
import XCTest
@testable import PersonalCalendar

@MainActor
final class RoutineRepositoryTests: XCTestCase {
    func testCreateCompleteAndUndoRoundTrip() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RoutineRecord.self, RoutineCompletionRecord.self, configurations: configuration)
        let subject = SwiftDataRoutineRepository(context: container.mainContext)
        let day = LocalDay(year: 2026, month: 8, day: 24)
        let id = try subject.create(.init(title: "Read", weekdays: [1,2,3,4,5,6,7], window: .evening, reminderHour: nil, reminderMinute: nil))

        try subject.setCompleted(routineID: id, day: day, completed: true)
        XCTAssertTrue(try subject.isCompleted(routineID: id, day: day))

        try subject.setCompleted(routineID: id, day: day, completed: false)
        XCTAssertFalse(try subject.isCompleted(routineID: id, day: day))
    }
}
```

- [ ] **Step 2: Run the test and verify persistence types are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/RoutineRepositoryTests`

Expected: FAIL with missing SwiftData models.

- [ ] **Step 3: Implement models, repository, and streak input**

```swift
import SwiftData

@Model
final class RoutineRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var weekdays: [Int]
    var windowRaw: String
    var reminderHour: Int?
    var reminderMinute: Int?
    var isPaused: Bool
    var isArchived: Bool
    var createdAt: Date

    init(id: UUID = UUID(), draft: RoutineDraft, createdAt: Date = .now) {
        self.id = id
        title = draft.title
        weekdays = draft.weekdays.sorted()
        windowRaw = draft.window.rawValue
        reminderHour = draft.reminderHour
        reminderMinute = draft.reminderMinute
        isPaused = false
        isArchived = false
        self.createdAt = createdAt
    }
}

@Model
final class RoutineCompletionRecord {
    @Attribute(.unique) var key: String
    var routineID: UUID
    var year: Int
    var month: Int
    var day: Int
    var completedAt: Date

    init(routineID: UUID, day: LocalDay, completedAt: Date = .now) {
        key = "\(routineID.uuidString)|\(day.year)-\(day.month)-\(day.day)"
        self.routineID = routineID
        year = day.year
        month = day.month
        self.day = day.day
        self.completedAt = completedAt
    }
}

@MainActor
protocol RoutineRepository: AnyObject {
    func list(includeArchived: Bool) throws -> [RoutineSnapshot]
    func create(_ draft: RoutineDraft) throws -> UUID
    func update(id: UUID, draft: RoutineDraft) throws
    func setPaused(id: UUID, paused: Bool) throws
    func setArchived(id: UUID, archived: Bool) throws
    func delete(id: UUID) throws
    func setCompleted(routineID: UUID, day: LocalDay, completed: Bool) throws
    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool
    func completedDays(routineID: UUID) throws -> Set<LocalDay>
}

struct RoutineStreakCalculator {
    func currentStreak(routine: RoutineSnapshot, completedDays: Set<LocalDay>, through day: LocalDay, calendar: Calendar) -> Int {
        guard !routine.weekdays.isEmpty else { return 0 }
        var cursor = day
        if routine.weekdays.contains(calendar.component(.weekday, from: cursor.startDate(in: calendar))) && !completedDays.contains(cursor) {
            cursor = LocalDay(date: calendar.date(byAdding: .day, value: -1, to: cursor.startDate(in: calendar))!, calendar: calendar)
        }
        var streak = 0
        while true {
            let weekday = calendar.component(.weekday, from: cursor.startDate(in: calendar))
            if routine.weekdays.contains(weekday) {
                guard completedDays.contains(cursor) else { return streak }
                streak += 1
            }
            cursor = LocalDay(date: calendar.date(byAdding: .day, value: -1, to: cursor.startDate(in: calendar))!, calendar: calendar)
        }
    }
}
```

Add this repository fake after the production protocol exists:

```swift
struct RoutineCompletionCall: Equatable { let id: UUID; let day: LocalDay; let completed: Bool }

extension RoutineSnapshot {
    static let sampleRoutine = RoutineSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Read", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .evening, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)
}

@MainActor
final class FakeRoutineRepository: RoutineRepository {
    var routines: [RoutineSnapshot]
    var createdDrafts: [RoutineDraft] = []
    var completionCalls: [RoutineCompletionCall] = []
    private var completions: [UUID: Set<LocalDay>] = [:]

    init(routines: [RoutineSnapshot] = []) { self.routines = routines }
    func list(includeArchived: Bool) throws -> [RoutineSnapshot] { includeArchived ? routines : routines.filter { !$0.isArchived } }
    func create(_ draft: RoutineDraft) throws -> UUID { createdDrafts.append(draft); return UUID() }
    func update(id: UUID, draft: RoutineDraft) throws { }
    func setPaused(id: UUID, paused: Bool) throws { }
    func setArchived(id: UUID, archived: Bool) throws { }
    func delete(id: UUID) throws { routines.removeAll { $0.id == id }; completions[id] = nil }
    func setCompleted(routineID: UUID, day: LocalDay, completed: Bool) throws {
        completionCalls.append(.init(id: routineID, day: day, completed: completed))
        if completed { completions[routineID, default: []].insert(day) } else { completions[routineID]?.remove(day) }
    }
    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool { completions[routineID, default: []].contains(day) }
    func completedDays(routineID: UUID) throws -> Set<LocalDay> { completions[routineID, default: []] }
}
```

Implement each method with `FetchDescriptor`, explicit `context.save()`, and a unique completion key. `delete(id:)` removes the routine and every completion record with that `routineID`. Reject blank titles, empty weekday sets, and reminder components outside hour `0...23` and minute `0...59` with `RoutineRepositoryError.invalidDraft`.

Extend `RoutineRepositoryTests` with a Monday/Wednesday/Friday streak case: completions on the two most recent scheduled days return `2` when today's scheduled occurrence is incomplete and `3` after today's occurrence is completed. Add a delete assertion that both the routine and its completion rows are gone.

Create the production `ModelContainer` with only `RoutineRecord` and `RoutineCompletionRecord`; do not add a CloudKit configuration or entitlement.

- [ ] **Step 4: Run persistence tests**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/RoutineRepositoryTests`

Expected: PASS.

- [ ] **Step 5: Commit local routine persistence**

Run: `git add PersonalCalendar/Persistence PersonalCalendar/App PersonalCalendarTests/Persistence PersonalCalendarTests/Support/Fakes.swift`

Run: `git commit -m "feat: persist private routines locally"`

---

### Task 7: Merge events, reminders, and routines into one day agenda

**Files:**
- Create: `PersonalCalendar/Services/Agenda/AgendaComposer.swift`
- Create: `PersonalCalendarTests/Services/AgendaComposerTests.swift`

**Interfaces:**
- Consumes: all snapshot types, `LocalDay`, and routine completion state.
- Produces: `DayAgenda` and `AgendaComposer.compose(day:events:reminders:routines:completedRoutineIDs:includeOverdueTasks:calendar:)`.

- [ ] **Step 1: Write failing ordering and filtering tests**

```swift
import XCTest
@testable import PersonalCalendar

final class AgendaComposerTests: XCTestCase {
    func testOrdersAllDayTimedWindowAndUnscheduledSections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        let day = LocalDay(year: 2026, month: 8, day: 24)
        let start = day.startDate(in: calendar)
        let events = [CalendarEventSnapshot(id: "event", title: "Birthday", start: start, end: start.addingTimeInterval(86_400), isAllDay: true, calendarID: "c", calendarTitle: "Home", allowsModification: true, hasRecurrence: false)]
        let reminders = [ReminderSnapshot(id: "task", title: "Buy milk", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: "l", listTitle: "Tasks", isCompleted: false, allowsModification: true, hasRecurrence: false)]
        let routines = [RoutineSnapshot(id: UUID(), title: "Read", weekdays: [1,2,3,4,5,6,7], window: .evening, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)]

        let result = AgendaComposer().compose(day: day, events: events, reminders: reminders, routines: routines, completedRoutineIDs: [], includeOverdueTasks: true, calendar: calendar)

        XCTAssertEqual(result.allDay.map(\.title), ["Birthday"])
        XCTAssertEqual(result.scheduled.map(\.title), ["Read"])
        XCTAssertEqual(result.priority.map(\.title), ["Buy milk"])
    }
}
```

- [ ] **Step 2: Run test and confirm composer is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/AgendaComposerTests`

Expected: FAIL with missing `AgendaComposer` and `DayAgenda`.

- [ ] **Step 3: Implement explicit grouping rules**

```swift
struct DayAgenda: Equatable, Sendable {
    var allDay: [AgendaItem]
    var scheduled: [AgendaItem]
    var priority: [AgendaItem]
}

struct AgendaComposer {
    func compose(
        day: LocalDay,
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot],
        routines: [RoutineSnapshot],
        completedRoutineIDs: Set<UUID>,
        includeOverdueTasks: Bool,
        calendar: Calendar
    ) -> DayAgenda {
        let interval = DateInterval(start: day.startDate(in: calendar), end: calendar.date(byAdding: .day, value: 1, to: day.startDate(in: calendar))!)
        let eventItems = events.filter { $0.start < interval.end && $0.end > interval.start }.map(AgendaItem.init(event:))
        let taskItems = reminders.filter { reminder in
            guard !reminder.isCompleted else { return false }
            guard let due = reminder.dueDate else { return true }
            let isDueOnDay = due >= interval.start && due < interval.end
            return isDueOnDay || (includeOverdueTasks && due < interval.start)
        }.map(AgendaItem.init(reminder:))
        let weekday = calendar.component(.weekday, from: interval.start)
        let routineItems = routines.filter { !$0.isPaused && !$0.isArchived && $0.weekdays.contains(weekday) }.map { AgendaItem(routine: $0, completed: completedRoutineIDs.contains($0.id), day: day, calendar: calendar) }
        let all = eventItems + taskItems + routineItems
        return DayAgenda(
            allDay: all.filter { $0.placement == .allDay }.sorted(by: AgendaItem.stableSort),
            scheduled: all.filter { $0.placement.isScheduled }.sorted(by: AgendaItem.stableSort),
            priority: all.filter { $0.placement.isPriority }.sorted(by: AgendaItem.prioritySort)
        )
    }
}

extension AgendaPlacement {
    var isScheduled: Bool {
        switch self { case .timed: true; case let .window(window): window.anchorHour != nil; case .allDay, .unscheduled: false }
    }

    var isPriority: Bool { self == .unscheduled || self == .window(.anytime) }

}

extension AgendaItem {
    init(event: CalendarEventSnapshot) {
        self.init(id: "event|\(event.id)", title: event.title, source: .event, placement: event.isAllDay ? .allDay : .timed(event.start), sortDate: event.isAllDay ? nil : event.start, priority: 0, isCompleted: false, allowsModification: event.allowsModification)
    }

    init(reminder: ReminderSnapshot) {
        let placement: AgendaPlacement = reminder.dueHasTime ? reminder.dueDate.map(AgendaPlacement.timed) ?? .unscheduled : .unscheduled
        self.init(id: "task|\(reminder.id)", title: reminder.title, source: .task, placement: placement, sortDate: reminder.dueHasTime ? reminder.dueDate : nil, priority: reminder.priority, isCompleted: reminder.isCompleted, allowsModification: reminder.allowsModification)
    }

    init(routine: RoutineSnapshot, completed: Bool, day: LocalDay, calendar: Calendar) {
        let placement: AgendaPlacement = .window(routine.window)
        let sortDate: Date?
        if let hour = routine.window.anchorHour {
            sortDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.startDate(in: calendar))!
        } else {
            sortDate = nil
        }
        self.init(id: "routine|\(routine.id.uuidString)|\(day.year)-\(day.month)-\(day.day)", title: routine.title, source: .routine, placement: placement, sortDate: sortDate, priority: 0, isCompleted: completed, allowsModification: true)
    }

    static func stableSort(_ lhs: AgendaItem, _ rhs: AgendaItem) -> Bool {
        switch (lhs.sortDate, rhs.sortDate) {
        case let (left?, right?) where left != right: return left < right
        default: return (lhs.source.rawValue, lhs.title, lhs.id) < (rhs.source.rawValue, rhs.title, rhs.id)
        }
    }

    static func prioritySort(_ lhs: AgendaItem, _ rhs: AgendaItem) -> Bool {
        lhs.priority == rhs.priority ? stableSort(lhs, rhs) : lhs.priority > rhs.priority
    }
}
```

Add named initializers and sort functions to `AgendaItem.swift`. Timed dates sort by date; routine windows sort at 09:00, 13:00, and 18:00; ties sort by source then title; unscheduled tasks sort by higher EventKit priority first and then title.

Calendar passes `includeOverdueTasks: selectedDay == today`; Today always passes `true`.

- [ ] **Step 4: Run composer tests**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/AgendaComposerTests`

Expected: PASS.

- [ ] **Step 5: Commit agenda composition**

Run: `git add PersonalCalendar/Domain/AgendaItem.swift PersonalCalendar/Services/Agenda PersonalCalendarTests/Services/AgendaComposerTests.swift`

Run: `git commit -m "feat: compose unified daily agenda"`

---

### Task 8: Store source selections and assemble live/demo dependencies

**Files:**
- Create: `PersonalCalendar/Settings/AppSettingsStore.swift`
- Modify: `PersonalCalendar/App/AppEnvironment.swift`
- Modify: `PersonalCalendar/App/PersonalCalendarApp.swift`
- Create: `PersonalCalendar/App/DemoEnvironment.swift`
- Modify: `PersonalCalendarTests/Support/Fakes.swift`
- Create: `PersonalCalendarTests/Settings/AppSettingsStoreTests.swift`

**Interfaces:**
- Consumes: all service protocols, `ModelContainer`, and `AgendaComposer`.
- Produces: `AppSettingsStore`, `AppEnvironment.live(container:)`, and `AppEnvironment.demo(container:)`.

- [ ] **Step 1: Write failing isolated-settings test**

```swift
import XCTest
@testable import PersonalCalendar

final class AppSettingsStoreTests: XCTestCase {
    func testSelectedSourcesAndDefaultsRoundTrip() {
        let suite = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let subject = AppSettingsStore(defaults: defaults)

        subject.selectedCalendarIDs = ["home"]
        subject.selectedReminderListIDs = ["tasks"]
        subject.defaultCalendarID = "home"
        subject.defaultReminderListID = "tasks"

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.selectedCalendarIDs, ["home"])
        XCTAssertEqual(reloaded.selectedReminderListIDs, ["tasks"])
        XCTAssertEqual(reloaded.defaultCalendarID, "home")
        XCTAssertEqual(reloaded.defaultReminderListID, "tasks")
    }
}
```

- [ ] **Step 2: Run and confirm settings type is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/AppSettingsStoreTests`

Expected: FAIL with missing `AppSettingsStore`.

- [ ] **Step 3: Implement settings and dependency factories**

```swift
@MainActor
@Observable
final class AppSettingsStore {
    private enum Key {
        static let selectedCalendars = "selectedCalendarIDs"
        static let selectedLists = "selectedReminderListIDs"
        static let defaultCalendar = "defaultCalendarID"
        static let defaultList = "defaultReminderListID"
    }

    private let defaults: UserDefaults
    var selectedCalendarIDs: Set<String> { didSet { defaults.set(Array(selectedCalendarIDs), forKey: Key.selectedCalendars) } }
    var selectedReminderListIDs: Set<String> { didSet { defaults.set(Array(selectedReminderListIDs), forKey: Key.selectedLists) } }
    var defaultCalendarID: String? { didSet { defaults.set(defaultCalendarID, forKey: Key.defaultCalendar) } }
    var defaultReminderListID: String? { didSet { defaults.set(defaultReminderListID, forKey: Key.defaultList) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedCalendarIDs = Set(defaults.stringArray(forKey: Key.selectedCalendars) ?? [])
        selectedReminderListIDs = Set(defaults.stringArray(forKey: Key.selectedLists) ?? [])
        defaultCalendarID = defaults.string(forKey: Key.defaultCalendar)
        defaultReminderListID = defaults.string(forKey: Key.defaultList)
    }
}

extension UserDefaults {
    static var ephemeral: UserDefaults {
        UserDefaults(suiteName: "PersonalCalendarTests.\(UUID().uuidString)")!
    }
}
```

Replace the bootstrap environment from Task 1 with this exact dependency surface:

```swift
@MainActor
struct AppEnvironment {
    let calendar: any CalendarServicing
    let reminders: any RemindersServicing
    let routines: any RoutineRepository
    let notificationAuthorization: any NotificationAuthorizing
    let permissions: PermissionCoordinator
    let agendaComposer: AgendaComposer
    let settings: AppSettingsStore

    static func live(container: ModelContainer) -> AppEnvironment {
        let store = EKEventStore()
        let calendar = EventKitCalendarService(store: store)
        let reminders = EventKitRemindersService(store: store)
        let notifications = SystemNotificationAuthorizer()
        let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        return .init(calendar: calendar, reminders: reminders, routines: SwiftDataRoutineRepository(context: container.mainContext), notificationAuthorization: notifications, permissions: permissions, agendaComposer: AgendaComposer(), settings: AppSettingsStore())
    }

    static func demo(container: ModelContainer, arguments: [String]) -> AppEnvironment {
        let calendarAccess: AccessState = arguments.contains("-calendar-denied") ? .denied : .granted
        let calendar = DemoCalendarService(access: calendarAccess)
        let reminders = DemoRemindersService(access: .granted)
        let notifications = DemoNotificationAuthorizer(access: .granted)
        let permissions = PermissionCoordinator(calendar: calendar, reminders: reminders, notifications: notifications)
        return .init(calendar: calendar, reminders: reminders, routines: DemoRoutineRepository(), notificationAuthorization: notifications, permissions: permissions, agendaComposer: AgendaComposer(), settings: AppSettingsStore(defaults: .ephemeral))
    }
}
```

Implement `DemoCalendarService`, `DemoRemindersService`, `DemoRoutineRepository`, and `DemoNotificationAuthorizer` in `PersonalCalendar/App/DemoEnvironment.swift` with deterministic sample data and in-memory mutations. Production code cannot import test-target types; keep XCTest-only conveniences in `PersonalCalendarTests/Support/Fakes.swift`. `PersonalCalendarApp` builds an in-memory model container and calls `demo` only when arguments contain `-ui-testing`; otherwise it creates the persistent local container and calls `live`.

Use these in-app demo implementations:

```swift
@MainActor
final class DemoCalendarService: CalendarServicing {
    var accessState: AccessState
    private(set) var events: [CalendarEventSnapshot]
    private let descriptor = CalendarDescriptor(id: "demo-calendar", title: "Personal", colorHex: "#3A8D7C", allowsContentModifications: true)

    init(access: AccessState) {
        accessState = access
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now)!
        events = [.init(id: "demo-event", title: "Coffee", start: start, end: start.addingTimeInterval(3_600), isAllDay: false, calendarID: "demo-calendar", calendarTitle: "Personal", allowsModification: true, hasRecurrence: false)]
    }

    func requestFullAccess() async -> AccessState { accessState = .granted; return accessState }
    func calendars() -> [CalendarDescriptor] { [descriptor] }
    func fetchEvents(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEventSnapshot] { accessState == .granted ? events.filter { $0.start < interval.end && $0.end > interval.start } : [] }
    func createEvent(_ draft: EventDraft) throws -> String {
        let id = "demo-event-\(events.count + 1)"
        events.append(.init(id: id, title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay, calendarID: descriptor.id, calendarTitle: descriptor.title, allowsModification: true, hasRecurrence: false))
        return id
    }
}

@MainActor
final class DemoRemindersService: RemindersServicing {
    var accessState: AccessState
    private var values = [ReminderSnapshot(id: "demo-task", title: "Buy milk", notes: nil, dueDate: nil, dueHasTime: false, priority: 5, listID: "demo-list", listTitle: "Tasks", isCompleted: false, allowsModification: true, hasRecurrence: false)]
    private let descriptor = ReminderListDescriptor(id: "demo-list", title: "Tasks", colorHex: "#CB6B4F", allowsContentModifications: true)
    init(access: AccessState) { accessState = access }
    func requestFullAccess() async -> AccessState { accessState = .granted; return accessState }
    func lists() -> [ReminderListDescriptor] { [descriptor] }
    func fetchReminders(listIDs: Set<String>) async -> [ReminderSnapshot] { accessState == .granted ? values : [] }
    func createReminder(_ draft: ReminderDraft) throws -> String {
        let id = "demo-task-\(values.count + 1)"
        values.append(.init(id: id, title: draft.title, notes: draft.notes, dueDate: draft.dueDate, dueHasTime: draft.dueHasTime, priority: draft.priority, listID: descriptor.id, listTitle: descriptor.title, isCompleted: false, allowsModification: true, hasRecurrence: false))
        return id
    }
    func setCompleted(id: String, completed: Bool) throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        let old = values[index]
        values[index] = .init(id: old.id, title: old.title, notes: old.notes, dueDate: old.dueDate, dueHasTime: old.dueHasTime, priority: old.priority, listID: old.listID, listTitle: old.listTitle, isCompleted: completed, allowsModification: old.allowsModification, hasRecurrence: old.hasRecurrence)
    }
}

@MainActor
final class DemoRoutineRepository: RoutineRepository {
    private var values = [RoutineSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Read", weekdays: [1, 2, 3, 4, 5, 6, 7], window: .evening, reminderHour: nil, reminderMinute: nil, isPaused: false, isArchived: false)]
    private var completed: [UUID: Set<LocalDay>] = [:]
    func list(includeArchived: Bool) throws -> [RoutineSnapshot] { includeArchived ? values : values.filter { !$0.isArchived } }
    func create(_ draft: RoutineDraft) throws -> UUID { let id = UUID(); values.append(.init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: false, isArchived: false)); return id }
    func update(id: UUID, draft: RoutineDraft) throws { guard let index = values.firstIndex(where: { $0.id == id }) else { return }; let old = values[index]; values[index] = .init(id: id, title: draft.title, weekdays: draft.weekdays, window: draft.window, reminderHour: draft.reminderHour, reminderMinute: draft.reminderMinute, isPaused: old.isPaused, isArchived: old.isArchived) }
    func setPaused(id: UUID, paused: Bool) throws { mutate(id) { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: $0.window, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, isPaused: paused, isArchived: $0.isArchived) } }
    func setArchived(id: UUID, archived: Bool) throws { mutate(id) { .init(id: $0.id, title: $0.title, weekdays: $0.weekdays, window: $0.window, reminderHour: $0.reminderHour, reminderMinute: $0.reminderMinute, isPaused: $0.isPaused, isArchived: archived) } }
    func delete(id: UUID) throws { values.removeAll { $0.id == id }; completed[id] = nil }
    func setCompleted(routineID: UUID, day: LocalDay, completed state: Bool) throws { if state { completed[routineID, default: []].insert(day) } else { completed[routineID]?.remove(day) } }
    func isCompleted(routineID: UUID, day: LocalDay) throws -> Bool { completed[routineID, default: []].contains(day) }
    func completedDays(routineID: UUID) throws -> Set<LocalDay> { completed[routineID, default: []] }
    private func mutate(_ id: UUID, _ transform: (RoutineSnapshot) -> RoutineSnapshot) { if let index = values.firstIndex(where: { $0.id == id }) { values[index] = transform(values[index]) } }
}

@MainActor
final class DemoNotificationAuthorizer: NotificationAuthorizing {
    private var state: AccessState
    init(access: AccessState) { state = access }
    var accessState: AccessState { get async { state } }
    func requestAccess() async -> AccessState { state = .granted; return state }
}
```

`AppEnvironment.live(container:)` must construct one shared `EKEventStore`, both EventKit services, one `SwiftDataRoutineRepository(container.mainContext)`, a system notification authorizer, one `PermissionCoordinator`, one `AgendaComposer`, and one `AppSettingsStore`. `AppEnvironment.demo(container:)` must use deterministic fake events, reminders, and routines when the `-ui-testing` launch argument is present.

- [ ] **Step 4: Run settings tests and launch UI test**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/AppSettingsStoreTests -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testLaunchShowsFourPrimaryTabs`

Expected: PASS without showing system permission prompts in demo mode.

- [ ] **Step 5: Commit settings and dependency assembly**

Run: `git add PersonalCalendar/App PersonalCalendar/Settings PersonalCalendarTests/Settings PersonalCalendarTests/Support`

Run: `git commit -m "feat: assemble local app environment"`

---

### Task 9: Build the month grid and draggable day tray

**Files:**
- Create: `PersonalCalendar/Features/Calendar/MonthGridBuilder.swift`
- Create: `PersonalCalendar/Features/Calendar/CalendarViewModel.swift`
- Create: `PersonalCalendar/Features/Calendar/CalendarHomeView.swift`
- Create: `PersonalCalendar/Features/Calendar/MonthGridView.swift`
- Create: `PersonalCalendar/Features/Calendar/DayTrayView.swift`
- Create: `PersonalCalendar/Features/Calendar/NewEventSheet.swift`
- Create: `PersonalCalendarTests/Features/MonthGridBuilderTests.swift`
- Create: `PersonalCalendarTests/Features/CalendarViewModelTests.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`

**Interfaces:**
- Consumes: `AppEnvironment`, source services, routine repository, `AgendaComposer`, and settings.
- Produces: `MonthGridBuilder`, `CalendarViewModel`, `TrayState`, and `CalendarHomeView`.

- [ ] **Step 1: Write failing 42-cell grid and selection tests**

```swift
import XCTest
@testable import PersonalCalendar

final class MonthGridBuilderTests: XCTestCase {
    func testAugust2026BuildsSixCompleteWeeks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = LocalDay(year: 2026, month: 8, day: 1)

        let result = MonthGridBuilder(calendar: calendar).days(containing: month)

        XCTAssertEqual(result.count, 42)
        XCTAssertEqual(result.first?.day, LocalDay(year: 2026, month: 7, day: 26))
        XCTAssertEqual(result.last?.day, LocalDay(year: 2026, month: 9, day: 5))
    }
}
```

- [ ] **Step 2: Run and confirm grid builder is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/MonthGridBuilderTests`

Expected: FAIL with missing `MonthGridBuilder`.

- [ ] **Step 3: Implement grid, view model, and tray states**

```swift
struct CalendarCell: Identifiable, Equatable {
    let day: LocalDay
    let belongsToDisplayedMonth: Bool
    var id: LocalDay { day }
}

struct MonthGridBuilder {
    let calendar: Calendar

    func days(containing month: LocalDay) -> [CalendarCell] {
        let first = month.startDate(in: calendar)
        let weekdayOffset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: first)!
        return (0..<42).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            let day = LocalDay(date: date, calendar: calendar)
            return CalendarCell(day: day, belongsToDisplayedMonth: day.month == month.month && day.year == month.year)
        }
    }
}

enum TrayState: Equatable { case resting, expanded }

@MainActor
@Observable
final class CalendarViewModel {
    var displayedMonth: LocalDay
    var selectedDay: LocalDay
    var trayState: TrayState = .resting
    private(set) var agenda = DayAgenda(allDay: [], scheduled: [], priority: [])
    private(set) var errorMessage: String?
    private(set) var eventDraftOnFailure: EventDraft?
    private(set) var isLoading = false
    private var cachedEvents: [CalendarEventSnapshot] = []
    private var cachedReminders: [ReminderSnapshot] = []
    private var cachedRoutines: [RoutineSnapshot] = []
    private let today: LocalDay
    private let calendarService: any CalendarServicing
    private let remindersService: any RemindersServicing
    private let routines: any RoutineRepository
    private let composer: AgendaComposer
    private let settings: AppSettingsStore
    private let systemCalendar: Calendar

    init(today: LocalDay, calendarService: any CalendarServicing, remindersService: any RemindersServicing, routines: any RoutineRepository, composer: AgendaComposer, settings: AppSettingsStore, systemCalendar: Calendar) {
        self.today = today
        self.calendarService = calendarService
        self.remindersService = remindersService
        self.routines = routines
        self.composer = composer
        self.settings = settings
        self.systemCalendar = systemCalendar
        displayedMonth = LocalDay(year: today.year, month: today.month, day: 1)
        selectedDay = today
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let cells = MonthGridBuilder(calendar: systemCalendar).days(containing: displayedMonth)
        let start = cells.first!.day.startDate(in: systemCalendar)
        let end = systemCalendar.date(byAdding: .day, value: 1, to: cells.last!.day.startDate(in: systemCalendar))!
        do {
            if calendarService.accessState == .granted { cachedEvents = try calendarService.fetchEvents(in: .init(start: start, end: end), calendarIDs: settings.selectedCalendarIDs) } else { cachedEvents = [] }
            if remindersService.accessState == .granted { cachedReminders = await remindersService.fetchReminders(listIDs: settings.selectedReminderListIDs) } else { cachedReminders = [] }
            cachedRoutines = try routines.list(includeArchived: false)
            try rebuildSelectedAgenda()
            errorMessage = nil
        } catch {
            errorMessage = "Your schedule could not be refreshed. Try again."
        }
    }

    func select(_ day: LocalDay) async { selectedDay = day; try? rebuildSelectedAgenda() }
    func setTray(_ state: TrayState) { trayState = state }
    func showToday() async { selectedDay = today; displayedMonth = .init(year: today.year, month: today.month, day: 1); await load() }
    func moveMonth(by value: Int) async {
        let moved = systemCalendar.date(byAdding: .month, value: value, to: displayedMonth.startDate(in: systemCalendar))!
        displayedMonth = LocalDay(date: moved, calendar: systemCalendar)
        await load()
    }

    func createEvent(_ draft: EventDraft) async {
        do {
            _ = try calendarService.createEvent(draft)
            eventDraftOnFailure = nil
            await load()
        } catch {
            eventDraftOnFailure = draft
            errorMessage = "Your event was not saved. You can try again."
        }
    }

    private func rebuildSelectedAgenda() throws {
        let completed = Set(try cachedRoutines.filter { try routines.isCompleted(routineID: $0.id, day: selectedDay) }.map(\.id))
        agenda = composer.compose(day: selectedDay, events: cachedEvents, reminders: cachedReminders, routines: cachedRoutines, completedRoutineIDs: completed, includeOverdueTasks: selectedDay == today, calendar: systemCalendar)
    }
}
```

A denied source contributes an empty array and a permission card, not an error screen. Expose `load()` as the retry action; because the view model stores only the last confirmed snapshots, a failed refresh never destroys an editor draft.

Build `CalendarHomeView` as a `VStack`: month header, either a six-week `MonthGridView` or selected-week strip, then `DayTrayView`. Use a vertical `DragGesture(minimumDistance: 20)` with a 60-point threshold. Add a visible button labeled “Expand day” or “Collapse day,” and disable motion animation when `accessibilityReduceMotion` is true.

In the resting state, `DayTrayView` shows the selected date, the next timed event, the highest-priority due task, and the next incomplete routine, omitting absent rows. In the expanded state it renders `DayAgenda` as All Day, Schedule, and Priority sections. Month cells show at most three compact source-colored indicators plus a “+N” count; Plan 2 replaces source colors with app categories where assigned.

Add a toolbar button labeled “New Event.” `NewEventSheet` edits title, all-day state, start, end, and a writable calendar, defaulting to `settings.defaultCalendarID`. It calls `createEvent(_:)`, stays presented on failure, restores `eventDraftOnFailure`, and shows Retry.

- [ ] **Step 4: Run unit and focused UI tests**

Extend `FoundationFlowUITests` with `testCalendarDateSelectionAndAccessibleTrayButton` using the demo environment. Assert the current date button exists, tap “Expand day,” and assert “Collapse day” appears.

Add `testCreateBasicEventInDemoMode`: tap “New Event,” enter “Dentist,” choose a time, save, and assert “Dentist” appears in the selected-day tray.

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/MonthGridBuilderTests -only-testing:PersonalCalendarTests/CalendarViewModelTests -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testCalendarDateSelectionAndAccessibleTrayButton -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testCreateBasicEventInDemoMode`

Expected: PASS.

- [ ] **Step 5: Commit Calendar home**

Run: `git add PersonalCalendar/Features/Calendar PersonalCalendar/App/RootTabView.swift PersonalCalendarTests/Features PersonalCalendarUITests/FoundationFlowUITests.swift`

Run: `git commit -m "feat: add month calendar and day tray"`

---

### Task 10: Build the Today agenda

**Files:**
- Create: `PersonalCalendar/Features/Today/TodayViewModel.swift`
- Create: `PersonalCalendar/Features/Today/TodayView.swift`
- Create: `PersonalCalendar/DesignSystem/AgendaRow.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `PersonalCalendarTests/Features/FeatureViewModelTests.swift`
- Modify: `PersonalCalendarUITests/FoundationFlowUITests.swift`

**Interfaces:**
- Consumes: `DayAgenda`, `AgendaComposer`, all repositories, permissions, and `CalendarTheme`.
- Produces: `TodayViewModel`, `TodayView`, and reusable `AgendaRow`.

- [ ] **Step 1: Write failing current-day and denied-source tests**

```swift
@MainActor
func testTodayLoadsAvailableSourcesWhenCalendarIsDenied() async {
    let calendar = FakeCalendarService(access: .denied)
    let reminders = FakeRemindersService(access: .granted, reminders: [.sampleTask])
    let routines = FakeRoutineRepository(routines: [.sampleRoutine])
    let subject = TodayViewModel(calendar: calendar, reminders: reminders, routines: routines, composer: AgendaComposer(), calendarProvider: { .current }, now: { Date(timeIntervalSince1970: 1_787_500_800) })

    await subject.load()

    XCTAssertNil(subject.fatalErrorMessage)
    XCTAssertEqual(subject.agenda.priority.count, 1)
    XCTAssertTrue(subject.showsCalendarPermissionCard)
}
```

- [ ] **Step 2: Run and confirm Today view model is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests`

Expected: FAIL with missing `TodayViewModel`.

- [ ] **Step 3: Implement Today loading and sectioned UI**

```swift
@MainActor
@Observable
final class TodayViewModel {
    private(set) var agenda = DayAgenda(allDay: [], scheduled: [], priority: [])
    private(set) var isLoading = false
    private(set) var fatalErrorMessage: String?
    var showsCalendarPermissionCard = false
    var showsRemindersPermissionCard = false
    private let calendar: any CalendarServicing
    private let reminders: any RemindersServicing
    private let routines: any RoutineRepository
    private let composer: AgendaComposer
    private let calendarProvider: () -> Calendar
    private let now: () -> Date

    init(calendar: any CalendarServicing, reminders: any RemindersServicing, routines: any RoutineRepository, composer: AgendaComposer, calendarProvider: @escaping () -> Calendar, now: @escaping () -> Date) {
        self.calendar = calendar
        self.reminders = reminders
        self.routines = routines
        self.composer = composer
        self.calendarProvider = calendarProvider
        self.now = now
    }

    func load() async {
        isLoading = true
        fatalErrorMessage = nil
        defer { isLoading = false }
        let systemCalendar = calendarProvider()
        let localDay = LocalDay(date: now(), calendar: systemCalendar)
        showsCalendarPermissionCard = calendar.accessState != .granted
        showsRemindersPermissionCard = reminders.accessState != .granted
        let start = localDay.startDate(in: systemCalendar)
        let end = systemCalendar.date(byAdding: .day, value: 1, to: start)!
        var events: [CalendarEventSnapshot] = []
        if calendar.accessState == .granted {
            do { events = try calendar.fetchEvents(in: .init(start: start, end: end), calendarIDs: []) }
            catch { fatalErrorMessage = "Calendar events could not be refreshed. Pull to try again." }
        }
        let tasks = reminders.accessState == .granted ? await reminders.fetchReminders(listIDs: []) : []
        do {
            let routineValues = try routines.list(includeArchived: false)
            let completed = Set(try routineValues.filter { try routines.isCompleted(routineID: $0.id, day: localDay) }.map(\.id))
            agenda = composer.compose(day: localDay, events: events, reminders: tasks, routines: routineValues, completedRoutineIDs: completed, includeOverdueTasks: true, calendar: systemCalendar)
        } catch {
            fatalErrorMessage = "Your routines could not be refreshed. Pull to try again."
        }
    }
}
```

Implement `TodayView` with sections in this exact order: All Day, Schedule, Priority. Hide empty sections. Show source-specific icons and a completion control only for tasks and routines. Use `.task { await model.load() }`, `.refreshable`, `ContentUnavailableView` for a genuinely empty day, and inline permission cards that navigate to Settings.

- [ ] **Step 4: Run model and UI tests**

Add `testTodayTabShowsDemoAgenda` to the UI test, tap Today, and assert “All Day,” “Schedule,” or “Priority” plus at least one demo item.

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testTodayTabShowsDemoAgenda`

Expected: PASS.

- [ ] **Step 5: Commit Today**

Run: `git add PersonalCalendar/Features/Today PersonalCalendar/DesignSystem/AgendaRow.swift PersonalCalendar/App/RootTabView.swift PersonalCalendarTests/Features PersonalCalendarUITests/FoundationFlowUITests.swift`

Run: `git commit -m "feat: add unified today agenda"`

---

### Task 11: Build basic Tasks and Routines flows

**Files:**
- Create: `PersonalCalendar/Features/Tasks/TasksViewModel.swift`
- Create: `PersonalCalendar/Features/Tasks/TasksView.swift`
- Create: `PersonalCalendar/Features/Tasks/NewTaskSheet.swift`
- Create: `PersonalCalendar/Features/Routines/RoutinesViewModel.swift`
- Create: `PersonalCalendar/Features/Routines/RoutinesView.swift`
- Create: `PersonalCalendar/Features/Routines/RoutineEditorView.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `PersonalCalendarTests/Features/FeatureViewModelTests.swift`
- Modify: `PersonalCalendarUITests/FoundationFlowUITests.swift`

**Interfaces:**
- Consumes: `RemindersServicing`, `RoutineRepository`, settings defaults, and the domain drafts.
- Produces: basic task create/complete and routine create/edit/pause/archive/complete UI flows.

- [ ] **Step 1: Write failing task and routine action tests**

```swift
@MainActor
func testTaskCompletionRefreshesFromService() async throws {
    let service = FakeRemindersService(access: .granted, reminders: [.sampleTask])
    let subject = TasksViewModel(service: service, settings: AppSettingsStore(defaults: .ephemeral))
    await subject.load()

    await subject.setCompleted(id: "task", completed: true)

    XCTAssertEqual(service.completedCalls, [CompletionCall(id: "task", completed: true)])
}

@MainActor
func testRoutineCompletionUpdatesRepository() async {
    let repository = FakeRoutineRepository(routines: [.sampleRoutine])
    let subject = RoutinesViewModel(repository: repository, calendar: .current, now: { .now })

    await subject.setCompleted(id: RoutineSnapshot.sampleRoutine.id, completed: true)

    XCTAssertEqual(repository.completionCalls.count, 1)
}
```

- [ ] **Step 2: Run tests and confirm feature models are missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests`

Expected: FAIL with missing feature models.

- [ ] **Step 3: Implement basic models and forms**

```swift
@MainActor
@Observable
final class TasksViewModel {
    private(set) var today: [ReminderSnapshot] = []
    private(set) var upcoming: [ReminderSnapshot] = []
    private(set) var completed: [ReminderSnapshot] = []
    private(set) var draftOnFailure: ReminderDraft?
    private(set) var errorMessage: String?
    private let service: any RemindersServicing
    private let settings: AppSettingsStore

    init(service: any RemindersServicing, settings: AppSettingsStore) {
        self.service = service
        self.settings = settings
    }

    func load() async {
        let values = await service.fetchReminders(listIDs: settings.selectedReminderListIDs)
        let start = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        today = values.filter { !$0.isCompleted && ($0.dueDate.map { $0 < tomorrow } ?? false) }
        upcoming = values.filter { !$0.isCompleted && ($0.dueDate.map { $0 >= tomorrow } ?? true) }
        completed = values.filter(\.isCompleted)
    }

    func create(_ draft: ReminderDraft) async {
        do {
            _ = try service.createReminder(draft)
            draftOnFailure = nil
            await load()
        } catch {
            draftOnFailure = draft
            errorMessage = "Your task was not saved. You can try again."
        }
    }

    func setCompleted(id: String, completed: Bool) async {
        do { try service.setCompleted(id: id, completed: completed); await load() }
        catch { errorMessage = "Your task was not changed. Try again." }
    }
}

@MainActor
@Observable
final class RoutinesViewModel {
    private(set) var active: [RoutineSnapshot] = []
    private(set) var archived: [RoutineSnapshot] = []
    private(set) var errorMessage: String?
    private(set) var draftOnFailure: RoutineDraft?
    private let repository: any RoutineRepository
    private let calendar: Calendar
    private let now: () -> Date

    init(repository: any RoutineRepository, calendar: Calendar, now: @escaping () -> Date) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    func reload() {
        do {
            let all = try repository.list(includeArchived: true)
            active = all.filter { !$0.isArchived }
            archived = all.filter(\.isArchived)
        } catch {
            errorMessage = "Your routines could not be loaded."
        }
    }

    func setCompleted(id: UUID, completed: Bool) async {
        let day = LocalDay(date: now(), calendar: calendar)
        do { try repository.setCompleted(routineID: id, day: day, completed: completed); reload() }
        catch { errorMessage = "Your routine was not changed. Try again." }
    }

    func create(_ draft: RoutineDraft) {
        do { _ = try repository.create(draft); draftOnFailure = nil; reload() }
        catch { draftOnFailure = draft; errorMessage = "Your routine was not saved. You can try again." }
    }

    func update(id: UUID, draft: RoutineDraft) {
        do { try repository.update(id: id, draft: draft); draftOnFailure = nil; reload() }
        catch { draftOnFailure = draft; errorMessage = "Your routine was not saved. You can try again." }
    }

    func setPaused(id: UUID, paused: Bool) { do { try repository.setPaused(id: id, paused: paused); reload() } catch { errorMessage = "Your routine was not changed. Try again." } }
    func setArchived(id: UUID, archived: Bool) { do { try repository.setArchived(id: id, archived: archived); reload() } catch { errorMessage = "Your routine was not changed. Try again." } }
    func delete(id: UUID) { do { try repository.delete(id: id); reload() } catch { errorMessage = "Your routine was not deleted. Try again." } }
}
```

Tasks UI groups incomplete reminders into Today and Upcoming based on due date and shows a separate Completed disclosure group. The creation sheet includes title, notes, due date toggle, due time toggle, priority, and writable list. Routines UI includes title, weekday buttons, one of four windows, optional reminder time, pause, archive, delete, and completion. Each active routine displays its current streak and a 14-day completion strip. All failed creates keep the draft and show Retry.

- [ ] **Step 4: Add and run end-to-end demo UI tests**

Add `testCreateTaskAndCompleteRoutineInDemoMode`: launch with `-ui-testing`, create “Call Alex” through Tasks, verify it appears, open Routines, tap the demo “Read” completion button, verify its accessibility value becomes “Completed,” and assert the routine announces “1 day streak” with a 14-day history element.

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarTests/FeatureViewModelTests -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testCreateTaskAndCompleteRoutineInDemoMode`

Expected: PASS.

- [ ] **Step 5: Commit Tasks and Routines**

Run: `git add PersonalCalendar/Features/Tasks PersonalCalendar/Features/Routines PersonalCalendar/App/RootTabView.swift PersonalCalendarTests/Features PersonalCalendarUITests/FoundationFlowUITests.swift`

Run: `git commit -m "feat: add task and routine flows"`

---

### Task 12: Add Settings, permission education, and foundation verification

**Files:**
- Create: `PersonalCalendar/Features/Settings/SettingsView.swift`
- Create: `PersonalCalendar/Features/Settings/PermissionCard.swift`
- Create: `PersonalCalendar/Features/Onboarding/PermissionOnboardingView.swift`
- Modify: `PersonalCalendar/App/RootTabView.swift`
- Modify: `PersonalCalendarUITests/FoundationFlowUITests.swift`
- Create: `README.md`

**Interfaces:**
- Consumes: `PermissionCoordinator`, source descriptors, and `AppSettingsStore`.
- Produces: a toolbar Settings route, independent permission actions, source filtering, and the complete foundation milestone.

- [ ] **Step 1: Write failing UI tests for denied and granted states**

```swift
func testSettingsExplainsDeniedCalendarWithoutBlockingRoutines() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-calendar-denied"]
    app.launch()
    app.buttons["Settings"].tap()

    XCTAssertTrue(app.staticTexts["Calendar access is off"].waitForExistence(timeout: 2))
    app.buttons["Done"].tap()
    app.tabBars.buttons["Routines"].tap()
    XCTAssertTrue(app.navigationBars["Routines"].exists)
}
```

- [ ] **Step 2: Run and verify Settings route is missing**

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PersonalCalendarUITests/FoundationFlowUITests/testSettingsExplainsDeniedCalendarWithoutBlockingRoutines`

Expected: FAIL because the Settings route does not exist.

- [ ] **Step 3: Implement permission and source settings**

```swift
struct PermissionCard: View {
    let title: String
    let explanation: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(explanation).font(.subheadline).foregroundStyle(.secondary)
            Button(actionTitle, action: action).frame(minHeight: CalendarTheme.minimumTapSize)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: CalendarTheme.cornerRadius))
    }
}
```

`SettingsView` must display Calendar, Reminders, and Notifications separately; request only the tapped permission; show “Open System Settings” after denial using `UIApplication.openSettingsURLString`; list all visible source toggles; allow default selection only from writable destinations; and leave Routines usable when every system permission is denied. An empty stored source set means “all available sources” on first use; after the first toggle, persist the explicit selection and prevent deselecting the final source of that type.

Add `didCompleteOnboarding` to `AppSettingsStore`. On first launch, present `PermissionOnboardingView` before the tab content. It has three short pages in this order: Calendar, Reminders, Notifications. Each page offers “Allow” and “Not Now”; only “Allow” requests that page's permission, and either choice advances one page. Finishing or skipping all three sets `didCompleteOnboarding = true`. UI-test demo settings set it to true unless launch arguments contain `-show-onboarding`.

Update `README.md` with exact local commands:

```markdown
# Personal Calendar

Generate the project with `xcodegen generate`.

Build with `xcodebuild build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`.

Run tests with `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

The app stores events in Apple Calendar, tasks in Apple Reminders, and routines locally with SwiftData. It has no backend or CloudKit entitlement.
```

- [ ] **Step 4: Run the complete foundation verification**

Run: `xcodegen generate`

Run: `xcodebuild clean build -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'generic/platform=iOS Simulator'`

Run: `xcodebuild test -project PersonalCalendar.xcodeproj -scheme PersonalCalendar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

Run: `git diff --check`

Expected: build PASS, all unit/UI tests PASS, and `git diff --check` produces no output.

- [ ] **Step 5: Perform accessibility and degraded-mode checks**

On the simulator, verify these exact states:

```text
Calendar denied + Reminders granted: tasks and routines remain visible.
Calendar granted + Reminders denied: events and routines remain visible.
Both denied: Calendar and Today show routine content plus permission cards.
Extra-extra-extra-large text: tab labels, date cells, and forms do not clip essential text.
VoiceOver: every date announces date, selection, today state, and item count.
Reduce Motion: tray switches state without a large spring animation.
Dark Mode: text, categories, disabled actions, and permission cards remain legible.
```

- [ ] **Step 6: Commit the verified foundation milestone**

Run: `git add PersonalCalendar/Features/Settings PersonalCalendar/Features/Onboarding PersonalCalendar/Settings/AppSettingsStore.swift PersonalCalendar/App/RootTabView.swift PersonalCalendarUITests README.md`

Run: `git commit -m "feat: complete personal calendar foundation"`

Run: `git status --short`

Expected: no output.

## Foundation exit criteria

- The generated project builds without CloudKit or third-party runtime dependencies.
- The four-tab shell and Settings route are usable with VoiceOver and large text.
- Calendar and Reminders permissions can be granted or denied independently.
- Accessible Apple events and reminders appear through value snapshots rather than persisted copies.
- A user can create a basic event, create or complete a basic reminder, and create or complete a routine.
- Calendar shows a six-week month with a resting/expanded day tray.
- Today combines all available sources in deterministic sections.
- Routines and completion history survive relaunch through local SwiftData.
- Denied permissions never make the app unusable.
- The full unit and UI test suites pass.

## Primary Apple references

- [Accessing the Event Store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [Accessing Calendar Using EventKit and EventKitUI](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui)
- [Creating a Recurring Event or Reminder](https://developer.apple.com/documentation/eventkit/creating-a-recurring-event)
- [SwiftData ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
